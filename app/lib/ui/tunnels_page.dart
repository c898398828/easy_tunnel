import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/tunnel_model.dart';
import '../providers/tunnel_provider.dart';
import '../theme.dart';
import 'widgets/log_drawer.dart';
import 'widgets/new_tunnel_dialog.dart';
import 'widgets/tunnel_card.dart';

class TunnelsPage extends StatelessWidget {
  const TunnelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final total = provider.tunnels.length;
    final running = provider.tunnels
        .where((t) => t.status == TunnelStatus.running)
        .length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部标题栏
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '隧道管理',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E232E),
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: const Color(0xFF2C3442)),
                              ),
                              child: Text(
                                '$running / $total 在线',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'Consolas',
                                  fontWeight: FontWeight.w600,
                                  color: running > 0
                                      ? AppColors.green
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '管理本地端口与 Docker 容器上的内网穿透实例，支持双引擎并发托管',
                          style:
                              TextStyle(fontSize: 11, color: AppColors.textSub),
                        ),
                      ],
                    ),
                    const Spacer(),

                    // 刷新状态按钮
                    Tooltip(
                      message: '刷新本地端口与 Docker 容器状态',
                      child: InkWell(
                        onTap: () async {
                          await provider.inspectAllPorts();
                          await provider.refreshDocker();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已刷新系统端口与 Docker 状态',
                                  style: TextStyle(fontSize: 12)),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161920),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF242A36)),
                          ),
                          child: const Icon(Icons.refresh_rounded,
                              size: 16, color: AppColors.textSub),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 新建穿透条目按钮
                    InkWell(
                      onTap: () => showDialog(
                          context: context,
                          builder: (_) => const NewTunnelDialog()),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.blue.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add_rounded,
                                size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              '新建穿透条目',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // 隧道卡片列表
                if (provider.tunnels.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 70),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161920),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF232732)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E232E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.hub_outlined,
                              size: 24, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 14),
                        const Text('尚未配置任何内网穿透隧道',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        const Text('点击右上角「新建穿透条目」即可快速配置本地或 Docker 端口',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSub)),
                      ],
                    ),
                  )
                else
                  ...provider.tunnels.map((t) => TunnelCard(tunnel: t)),
              ],
            ),
          ),
        ),
        // 底部实时控制台日志抽屉
        const LogDrawer(),
      ],
    );
  }
}
