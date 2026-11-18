// window_manager 0.7.0 moved the 0.5.x-compatible API to legacy.dart.
// ignore_for_file: deprecated_member_use
import 'package:material_ui/material_ui.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/legacy.dart';

import 'app.dart';
import 'providers/tunnel_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(948, 622),
    minimumSize: Size(948, 622),
    center: true,
    title: 'Easy Tunnel',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setSize(const Size(948, 622));
    await windowManager.setMinimumSize(const Size(948, 622));
    await windowManager.show();
    await windowManager.focus();
  });

  try {
    await LocalNotifier.instance.setup(appName: 'Easy Tunnel');
  } catch (_) {}

  final provider = await TunnelProvider.bootstrap(
    notify: (title, body) async {
      try {
        final n = LocalNotification(
          identifier: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
          body: body,
        );
        await LocalNotifier.instance.notify(n);
      } catch (_) {}
    },
  );
  await provider.init();

  runApp(EasyTunnelApp(provider: provider));
}
