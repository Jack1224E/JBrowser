import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../services/path_resolver.dart';

enum EngineStatus { disconnected, starting, connected, error }

class EngineProcessState {
  final EngineStatus status;
  final int? pid;
  final String? error;

  EngineProcessState({
    required this.status,
    this.pid,
    this.error,
  });

  factory EngineProcessState.initial() => EngineProcessState(status: EngineStatus.disconnected);
}

class EngineProcessNotifier extends StateNotifier<EngineProcessState> {
  Process? _process;
  int _healAttempts = 0;
  bool _intentionalStop = false;

  EngineProcessNotifier() : super(EngineProcessState.initial()) {
    _registerShutdownHooks();
  }

  void _registerShutdownHooks() {
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) async {
        await _saveSessionRpc();
        exit(0);
      });
      ProcessSignal.sigint.watch().listen((_) async {
        await _saveSessionRpc();
        exit(0);
      });
    }
  }

  Future<void> _saveSessionRpc() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
      final req = await client.post('127.0.0.1', 6800, '/jsonrpc');
      req.headers.contentType = ContentType.json;
      req.write('{"jsonrpc":"2.0","id":"exit","method":"aria2.saveSession","params":[]}');
      final res = await req.close();
      if (res.statusCode == 200) {
        stderr.writeln('[EngineGuard] Successfully saved aria2 session before exit.');
      }
    } catch (e) {
      stderr.writeln('[EngineGuard] save_session_rpc failed: $e');
    }
  }

  void _scheduleHeal() {
    if (_intentionalStop) return;
    if (_healAttempts > 5) {
      stderr.writeln('[EngineGuard] Max heal attempts reached. Giving up.');
      return;
    }
    _healAttempts++;
    final backoff = Duration(seconds: 2 * _healAttempts);
    stderr.writeln('[EngineGuard] Scheduling auto-heal in ${backoff.inSeconds}s (Attempt $_healAttempts)');
    Future.delayed(backoff, () {
      if (state.status == EngineStatus.error || state.status == EngineStatus.disconnected) {
        start();
      }
    });
  }

  Future<void> start() async {
    if (state.status == EngineStatus.starting || state.status == EngineStatus.connected) return;

    state = EngineProcessState(status: EngineStatus.starting);
    _intentionalStop = false;

    try {
      final logFile = File('/tmp/switchboard_engine.log');
      final bootTraceFile = File('${Platform.environment['HOME']}/.local/state/jbrowser/boot_trace.log');
      await logFile.writeAsString('[${DateTime.now()}] SOTA Guard Log Started\n', mode: FileMode.write);
      void log(String msg) {
        stderr.writeln(msg);
        logFile.writeAsStringSync('$msg\n', mode: FileMode.append, flush: true);
        try {
          final hrNow = DateTime.now().millisecondsSinceEpoch;
          bootTraceFile.writeAsStringSync('[$hrNow] [Flutter EngineGuard] $msg\n', mode: FileMode.append, flush: true);
        } catch (_) {}
      }

      log('[EngineGuard] Reclamation start...');
      await _reclaimStalePort();

      final aria2cPath = await PirPathResolver.findAria2c();
      final sessionFile = await PirPathResolver.getSessionFilePath();
      
      log('[EngineGuard] Binary: $aria2cPath');
      log('[EngineGuard] Session: $sessionFile');

      final args = <String>[
        '--enable-rpc',
        '--rpc-listen-all=false',
        '--rpc-listen-port=6800',
        '--max-connection-per-server=16',
        '--split=16',
        '--min-split-size=1M',
        '--save-session=$sessionFile',
        '--save-session-interval=30',
        '--continue=true',
        '--always-resume=true',
        '--force-save=false'
      ];
      
      // SOTA: Only attach input-file if it physically exists. Otherwise aria2c throws Exit Code 1 instantly!
      final f = File(sessionFile);
      Directory(f.parent.path).createSync(recursive: true);
      if (f.existsSync()) {
        final stat = f.statSync();
        if (stat.size > 0) {
           log('[EngineGuard] Verified session file: ${stat.size} bytes. Initializing rehydration...');
           args.add('--input-file=$sessionFile');
        } else {
           log('[EngineGuard] Session file is empty. Proceeding with clear session.');
        }
      }

      log('[EngineGuard] Args: ${args.join(' ')}');

      _process = await Process.start(aria2cPath, args);

      _process?.stderr.listen((data) {
        final msg = String.fromCharCodes(data);
        log('[ARIA2C_FATAL] $msg');
      });

      _process?.stdout.listen((data) {
        final msg = String.fromCharCodes(data);
        log('[aria2c_RAW_STDOUT] $msg');
      });

      _process?.exitCode.then((code) async {
        state = EngineProcessState(
          status: EngineStatus.error,
          error: 'Engine exited with code $code',
        );
        _process = null;

        // Fatal Initialization Check (Exit 1)
        if (code == 1 && _healAttempts == 0) {
          log('[EngineGuard] FATAL: Aria2c threw Exit Code 1. Purging corrupted session file and hard-rebooting.');
          if (f.existsSync()) f.deleteSync();
        }

        if (!_intentionalStop) _scheduleHeal();
      });

      // Warm-up phase: Wait for RPC to be available
      await _waitForRpc();

      _healAttempts = 0; // Reset heal tracking on strict successful connection
      state = EngineProcessState(
        status: EngineStatus.connected,
        pid: _process?.pid,
      );
    } catch (e) {
      state = EngineProcessState(status: EngineStatus.error, error: e.toString());
      if (!_intentionalStop) _scheduleHeal();
    }
  }

  Future<void> _waitForRpc() async {
    for (int i = 0; i < 10; i++) {
      try {
        final socket = await Socket.connect('127.0.0.1', 6800, timeout: const Duration(seconds: 1));
        await socket.close();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    throw Exception('Timeout waiting for aria2c RPC server to start.');
  }

  Future<void> _reclaimStalePort() async {
    try {
      // 1. Gatekeeper Validation & Security check
      final lsofCheck = await Process.run('which', ['lsof']);
      if (lsofCheck.exitCode != 0) {
        stderr.writeln('[Reclaimer] WARNING: lsof not found. Stale port reclamation bypassed.');
        return;
      }

      // 2. PID Discovery (Direct invocation, no shell injection)
      try {
        final result = await Process.run('lsof', ['-ti', ':6800']);
        bool killedAny = false;

        if (result.stdout.toString().trim().isNotEmpty) {
          final pids = result.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty);
          
          for (final pid in pids) {
            // 3. Surgical Verification
            final nameResult = await Process.run('ps', ['-p', pid, '-o', 'comm=']);
            if (nameResult.stdout.toString().contains('aria2c')) {
              stderr.writeln('[Reclaimer] Reclaiming port 6800 from zombie aria2c (PID: $pid)');
              final killRes = await Process.run('kill', ['-9', pid]);
              if (killRes.exitCode == 0) killedAny = true;
            } else {
              stderr.writeln('[Reclaimer] Port 6800 occupied by non-aria2c process (PID: $pid), skipping.');
            }
          }
        }

        // 3b. Secondary Pgrep Validation (Catches initializing daemons lsof misses)
        final pgrepResult = await Process.run('pgrep', ['-x', 'aria2c']);
        if (pgrepResult.stdout.toString().trim().isNotEmpty) {
           final pids = pgrepResult.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty);
           for (final pid in pids) {
              stderr.writeln('[Reclaimer] Reclaiming stray aria2c daemon (PID: $pid) via pgrep');
              final killRes = await Process.run('kill', ['-9', pid]);
              if (killRes.exitCode == 0) killedAny = true;
           }
        }
          
        // 4. OS Release Barrier (Exact SOTA timing)
        if (killedAny) {
            stderr.writeln('[Reclaimer] Port reclaimed. Sleeping 300ms to allow OS socket release.');
            await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        stderr.writeln('[RECLAIM_ERR] Failed to execute lsof: $e');
      }
    } catch (e) {
      stderr.writeln('[Reclaimer] Stale port check failed: $e');
    }
  }

  Future<void> stop() async {
    _intentionalStop = true;
    await _saveSessionRpc();
    _process?.kill();
    _process = null;
    state = EngineProcessState.initial();
  }
}

final engineProcessProvider = StateNotifierProvider<EngineProcessNotifier, EngineProcessState>((ref) {
  return EngineProcessNotifier();
});
