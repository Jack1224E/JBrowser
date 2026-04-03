import 'dart:isolate';
import 'dart:io';
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

  /// LAYER 3: The Synchronous Bouncer
  /// Returns true if this is the first time we've seen this requestId.
  /// Mutates state immediately in a single Event Loop tick.
  bool tryClaim({required String requestId, required String url, required String gid}) {
    if (state is! AsyncData) return false;
    
    final currentList = state.value ?? [];
    final alreadyExists = currentList.any((d) => d.requestId == requestId);
    
    if (alreadyExists) {
      stderr.writeln('[DEDUP_RIVERPOD] Signal dropped: $requestId');
      return false;
    }

    final fileName = url.split('/').last.split('?').first;
    final pendingDownload = DownloadStatus(
      gid: gid,
      status: 'pending',
      totalLength: 0,
      completedLength: 0,
      downloadSpeed: 0,
      uploadSpeed: 0,
      files: [fileName],
      requestId: requestId,
    );

    state = AsyncValue.data([pendingDownload, ...currentList]);
    return true;
  }

  /// Legacy compat / internal add (not used by Vault paths)
  void addPending(String url, {String? requestId}) {
    final gid = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    tryClaim(requestId: requestId ?? gid, url: url, gid: gid);
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
