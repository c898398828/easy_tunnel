// tray_manager 0.9.0 / window_manager 0.7.0 moved the 0.5.x-compatible API
// to legacy.dart.
// ignore_for_file: deprecated_member_use
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

class TrayWindowService with TrayListener, WindowListener {
  final bool Function() shouldHideOnClose;
  final void Function() onShowApp;
  final void Function() onStopAll;
  final Future<void> Function() onExit;

  TrayWindowService({
    required this.shouldHideOnClose,
    required this.onShowApp,
    required this.onStopAll,
    required this.onExit,
  });

  Future<void> init() async {
    // Route every close through onWindowClose first: if tray setup fails the
    // listener stays registered and shouldHideOnClose() forces a real exit.
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    var trayListenerAdded = false;
    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('Easy Tunnel');
      final menu = Menu(items: [
        MenuItem(key: 'show', label: '打开主界面'),
        MenuItem.separator(),
        MenuItem(key: 'stop_all', label: '停止全部隧道'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '彻底退出'),
      ]);
      await trayManager.setContextMenu(menu);
      trayManager.addListener(this);
      trayListenerAdded = true;
    } catch (_) {
      if (trayListenerAdded) trayManager.removeListener(this);
      rethrow;
    }
  }

  Future<void> disposeService() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() => onShowApp();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShowApp();
      case 'stop_all':
        onStopAll();
      case 'exit':
        onExit();
    }
  }

  @override
  void onWindowClose() async {
    if (shouldHideOnClose()) {
      await windowManager.hide();
    } else {
      await onExit();
    }
  }
}
