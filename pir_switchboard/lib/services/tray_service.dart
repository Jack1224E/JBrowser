import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../engine/pir_engine_client.dart';
import '../services/vault_queue_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  late final ProviderContainer _container;

  Future<void> init(ProviderContainer container) async {
    _container = container;
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
    );
    
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'open',
          label: 'Open JBrowser',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: 'Exit Vault',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'open') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit') {
      await vaultExit();
    }
  }

  Future<void> vaultExit() async {
    // Phase 2 Kill Sequence
    try {
      // 1. Hide UI instantly
      await windowManager.hide();
      
      // 2. Stop Vault Queue Polling
      _container.read(vaultQueueServiceProvider).stop();
      
      // 3. Graceful engine shutdown (Motrix Extraction 5)
      final client = PirEngineClient();
      
      // Perform flush and shutdown with a strict 2s barrier
      await Future.wait([
        client.saveSession(),
        client.shutdown(),
      ]).timeout(const Duration(seconds: 2), onTimeout: () {
        stderr.writeln('[Exit] Shutdown timeout reached. Force exiting.');
        return [];
      });
      
      // 4. Cleanup Singleton Lock
      final home = Platform.environment['HOME'] ?? '/tmp';
      final lockFile = File('$home/.config/jbrowser_profile/switchboard.lock');
      if (lockFile.existsSync()) lockFile.deleteSync();
    } catch (e) {
      debugPrint('Error during exit: $e');
    } finally {
      // 4. Terminate Dart process
      exit(0);
    }
  }
}

final trayServiceProvider = Provider((ref) => TrayService());
