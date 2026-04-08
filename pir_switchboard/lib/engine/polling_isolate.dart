import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'pir_engine_client.dart';
import '../models/download_status.dart';

class PollUpdate {
  final List<DownloadStatus> activeDownloads;
  final String? error;

  PollUpdate({required this.activeDownloads, this.error});
}

class PollingIsolateParams {
  final SendPort sendPort;
  final String rpcUrl;

  PollingIsolateParams({required this.sendPort, required this.rpcUrl});
}

// Background Isolate Entry Point
void pollIsolateMain(PollingIsolateParams params) async {
  final client = PirEngineClient(rpcUrl: params.rpcUrl);
  
  // Sequential Polling: Prevents overlapping RPC calls (Thundering Herd)
  while (true) {
    try {
      final active = await client.tellActive();
      final waiting = await client.tellWaiting(0, 50);
      final stopped = await client.tellStopped(0, 50);
      
      final all = [...active, ...waiting, ...stopped];
      stderr.writeln('[POLL_TICK] Engine reported GIDs: ${all.map((t) => t.gid).toList()}');
      params.sendPort.send(PollUpdate(activeDownloads: all));

      // Dynamic Heartbeat Scaling (Motrix Extraction 6)
      bool hasActive = active.any((d) => d.status == 'active');
      int nextInterval = hasActive ? 500 : 5000;
      
      // Low-noise logging for interval shifts
      if (hasActive) {
        stderr.writeln('[Heartbeat] Active tasks detected. Scaling to 500ms.');
      } else {
        // Only log idle once to prevent log spam
        stderr.writeln('[Heartbeat] Core idle. Scaling to 5000ms.');
      }

      await Future.delayed(Duration(milliseconds: nextInterval));
    } catch (e) {
      params.sendPort.send(PollUpdate(activeDownloads: [], error: e.toString()));
      await Future.delayed(const Duration(milliseconds: 5000)); // Backoff on error
    }
  }
}
