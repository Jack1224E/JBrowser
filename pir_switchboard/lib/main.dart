import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/engine_process_provider.dart';
import 'providers/download_list_provider.dart';
import 'widgets/download_tile.dart';
import 'engine/pir_engine_client.dart';
import 'models/download_status.dart';
import 'services/vault_queue_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/tray_service.dart';
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Singleton Guard Phase
  await _checkInstanceSingleton(args);
  
  // Phase 2: Ghost Lifecycle - Window Initialization
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'Pir Switchboard — Secured Vault',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    // Ghost Mode: Intercept "X" to hide instead of kill
    await windowManager.setPreventClose(true);
  });

  // The Boot Gate logic has been moved to AppLifecycleObserver's _executeBootGate 
  // so the Flutter UI can mount and render a secure "System Initializing" lock screen.
  final container = ProviderContainer();

  // 3. Tray Initialization
  await container.read(trayServiceProvider).init(container);

  // Parse named CLI arguments
  String? initialUrl;
  String? initialRequestId;
  String? initialGid;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--download-url' && i + 1 < args.length) {
      initialUrl = args[i + 1];
    } else if (args[i] == '--request-id' && i + 1 < args.length) {
      initialRequestId = args[i + 1];
    } else if (args[i] == '--gid' && i + 1 < args.length) {
      initialGid = args[i + 1];
    }
  }

  if (initialUrl == null && args.isNotEmpty && !args.first.startsWith('--')) {
    initialUrl = args.first;
  }
  
  initialGid ??= 'pending-${DateTime.now().millisecondsSinceEpoch}';
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: AppLifecycleObserver(
        cliUrl: initialUrl,
        cliRequestId: initialRequestId,
        cliGid: initialGid,
        child: const PirSwitchboardApp(),
      ),
    ),
  );
}

class AppLifecycleObserver extends ConsumerStatefulWidget {
  final Widget child;
  final String? cliUrl;
  final String? cliRequestId;
  final String? cliGid;
  const AppLifecycleObserver({super.key, required this.child, this.cliUrl, this.cliRequestId, this.cliGid});

