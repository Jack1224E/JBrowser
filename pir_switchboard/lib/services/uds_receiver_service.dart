import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/download_list_provider.dart';
import '../engine/pir_engine_client.dart';

class UdsReceiverService {
  final Ref ref;
  ServerSocket? _server;
  final PirEngineClient _client = PirEngineClient();

  UdsReceiverService(this.ref);

  String _getSocketPath() {
    final xdgDir = Platform.environment['XDG_RUNTIME_DIR'];
    final baseDir = xdgDir != null ? '$xdgDir/jbrowser' : '/tmp/jbrowser';
    Directory(baseDir).createSync(recursive: true);
    return '$baseDir/bridge.sock';
  }

  Future<void> start() async {
    final path = _getSocketPath();
    final socketFile = File(path);

    // Stale socket cleanup
    if (socketFile.existsSync()) {
      socketFile.deleteSync();
    }

    _server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
    
    _server!.listen((client) {
      // CHUNKING FIX: Accumulate bytes in a buffer before decoding.
      // UDS streams can split a long JSON payload across multiple packets.
      final buffer = BytesBuilder(copy: false);

      client.listen(
        (data) {
          buffer.add(data);
        },
        onDone: () {
          // Connection closed — all bytes received. Now decode.
          try {
            final message = utf8.decode(buffer.toBytes());
            final payload = jsonDecode(message) as Map<String, dynamic>;
            
            if (payload['url'] != null) {
              final headers = Map<String, String>.from(payload['headers'] ?? {});

              // 1. App-Level Idempotency (Layer 3)
              final requestId = payload['requestId'] as String?;
              final url = payload['url'] as String?;
              final gid = payload['gid'] as String?;
              
              if (requestId == null || url == null || gid == null) {
                stderr.writeln('[UdsReceiver] MALFORMED PAYLOAD: $payload');
                return;
              }

              final notifier = ref.read(downloadListProvider.notifier);
              if (notifier.tryClaim(requestId: requestId, url: url, gid: gid)) {
                stderr.writeln('[UdsReceiver] Claimed NEW link: $requestId');
                
                // 2. Engine Handoff (Layer 4)
                _client.addUri(url, headers: headers, gid: gid).then((_) {
                   stderr.writeln('[UdsReceiver] Engine accepted: $gid');
                }).catchError((e) {
                  // LAYER 4: The Neck-Snapper
                  final errorMsg = e.toString();
                  if (errorMsg.contains('is already in use')) {
                    stderr.writeln('[DEDUP_ENGINE] Suppressed parallel spawn: $gid');
                  } else {
                    stderr.writeln('[UdsReceiver] Engine Error: $e');
                  }
                  return 'error';
                });
              }
            }
          } catch (e) {
            stderr.writeln('[UDS] Decoding Error: $e');
          }
        },
        onError: (e) {
          stderr.writeln('[UDS] Socket Error: $e');
        },
      );
    });
  }

  void stop() {
    _server?.close();
    final path = _getSocketPath();
    if (File(path).existsSync()) {
      File(path).deleteSync();
    }
  }
}

final udsServiceProvider = Provider<UdsReceiverService>((ref) {
  return UdsReceiverService(ref);
});
