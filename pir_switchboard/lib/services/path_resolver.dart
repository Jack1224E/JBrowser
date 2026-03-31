import 'dart:io';
import 'package:path/path.dart' as p;

class PirPathResolver {
  static Future<String> findAria2c() async {
    // 1. Check common Linux paths (CachyOS/Arch base)
    final commonPaths = [
      '/usr/bin/aria2c',
      '/usr/local/bin/aria2c',
    ];

    for (var path in commonPaths) {
      if (await File(path).exists()) return path;
    }

    // 2. Try 'which'
    try {
      final res = await Process.run('which', ['aria2c']);
      if (res.exitCode == 0) return res.stdout.toString().trim();
    } catch (_) {}

    throw Exception('aria2c binary not found. Please install aria2.');
  }

  static Future<String> getSessionDir() async {
    final home = Platform.environment['HOME'] ?? '/home/jack';
    final dir = p.join(home, '.config', 'pir_switchboard', 'session');
    
    final directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    return dir;
  }

  static Future<String> getSessionFilePath() async {
    final dir = await getSessionDir();
    final file = p.join(dir, 'aria2.session');
    
    final f = File(file);
    if (!await f.exists()) {
      await f.create();
    }
    
    return file;
  }
}
