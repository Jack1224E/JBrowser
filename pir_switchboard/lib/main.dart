import 'dart:io';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/engine_process_provider.dart';
import 'providers/download_list_provider.dart';
import 'widgets/download_tile.dart';
import 'engine/pir_engine_client.dart';
import 'models/download_status.dart';
import 'services/uds_receiver_service.dart';

void main(List<String> args) {
  // Parse named CLI arguments: --download-url <url> --request-id <id> --gid <gid>
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

  // Backwards compat: if no named args, treat first positional arg as URL
  if (initialUrl == null && args.isNotEmpty && !args.first.startsWith('--')) {
    initialUrl = args.first;
  }
  
  // If we have a URL but no GID (legacy), generate a pending one
  initialGid ??= 'pending-${DateTime.now().millisecondsSinceEpoch}';
  
  if (initialUrl != null) {
    stderr.writeln('[Switchboard] Received CLI URL: $initialUrl (requestId: $initialRequestId, gid: $initialGid)');
  } else {
    stderr.writeln('[Switchboard] No CLI URL received. Awaiting UDS/manual input.');
  }
  
  runApp(
    ProviderScope(
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

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver> {
  late final AppLifecycleListener _listener;
  bool _cliSubmitted = false;

  @override
  void initState() {
    super.initState();

    // Start the UDS receiver so the bridge socket is available immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final udsService = ref.read(udsServiceProvider);
        await udsService.start();
        stderr.writeln('[Switchboard] UDS Receiver started.');
      } catch (e) {
        stderr.writeln('[Switchboard] UDS start error: $e');
      }

      // Process CLI URL if provided
      if (widget.cliUrl != null && !_cliSubmitted) {
        _cliSubmitted = true;
        stderr.writeln('[Switchboard] Auto-submitting CLI URL: ${widget.cliUrl} (requestId: ${widget.cliRequestId}, gid: ${widget.cliGid})');
        _submitUrlWhenReady(widget.cliUrl!, requestId: widget.cliRequestId, gid: widget.cliGid);
      }

      // Sweep the dead letter journal for missed links
      _sweepDeadLetterJournal();
    });

    _listener = AppLifecycleListener(
      onDetach: () => ref.read(udsServiceProvider).stop(),
      onExitRequested: () async {
        ref.read(udsServiceProvider).stop();
        return AppExitResponse.exit;
      },
      onStateChange: (state) {
        if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
           // Optional: could stop here too, but UDS is usually fine to stay open
        }
      },
    );
  }

  /// Wait for the engine to be connected, then submit the URL (with Layer 3/4)
  void _submitUrlWhenReady(String url, {String? requestId, String? gid}) {
    if (gid == null) {
      stderr.writeln('[Switchboard] Error: CLI URL provided without GID. Dropping.');
      return;
    }

    ref.listenManual<EngineProcessState>(engineProcessProvider, (prev, next) {
      if (next.status == EngineStatus.connected) {
        final notifier = ref.read(downloadListProvider.notifier);
        
        // Layer 3: Synchronous Bouncer
        if (notifier.tryClaim(requestId: requestId ?? gid, url: url, gid: gid)) {
          stderr.writeln('[Switchboard] Claimed CLI URL: $url (gid: $gid)');
          
          // Layer 4: Engine Arbiter
          PirEngineClient().addUri(url, gid: gid).then((_) {
            stderr.writeln('[Switchboard] CLI URL accepted by engine.');
          }).catchError((e) {
            final errorMsg = e.toString();
            if (errorMsg.contains('is already in use')) {
              stderr.writeln('[DEDUP_ENGINE] Suppressed parallel CLI spawn: $gid');
            } else {
              stderr.writeln('[Switchboard] CLI Engine Error: $e');
            }
          });
        }
      }
    });
  }

  /// Sweep ~/.local/state/jbrowser/pending_links.jsonl for missed downloads
  void _sweepDeadLetterJournal() {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final journalPath = '$home/.local/state/jbrowser/pending_links.jsonl';
      final journalFile = File(journalPath);
      if (!journalFile.existsSync()) return;

      final lines = journalFile.readAsLinesSync().where((l) => l.trim().isNotEmpty);
      if (lines.isEmpty) return;

      stderr.writeln('[Switchboard] Dead letter journal found: ${lines.length} entries to sweep.');
      for (final line in lines) {
        try {
          final entry = jsonDecode(line) as Map<String, dynamic>;
          final url = entry['url'] as String?;
          final deliveredAt = entry['delivered_at'];
          
          // IDEMPOTENCY: Ignore receipts (already delivered)
          if (deliveredAt != null) {
            stderr.writeln('[Switchboard] Skipping already-delivered journal entry: $url');
            continue;
          }

          if (url != null) {
            final requestId = entry['requestId'] as String?;
            final gid = entry['gid'] as String? ?? 'journal-${DateTime.now().millisecondsSinceEpoch}';
            
            final notifier = ref.read(downloadListProvider.notifier);
            if (notifier.tryClaim(requestId: requestId ?? gid, url: url, gid: gid)) {
              stderr.writeln('[Switchboard] Claimed journal entry: $requestId');
              
              PirEngineClient().addUri(url, gid: gid).catchError((e) {
                final errorMsg = e.toString();
                if (errorMsg.contains('is already in use')) {
                  stderr.writeln('[DEDUP_ENGINE] Suppressed parallel journal rehydration: $gid');
                } else {
                  stderr.writeln('[Switchboard] Journal rehydration error for $url: $e');
                }
                return 'error';
              });
            }
          }
        } catch (e) {
          stderr.writeln('[Switchboard] Skipping malformed journal entry: $e');
        }
      }

      // Clear the journal after sweep
      journalFile.writeAsStringSync('');
      stderr.writeln('[Switchboard] Dead letter journal swept and cleared.');
    } catch (e) {
      stderr.writeln('[Switchboard] Journal sweep error: $e');
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
