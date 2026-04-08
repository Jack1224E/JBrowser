import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/download_status.dart';
import '../models/global_stats.dart';

class PirEngineClient {
  final String rpcUrl;

  PirEngineClient({this.rpcUrl = 'http://127.0.0.1:6800/jsonrpc'});

  Future<Map<String, dynamic>> _call(String method, [List<dynamic> params = const []]) async {
    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 'pir-${DateTime.now().millisecondsSinceEpoch}',
        'method': method,
        'params': params,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('RPC Error: ${response.statusCode} - ${response.body}');
    }
  }

  Future<String> addUri(String url, {Map<String, String>? headers, String? gid}) async {
    final options = <String, dynamic>{};
    if (headers != null && headers.isNotEmpty) {
      options['header'] = headers.entries.map((e) => '${e.key}: ${e.value}').toList();
    }
    if (gid != null) {
      options['gid'] = gid;
    }

    stderr.writeln('[RPC_CALL] addUri requested with GID: $gid');

    final res = await _call('aria2.addUri', [[url], options]);
    return res['result'] as String;
  }

  Future<List<DownloadStatus>> tellActive() async {
    final res = await _call('aria2.tellActive');
    final List<dynamic> list = res['result'] ?? [];
    return list.map((json) => DownloadStatus.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<DownloadStatus>> tellWaiting(int offset, int num) async {
    final res = await _call('aria2.tellWaiting', [offset, num]);
    final List<dynamic> list = res['result'] ?? [];
    return list.map((json) => DownloadStatus.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<DownloadStatus>> tellStopped(int offset, int num) async {
    final res = await _call('aria2.tellStopped', [offset, num]);
    final List<dynamic> list = res['result'] ?? [];
    return list.map((json) => DownloadStatus.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<DownloadStatus> tellStatus(String gid) async {
    final res = await _call('aria2.tellStatus', [gid]);
    return DownloadStatus.fromJson(res['result']);
  }

  Future<void> pause(String gid) async {
    await _call('aria2.pause', [gid]);
  }

  Future<void> unpause(String gid) async {
    await _call('aria2.unpause', [gid]);
  }

  Future<void> remove(String gid) async {
    // Try to remove from active first, then result
    try {
      await _call('aria2.remove', [gid]);
    } catch (_) {
      try {
        await _call('aria2.removeDownloadResult', [gid]);
      } catch (_) {}
    }
  }

  Future<void> forceRemove(String gid) async {
    await _call('aria2.forceRemove', [gid]);
  }

  Future<void> saveSession() async {
    await _call('aria2.saveSession', []);
  }

  Future<void> shutdown() async {
    try {
      await _call('aria2.shutdown');
    } catch (_) {}
  }

  Future<GlobalStats> getGlobalStat() async {
    final res = await _call('aria2.getGlobalStat');
    return GlobalStats.fromJson(res['result']);
  }
}
