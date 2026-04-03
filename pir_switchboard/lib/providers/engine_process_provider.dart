import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/legacy.dart';
import '../services/path_resolver.dart';


enum EngineStatus { disconnected, starting, connected, error }

class EngineProcessState {
  final EngineStatus status;
  final String? error;
  final int? pid;

  EngineProcessState({required this.status, this.error, this.pid});

  factory EngineProcessState.initial() => EngineProcessState(status: EngineStatus.disconnected);
}

class EngineProcessNotifier extends StateNotifier<EngineProcessState> {
  Process? _process;

  EngineProcessNotifier() : super(EngineProcessState.initial());

  Future<void> start() async {
    if (state.status == EngineStatus.starting || state.status == EngineStatus.connected) return;

    state = EngineProcessState(status: EngineStatus.starting);

    try {
      // 1. Check if an engine is already running on port 6800
      try {
        final socket = await Socket.connect('127.0.0.1', 6800, timeout: const Duration(milliseconds: 500));
        await socket.close();
        // Port is active, assume engine is already running
        state = EngineProcessState(status: EngineStatus.connected);
        return;
      } catch (_) {
        // Proceed to start a new engine
      }

      final aria2cPath = await PirPathResolver.findAria2c();
      final sessionFile = await PirPathResolver.getSessionFilePath();

      _process = await Process.start(
        aria2cPath,
        [
          '--enable-rpc',
          '--rpc-listen-all=false',
          '--rpc-listen-port=6800',
          '--input-file=$sessionFile',
          '--save-session=$sessionFile',
          '--save-session-interval=60',
          '--max-connection-per-server=16',
          '--split=16',
          '--min-split-size=1M',
        ],
      );

      _process?.exitCode.then((code) {
        state = EngineProcessState(
          status: EngineStatus.error,
          error: 'Engine exited with code $code',
        );
        _process = null;
      });

      // Warm-up phase: Wait for RPC to be available
      await _waitForRpc();

      // UDS Server is now started by AppLifecycleObserver in main.dart

      state = EngineProcessState(
        status: EngineStatus.connected,
        pid: _process?.pid,
      );
    } catch (e) {
      state = EngineProcessState(status: EngineStatus.error, error: e.toString());
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

  void stop() {
    _process?.kill();
    _process = null;
    state = EngineProcessState.initial();
  }
}

final engineProcessProvider = StateNotifierProvider<EngineProcessNotifier, EngineProcessState>((ref) {
  return EngineProcessNotifier();
});
