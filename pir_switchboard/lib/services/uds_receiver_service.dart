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
              final url = payload['url'] as String;
              final requestId = payload['requestId'] as String?;
              final headers = Map<String, String>.from(payload['headers'] ?? {});

              stderr.writeln('[UDS] Received: requestId=$requestId url=$url');

              // 1. Optimistic UI Update (with idempotency guard)
              ref.read(downloadListProvider.notifier).addPending(url, requestId: requestId);

              // 2. Engine Handoff (Async)
              _client.addUri(url, headers: headers).catchError((e) {
                stderr.writeln('[UDS] Engine Handoff Error: $e');
                return 'error';
              });
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
