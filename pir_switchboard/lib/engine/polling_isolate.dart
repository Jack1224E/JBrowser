import 'dart:async';
import 'dart:isolate';
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
  
  Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
    try {
      final active = await client.tellActive();
      params.sendPort.send(PollUpdate(activeDownloads: active));
    } catch (e) {
      params.sendPort.send(PollUpdate(activeDownloads: [], error: e.toString()));
    }
  });
}
