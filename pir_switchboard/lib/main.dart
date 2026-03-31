import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/engine_process_provider.dart';
import 'providers/download_list_provider.dart';
import 'widgets/download_tile.dart';
import 'engine/pir_engine_client.dart';
import 'models/download_status.dart';

void main() {
  runApp(const ProviderScope(child: PirSwitchboardApp()));
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
