import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../engine/polling_isolate.dart';
import '../models/download_status.dart';
import 'engine_process_provider.dart';

class DownloadListNotifier extends StateNotifier<AsyncValue<List<DownloadStatus>>> {
  ReceivePort? _receivePort;
  Isolate? _isolate;

  DownloadListNotifier(this.ref) : super(const AsyncValue.loading()) {
    // Start polling once the engine is connected
    ref.listen<EngineProcessState>(engineProcessProvider, (prev, next) {
      if (next.status == EngineStatus.connected) {
        _startPolling();
      } else if (next.status == EngineStatus.disconnected || next.status == EngineStatus.error) {
        _stopPolling();
      }
    });
  }

  final Ref ref;

  Future<void> _startPolling() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      pollIsolateMain,
      PollingIsolateParams(
        sendPort: _receivePort!.sendPort,
        rpcUrl: 'http://127.0.0.1:6800/jsonrpc',
      ),
    );

    _receivePort!.listen((message) {
      if (message is PollUpdate) {
        if (message.error != null) {
          state = AsyncValue.error(message.error!, StackTrace.current);
        } else {
          state = AsyncValue.data(message.activeDownloads);
        }
      }
    });
  }

  void _stopPolling() {
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    state = const AsyncValue.data([]);
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final downloadListProvider = StateNotifierProvider<DownloadListNotifier, AsyncValue<List<DownloadStatus>>>((ref) {
  return DownloadListNotifier(ref);
});
