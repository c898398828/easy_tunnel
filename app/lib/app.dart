// window_manager 0.7.0 moved the 0.5.x-compatible API to legacy.dart.
// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/legacy.dart';

import 'providers/tunnel_provider.dart';
import 'services/tray_window_service.dart';
import 'theme.dart';
import 'ui/dashboard_page.dart';
import 'ui/settings_page.dart';
import 'ui/sidebar.dart';
import 'ui/title_bar.dart';
import 'ui/tunnels_page.dart';

class EasyTunnelApp extends StatefulWidget {
  final TunnelProvider provider;

  const EasyTunnelApp({super.key, required this.provider});

  @override
  State<EasyTunnelApp> createState() => _EasyTunnelAppState();
}

class _EasyTunnelAppState extends State<EasyTunnelApp> {
  TrayWindowService? _tray;
  bool _trayReady = true;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _tray = TrayWindowService(
        shouldHideOnClose: () =>
            _trayReady && widget.provider.settings.closeToTray,
        onShowApp: () async {
          await windowManager.show();
          await windowManager.focus();
        },
        onStopAll: () => widget.provider.stopAll(),
        onExit: _exitApp,
      );
      try {
        await _tray!.init();
      } catch (_) {
        _trayReady = false;
      }
    });
  }

  Future<void> _exitApp() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await widget.provider.stopAll();
      await _tray?.disposeService();
      await windowManager.destroy();
      exit(0);
    } finally {
      _exiting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: MaterialApp(
        title: 'Easy Tunnel',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = context.select<TunnelProvider, int>((p) => p.currentTab);
    return Scaffold(
      body: Column(
        children: [
          const TitleBar(),
          Expanded(
            child: Row(
              children: [
                const Sidebar(),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      border: Border(
                          left: BorderSide(color: AppColors.border)),
                    ),
                    child: IndexedStack(
                      index: tab,
                      children: const [
                        DashboardPage(),
                        TunnelsPage(),
                        SettingsPage(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
