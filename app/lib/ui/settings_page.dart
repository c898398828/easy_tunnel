import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../providers/tunnel_provider.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import 'widgets/engine_config_dialog.dart';
import 'widgets/modern_switch.dart';
import 'widgets/port_config_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _setStartup(bool enabled) async {
    final provider = context.read<TunnelProvider>();
    var ok = false;
    try {
      final result = enabled
          ? await Process.run('reg', [
              'add',
              r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
              '/v',
              'EasyTunnel',
              '/t',
              'REG_SZ',
              '/d',
              '"${Platform.resolvedExecutable}"',
              '/f',
            ])
          : await Process.run('reg', [
              'delete',
              r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
              '/v',
              'EasyTunnel',
              '/f',
            ]);
      ok = result.exitCode == 0;
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('开机自启设置失败，请检查系统权限', style: TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
      return;
    }
    provider.settings.launchAtStartup = enabled;
    await provider.saveSettings();
  }

  String _mask(String token) {
    if (token.length <= 8) return token.isEmpty ? '未配置' : '****';
    return '${token.substring(0, 4)}****${token.substring(token.length - 4)}';
  }

  void _openFolder(String path) {
    try {
      if (Platform.isWindows) {
        Process.run('explorer.exe', [path]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final settings = provider.settings;
    final baseDir = getPreferredBaseDir().path;
    final binDirPath = provider.deps.binDir.path;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏 + 刷新按钮 (对标参考图 2)
          Row(
            children: [
              const Text(
                '设置',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('配置状态已同步', style: TextStyle(fontSize: 12)),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      size: 14, color: AppColors.textSub),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 1. 调用观测 (对标参考图 2 第一张卡片)
          _SettingCard(
            title: '调用观测',
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '详细模式',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '额外保存完整请求和流响应；默认只保存时间、状态与用量。',
                        style: TextStyle(fontSize: 11, color: AppColors.textSub),
                      ),
                    ],
                  ),
                ),
                ModernSwitch(
                  value: settings.detailedLogs,
                  onChanged: (v) async {
                    settings.detailedLogs = v;
                    await provider.saveSettings();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 2. 端口设置 (对标参考图 2 第二张卡片)
          _SettingCard(
            title: '端口设置',
            actionText: '编辑',
            onAction: () => showDialog(
              context: context,
              builder: (_) => const PortConfigDialog(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('代理端口', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const SizedBox(width: 16),
                    Text('${settings.metricsPort}',
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(width: 32),
                    const Text('健康巡检', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const SizedBox(width: 16),
                    Text('每 ${settings.inspectIntervalSeconds} 秒',
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '端口被占用时会自动选择新的随机端口并保存。修改后需要重启软件才会生效。',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 3. 穿透服务凭证 (对标参考图 2 的双列配置风格)
          _SettingCard(
            title: '穿透服务凭证',
            actionText: '编辑',
            onAction: () => showDialog(
              context: context,
              builder: (_) => const EngineConfigDialog(engine: EngineType.cloudflare),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Cloudflare Token', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const Spacer(),
                    Text(
                      _mask(settings.cloudflareToken),
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'Consolas', color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFF262626)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('ngrok Authtoken', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const Spacer(),
                    Text(
                      _mask(settings.ngrokToken),
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'Consolas', color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 4. 软件数据与依赖存储路径 (完全在解压位置同级目录，绿色便携！)
          _SettingCard(
            title: '数据与环境依赖存储目录',
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('软件便携目录', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        baseDir,
                        style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _openFolder(baseDir),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: const Text('打开目录', style: TextStyle(fontSize: 10.5, color: AppColors.sky)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFF262626)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('依赖程序目录', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        binDirPath,
                        style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _openFolder(binDirPath),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: const Text('打开目录', style: TextStyle(fontSize: 10.5, color: AppColors.sky)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 5. 系统偏好设置 (优雅极简 ModernSwitch，彻底告别粗大丑陋按钮！)
          _SettingCard(
            title: '系统偏好设置',
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('关闭窗口行为', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const Spacer(),
                    Text(
                      settings.closeToTray ? '最小化到系统托盘' : '直接退出程序',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    ModernSwitch(
                      value: settings.closeToTray,
                      onChanged: (v) async {
                        settings.closeToTray = v;
                        await provider.saveSettings();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFF262626)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('开机自启动', style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const Spacer(),
                    Text(
                      settings.launchAtStartup ? '已启用' : '未启用',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    ModernSwitch(
                      value: settings.launchAtStartup,
                      onChanged: _setStartup,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 6. 本地穿透依赖
          _SettingCard(
            title: '本地穿透依赖组件',
            actionText: '重新检测',
            onAction: () async {
              await provider.recheckDependencies();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('穿透依赖检测完毕', style: TextStyle(fontSize: 12)),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Row(
              children: [
                _DepPill(name: 'cloudflared.exe', ready: provider.cloudflaredReady),
                const SizedBox(width: 14),
                _DepPill(name: 'ngrok.exe', ready: provider.ngrokReady),
                const Spacer(),
                Text(
                  provider.cloudflaredReady && provider.ngrokReady ? '全部组件就绪' : '组件检测就绪',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;
  final Widget child;

  const _SettingCard({
    required this.title,
    this.actionText,
    this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (actionText != null && onAction != null)
                InkWell(
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      actionText!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.sky,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DepPill extends StatelessWidget {
  final String name;
  final bool ready;

  const _DepPill({required this.name, required this.ready});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.green.withValues(alpha: 0.1)
            : AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: ready
              ? AppColors.green.withValues(alpha: 0.3)
              : AppColors.amber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: ready ? AppColors.green : AppColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w600,
              color: ready ? AppColors.green : AppColors.amber,
            ),
          ),
        ],
      ),
    );
  }
}
