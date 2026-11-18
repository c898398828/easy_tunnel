import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/tunnel_model.dart';
import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

class TunnelPerformanceBoard extends StatelessWidget {
  const TunnelPerformanceBoard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final tunnels = provider.tunnels;
    final globalAvg = provider.globalAvgLatencyMs;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 14, color: AppColors.sky),
              const SizedBox(width: 6),
              const Text(
                '各隧道实时性能与质量看板',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (globalAvg > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '全局平均延迟: ',
                        style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                      ),
                      Text(
                        '${globalAvg.toStringAsFixed(0)}ms',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w600,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // 隧道性能列表
          if (tunnels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '暂无已配置的隧道实例',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            )
          else
            ...tunnels.map((t) => _TunnelPerformanceRow(tunnel: t)),
        ],
      ),
    );
  }
}

class _TunnelPerformanceRow extends StatelessWidget {
  final TunnelModel tunnel;

  const _TunnelPerformanceRow({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final isRunning = tunnel.status == TunnelStatus.running;
    final isCf = tunnel.provider == 'cloudflare';
    final latency = tunnel.avgLatencyMs > 0 ? tunnel.avgLatencyMs : tunnel.lastLatencyMs;

    final Color latColor = !isRunning || latency == 0
        ? AppColors.textMuted
        : (latency < 60 ? AppColors.green : (latency < 150 ? AppColors.sky : AppColors.amber));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Row(
        children: [
          // 服务商小图标
          Icon(
            isCf ? Icons.cloud_outlined : Icons.view_in_ar_outlined,
            size: 14,
            color: isCf ? AppColors.amber : AppColors.indigo,
          ),
          const SizedBox(width: 8),

          // 隧道名称与目标端口（名称过长时省略，完整值悬浮可见）
          Flexible(
            child: Tooltip(
              message: tunnel.name,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                tunnel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(:${tunnel.targetPort})',
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              color: AppColors.textMuted,
            ),
          ),

          const SizedBox(width: 10),

          // 状态指示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isRunning
                  ? AppColors.green.withValues(alpha: 0.1)
                  : const Color(0xFF222222),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isRunning ? AppColors.green : AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isRunning ? '运行中' : '已停止',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: isRunning ? AppColors.green : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // 真实性能指标：平均延迟
          Row(
            children: [
              const Text('平均延迟: ',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textSub)),
              Text(
                tunnel.latencyDisplay,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                  color: latColor,
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          // 真实请求数
          Row(
            children: [
              const Text('请求: ',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textSub)),
              Text(
                '${tunnel.requestCount} 次',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          // 成功率
          Row(
            children: [
              const Text('成功率: ',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textSub)),
              Text(
                tunnel.requestCount == 0
                    ? '--'
                    : '${(tunnel.successRate * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                  color: tunnel.errorCount == 0 ? AppColors.green : AppColors.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