  @override
  ConsumerState<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver> with WindowListener {
  late final AppLifecycleListener _listener;
  bool _cliSubmitted = false;
  final Completer<void> _systemReady = Completer<void>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    // Mount the Boot Gate barrier immediately after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _executeBootGate();
    });

    // ACPI Sleep Suppression: Prevent OS sleep while downloads are active
    ref.listenManual<AsyncValue<List<DownloadStatus>>>(downloadListProvider, (prev, next) {
      final activeCount = next.value?.where((d) => d.status == 'active').length ?? 0;
      if (activeCount > 0) {
        WakelockPlus.enable();
        stderr.writeln('[ACPI] Active downloads detected ($activeCount). Wakelock ENABLED.');
      } else {
        WakelockPlus.disable();
        stderr.writeln('[ACPI] No active downloads. Wakelock DISABLED.');
      }
    });

    _listener = AppLifecycleListener(
      onDetach: () => ref.read(vaultQueueServiceProvider).stop(),
      onExitRequested: () async {
        ref.read(vaultQueueServiceProvider).stop();
        return AppExitResponse.exit;
      },
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          stderr.writeln('[Heartbeat] App resumed. Forcing engine connectivity check...');
          // Re-trigger engine start/connect if it was lost during sleep
          ref.read(engineProcessProvider.notifier).start();
        }
      },
    );
  }

  // (Removed _submitUrlWhenReady and _sweepDeadLetterJournal for VaultQueueService)

  Future<void> _executeBootGate() async {
    stderr.writeln('[LIFECYCLE] Boot Gate sequence started.');
    
    // Step 1: Wait for Engine
    stderr.writeln('[LIFECYCLE] Step 1: Initiating Engine...');
    final engineNotifier = ref.read(engineProcessProvider.notifier);
    await engineNotifier.start(); 

    // Step 2: Rehydrate State
    stderr.writeln('[LIFECYCLE] Step 2: Rehydrating state from engine...');
    try {
      final engineClient = PirEngineClient();
      final active = await engineClient.tellActive();
      final waiting = await engineClient.tellWaiting(0, 100);
      final stopped = await engineClient.tellStopped(0, 100);
      final initialTasks = [...active, ...waiting, ...stopped];
      ref.read(downloadListProvider.notifier).hydrate(initialTasks);
      stderr.writeln('[LIFECYCLE] State rehydration complete. ${initialTasks.length} tasks restored.');
    } catch (e) {
      stderr.writeln('[LIFECYCLE] State rehydration failed: $e');
    }

    // Step 3: Start Vault File Queue Consumer
    stderr.writeln('[LIFECYCLE] Step 3: Starting Vault Queue consumer...');
    try {
      final vaultService = ref.read(vaultQueueServiceProvider);
      vaultService.start();
      stderr.writeln('[LIFECYCLE] Vault Queue Service started.');
    } catch (e) {
      stderr.writeln('[LIFECYCLE] Vault Service start error: $e');
    }

    // Release the barrier
    _systemReady.complete();
    stderr.writeln('[LIFECYCLE] Boot Gate CLEAR. App is fully interactive.');
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _systemReady.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(
              backgroundColor: Color(0xFF141414),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.blueGrey),
                    SizedBox(height: 24),
                    Text('System Initializing...', 
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}

/// Singleton Guard: Ensures only one instance of Switchboard runs.
/// If an instance is already running, it sends a WAKE signal via UDS and exits.
Future<void> _checkInstanceSingleton(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '/tmp';
  final lockDir = Directory('$home/.config/jbrowser_profile');
  if (!lockDir.existsSync()) lockDir.createSync(recursive: true);
  
  final lockFile = File('${lockDir.path}/switchboard.lock');
  
  if (lockFile.existsSync()) {
    final oldPid = int.tryParse(lockFile.readAsStringSync().trim());
    if (oldPid != null) {
      // Check if process is actually running
      bool isRunning = false;
      try {
        // Send signal 0 to check existence without killing
        isRunning = Process.runSync('kill', ['-0', oldPid.toString()]).exitCode == 0;
      } catch (_) {}

      if (isRunning) {
        stderr.writeln('[Singleton] Primary instance (PID: $oldPid) is already running.');
        
        // Signal the primary instance to focus AND awake (CLI args deprecated)
        try {
          stderr.writeln('[Singleton] WOKE primary instance.');
        } catch (e) {
          stderr.writeln('[Singleton] Failed to send WAKE signal: $e');
        }
        
        exit(0); // Terminate secondary instance
      }
    }
  }

  // Register current instance
  lockFile.writeAsStringSync(pid.toString());
  stderr.writeln('[Singleton] Lockfile created for PID: $pid');
  
  // Cleanup on exit (not perfect in case of crash, but handled by PID check on next boot)
  ProcessSignal.sigterm.watch().listen((_) {
    if (lockFile.existsSync()) lockFile.deleteSync();
    exit(0);
  });
}

class PirSwitchboardApp extends StatelessWidget {
  const PirSwitchboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pir Switchboard',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF141414),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Auto-start the engine on launch
    ref.listen<EngineProcessState>(engineProcessProvider, (prev, next) {
      if (next.status == EngineStatus.disconnected) {
        ref.read(engineProcessProvider.notifier).start();
      }
    });

    final engineState = ref.watch(engineProcessProvider);
    final downloads = ref.watch(downloadListProvider);

    // Initial trigger if not already starting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (engineState.status == EngineStatus.disconnected) {
        ref.read(engineProcessProvider.notifier).start();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pir Switchboard MVP'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            icon: Icon(
              engineState.status == EngineStatus.connected ? Icons.power : Icons.power_off,
              color: engineState.status == EngineStatus.connected ? Colors.green : Colors.red,
            ),
            onPressed: () {
              if (engineState.status == EngineStatus.connected) {
                ref.read(engineProcessProvider.notifier).stop();
              } else {
                ref.read(engineProcessProvider.notifier).start();
              }
            },
          ),
        ],
      ),
      body: _buildBody(context, engineState, downloads),
      floatingActionButton: FloatingActionButton(
        onPressed: engineState.status == EngineStatus.connected 
          ? () => _showAddUrlDialog(context, ref)
          : null,
        backgroundColor: engineState.status == EngineStatus.connected ? Colors.blue : Colors.grey,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, EngineProcessState engine, AsyncValue<List<DownloadStatus>> downloads) {
    if (engine.status == EngineStatus.starting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("Engine starting...", style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (engine.status == EngineStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text("Engine Error: ${engine.error}"),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ProviderScope.containerOf(context).read(engineProcessProvider.notifier).start(),
              child: const Text("Retry Connection"),
            ),
          ],
        ),
      );
    }

    if (engine.status == EngineStatus.disconnected) {
      return Center(
        child: ElevatedButton(
          onPressed: () => ProviderScope.containerOf(context).read(engineProcessProvider.notifier).start(),
          child: const Text("Start Download Engine"),
        ),
      );
    }

    return downloads.when(
      data: (list) => list.isEmpty
          ? const Center(child: Text("No active downloads", style: TextStyle(color: Colors.white30)))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, idx) => DownloadTile(download: list[idx]),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text("RPC Error: $err", style: const TextStyle(color: Colors.red))),
    );
  }

  void _showAddUrlDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add New Download"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter URL (magnet or direct)"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                try {
                  await PirEngineClient().addUri(controller.text);
                  if (context.mounted) Navigator.pop(ctx);
                } catch (e) {
                  // Error handling
                }
              }
            },
            child: const Text("Download"),
          ),
        ],
      ),
    );
  }
}
