import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../engine/polling_isolate.dart';
import '../engine/pir_engine_client.dart';
import '../models/download_status.dart';
import '../services/vault_queue_service.dart';
import '../database/vault_db.dart';
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
  final PirEngineClient _engineClient = PirEngineClient();


  /// Phase 1: Boot Gate Hydration
  void hydrate(List<DownloadStatus> initialList) {
    stderr.writeln('[BOOT_GATE] Hydrating state with ${initialList.length} tasks from engine');
    state = AsyncValue.data(initialList);
  }

  Future<void> _startPolling() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      pollIsolateMain,
      PollingIsolateParams(
        sendPort: _receivePort!.sendPort,
        rpcUrl: 'http://127.0.0.1:6800/jsonrpc',
      ),
    );

    _receivePort!.listen((message) async {
      if (message is PollUpdate) {
        if (message.error != null) {
          state = AsyncValue.error(message.error!, StackTrace.current);
        } else {
          final engineList = message.activeDownloads;
          
          if (state is AsyncData && state.value != null) {
            final currentList = state.value!;
            
            // Phase 3: Reconciliation Guard (Flicker-free management)
            final reconciled = engineList.map((engineTask) {
              final localMatch = currentList.where((d) => d.gid == engineTask.gid).toList();
              if (localMatch.isNotEmpty) {
                final localTask = localMatch.first;
                if (localTask.isIntermediate) {
                  // Wait for engine to catch up to the intended state
                  if (localTask.status == 'pausing' && engineTask.status == 'paused') return engineTask;
                  if (localTask.status == 'resuming' && engineTask.status == 'active') return engineTask;
                  if (localTask.status == 'deleting') return localTask; // Skip until removed from list
                  return localTask;
                }
              }
              return engineTask;
            }).toList();

            // Task 3: The Ghost Purge & database check
            final vaultDb = ref.read(vaultDbProvider);
            final dbRows = await vaultDb.getActiveAndPending();
            
            final mappedVaultTasks = dbRows.map((t) {
              final url = t['url'] as String? ?? 'Missing URL';
              final fileName = url.split('/').last.split('?').first;
              final gid = t['gid'] as String? ?? 'unknown';
              return DownloadStatus(
                gid: gid,
                status: t['status'] as String? ?? 'pending',
                totalLength: 0,
                completedLength: 0,
                downloadSpeed: 0,
                uploadSpeed: 0,
                files: [fileName],
              );
            }).where((v) => !engineList.any((e) => e.gid == v.gid)).toList();

            // Keep locally-claimed "pending" tasks (from tryClaim)
            final pendingTasks = currentList.where((d) => 
              d.status == 'pending' && 
              !engineList.any((e) => e.gid == d.gid) &&
              !mappedVaultTasks.any((v) => v.gid == d.gid)
            ).toList();
            
            final proposedList = <DownloadStatus>[...mappedVaultTasks, ...pendingTasks, ...reconciled];

            // THE GHOST PURGE: Symmetric Reconciliation naturally purges ghosts because they are
            // neither in engineList nor in dbRows (marked 'deleted').
            final activeGids = proposedList.map((x) => x.gid).toSet();
            final ghostsPurged = currentList.where((c) => !activeGids.contains(c.gid)).length;
            if (ghostsPurged > 0) {
               stderr.writeln('[THE GHOST PURGE] Purged $ghostsPurged dead tiles from UI.');
            }

            state = AsyncValue.data(proposedList);
          } else {
            state = AsyncValue.data(engineList);
          }
        }
      }
    });
  }

  void _stopPolling() {
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    state = const AsyncValue.data([]);
  }

  // Phase 3: Optimistic Task Controls
  Future<void> pauseTask(String gid) async {
    _updateStatusOptimistically(gid, 'pausing');
    try {
      await _engineClient.pause(gid);
    } catch (e) {
      stderr.writeln('[Optimistic] Pause failed: $e');
    }
  }

  Future<void> resumeTask(String gid) async {
    _updateStatusOptimistically(gid, 'resuming');
    try {
      await _engineClient.unpause(gid);
    } catch (e) {
      stderr.writeln('[Optimistic] Resume failed: $e');
    }
  }

  Future<void> removeTask(String gid) async {
    _updateStatusOptimistically(gid, 'deleting');
    try {
      await _engineClient.remove(gid);
      // Persist delete intent to Vault DB for Symmetric Reconciliation
      ref.read(vaultDbProvider).markDeleted(gid);
      
      // Immediately remove from UI after successful RPC
      if (state is AsyncData) {
        final list = state.value!;
        state = AsyncValue.data(list.where((d) => d.gid != gid).toList());
      }
    } catch (e) {
      stderr.writeln('[Optimistic] Remove failed: $e');
    }
  }

  void _updateStatusOptimistically(String gid, String status) {
    if (state is! AsyncData) return;
    final list = state.value!;
    final index = list.indexWhere((d) => d.gid == gid);
    if (index != -1) {
      final updatedList = List<DownloadStatus>.from(list);
      updatedList[index] = updatedList[index].copyWith(status: status);
      state = AsyncValue.data(updatedList);
    }
  }

  /// LAYER 3: The Synchronous Bouncer
  /// Returns true if this is the first time we've seen this requestId.
  /// Mutates state immediately in a single Event Loop tick.
  bool tryClaim({required String requestId, required String url, required String gid}) {
    stderr.writeln('[DEDUP_RIVERPOD] tryClaim fired for requestId: $requestId');
    if (state is! AsyncData) return false;
    
    final currentList = state.value ?? [];
    final requestIdExists = currentList.any((d) => d.requestId == requestId);
    final urlExists = currentList.any((d) => d.files.any((f) => url.contains(f))); // Basic URL/File check
    
    if (requestIdExists) {
      stderr.writeln('[DEDUP_RIVERPOD] Request ID already seen: $requestId. Signal dropped.');
      return false;
    }

    if (urlExists) {
      stderr.writeln('[DEDUP_RIVERPOD] WARNING: Duplicate URL detected in history for: $url. Allowing claim but auditing required.');
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

  String _generateHexGid() {
    final random = Random();
    const chars = '0123456789abcdef';
    return List.generate(16, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Legacy compat / internal add (not used by Vault paths)
  void addPending(String url, {String? requestId}) {
    final gid = _generateHexGid();
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
