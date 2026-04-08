import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/pir_engine_client.dart';
import '../database/vault_db.dart';
import 'dart:developer' as dev;

final vaultQueueServiceProvider = Provider<VaultQueueService>((ref) {
  final db = ref.read(vaultDbProvider);
  return VaultQueueService(db);
});

/// Phase 2: SOTA Central Vault Directory Queue Consumer
/// Replaces the brittle IPC Push model with a reliable Pull model over the filesystem.
class VaultQueueService {
  final VaultDb _db;
  final _engineClient = PirEngineClient();
  Timer? _pollingTimer;
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  bool _isSweeping = false;

  VaultQueueService(this._db);

  /// Absolute directory of the Vault Queue
  /// Returns ~/.local/state/jbrowser/vault/queue/
  Directory get _queueDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final dir = Directory('$home/.local/state/jbrowser/vault/queue');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  void start() {
    dev.log('[VAULT_QUEUE] Starting Event-Driven Directory Watcher...');
    
    // 1. Immediate Initial Sweep (Cold Start catching)
    _sweepQueue();

    // 2. Event-Driven Watcher (Instant Ingress)
    try {
      _watchSubscription = _queueDir.watch(events: FileSystemEvent.create | FileSystemEvent.modify).listen((event) {
        if (event.path.endsWith('.json') && event is! FileSystemDeleteEvent) {
          dev.log('[CONSUMER_EVENT] Instant FileSystemEvent detected on ${event.path}');
          _sweepQueue(); // Sweeps process everything cleanly and safely with idempotency
        }
      });
      dev.log('[VAULT_QUEUE] Native SQLite-watcher active on ${_queueDir.path}');
    } catch (e) {
      dev.log('[VAULT_QUEUE_ERROR] Native watcher failed, falling back to polling: $e');
    }
    
    // 3. Fallback polling strategy to guarantee 100% ingestion (Increased interval to save CPU)
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sweepQueue();
    });
  }

  void stop() {
    _watchSubscription?.cancel();
    _pollingTimer?.cancel();
    _pollingTimer = null;
    dev.log('[VAULT_QUEUE] Stopped.');
  }

  Future<void> _sweepQueue() async {
    if (_isSweeping) return; // Prevent overlapping sweeps
    _isSweeping = true;

    try {
      final dir = _queueDir;
      final entities = dir.listSync();

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          dev.log('[CONSUMER] Found file: ${entity.path}');
          await _processVaultFile(entity);
        }
      }
    } catch (e) {
      dev.log('[VAULT_QUEUE_ERROR] Directory sweep failed: $e');
    } finally {
      _isSweeping = false;
    }
  }

  Future<void> _processVaultFile(File file) async {
    try {
      final content = await file.readAsString();
      final payload = jsonDecode(content);

      final url = payload['url'] as String?;
      final gid = payload['gid'] as String?;
      final headers = payload['headers'] as Map<String, dynamic>? ?? {};

      if (url == null || gid == null) {
        dev.log('[VAULT_QUEUE_ERROR] Malformed entry found and discarded: ${file.path}');
        await file.delete();
        return;
      }

      dev.log('[CONSUMER] Dispatching RPC addUri for GID: $gid');

      // 1. The Check-In: Immortal Whiteboard Logging
      await _db.insertTask(gid: gid, url: url, status: 'pending');

      // Attempt Engine Submission
      try {
        final Map<String, String> stringHeaders = headers.map((key, value) => MapEntry(key.toString(), value.toString()));
        final response = await _engineClient.addUri(url, gid: gid, headers: stringHeaders);
        dev.log('[CONSUMER] RPC Response: OK - $response');
        dev.log('[VAULT_QUEUE] Engine Accepted! Promoting $gid to Active Vault.');
        
        // 2. The Check-Out: Mark as active in DB
        await _db.updateStatus(gid, 'active');

        // Promotion: Move to active/ or delete. We delete Since engine tracks it now.
        // DO NOT delete until WE ARE SURE.
        await file.delete();
        
      } catch (e) {
        final errorMsg = e.toString();
        if (errorMsg.contains('is already in use')) {
          dev.log('[VAULT_QUEUE_IDEMPOTENT] Task already exists in engine. Cleaning up $gid.');
          await file.delete();
        } else if (errorMsg.contains('Connection refused') || errorMsg.contains('SocketException') || errorMsg.contains('Connection closed')) {
          // Engine not ready yet. Leave the file in the queue!
          dev.log('[CONSUMER] RPC ERROR: Engine not ready, leaving file in queue: $errorMsg');
        } else {
          dev.log('[CONSUMER] RPC ERROR: Fatal RPC failure for $gid: $e');
        }
      }

    } catch (e) {
      dev.log('[VAULT_QUEUE_PROC_ERROR] Failed to process file ${file.path}: $e');
    }
  }

  /// Expose the list of un-ingested GIDs for the UI Reconciler
  List<Map<String, dynamic>> getPendingVaultTasks() {
    try {
      return _queueDir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) {
            try {
              return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .where((entry) => entry != null)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
