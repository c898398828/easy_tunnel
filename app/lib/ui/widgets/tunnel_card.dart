import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/tunnel_model.dart';
import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

class TunnelCard extends StatelessWidget {
  final TunnelModel tunnel;

  const TunnelCard({super.key, required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final portStatus = provider.portStatuses[tunnel.id];
    final orphan = provider.isOrphanOccupied(tunnel);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部行：服务名称、提供商标签、状态标签、Docker 标签、右侧操作
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              children: [
                // 标题与标签组：空间不足时优先压缩名称与容器标签，操作按钮保持完整
                Expanded(
                  child: Row(
                    children: [
                      // 服务名称
                      Flexible(
                        child: Tooltip(
                          message: tunnel.name,
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            tunnel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 穿透类型微标
                      _ProviderBadge(provider: tunnel.provider, mode: tunnel.mode),
                      const SizedBox(width: 6),

                      // 状态微标
                      _StatusBadge(status: tunnel.status, pid: tunnel.processPid),

                      // Docker 容器微标
                      if (tunnel.dockerContainerName != null) ...[
                        const SizedBox(width: 6),
                        Flexible(child: _TagChip(tunnel.dockerContainerName!)),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // 实时日志按钮
                _ActionButton(
                  icon: Icons.terminal_rounded,
                  label: '实时日志',
                  active: provider.selectedLogTunnelId == tunnel.id,
                  onTap: () => provider.selectedLogTunnelId = tunnel.id,
                ),
                const SizedBox(width: 6),

                // 启动 / 停止 主按钮
                _StartStopButton(tunnel: tunnel),

                const SizedBox(width: 4),

                // 更多菜单
                _MoreMenu(tunnel: tunnel),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // 第二行：目标端口与监听状态 (极简、无冗余 emoji)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _PortChip('127.0.0.1:${tunnel.targetPort}'),
                const SizedBox(width: 10),
                Flexible(
                  child: _PortHealth(
                    tunnel: tunnel,
                    orphan: orphan,
                    inUse: portStatus?.inUse,
                    processName: portStatus?.processName,
                    pid: portStatus?.pid,
                  ),
                ),
                if (tunnel.status == TunnelStatus.running) ...[
                  const SizedBox(width: 10),
                  // 空间不足时等比缩小指标徽标，保证端口状态优先显示完整。
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _TunnelMetricsBadge(tunnel: tunnel),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 公网地址栏
          if (tunnel.publicUrl != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _UrlBar(url: tunnel.publicUrl!),
            ),
          ],

          // 错误信息栏
          if (tunnel.status == TunnelStatus.error && tunnel.lastError != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 13, color: AppColors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tunnel.lastError!,
                      style: const TextStyle(fontSize: 11, color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortHealth extends StatelessWidget {
  final TunnelModel tunnel;
  final bool orphan;
  final bool? inUse;
  final String? processName;
  final int? pid;

  const _PortHealth({
    required this.tunnel,
    required this.orphan,
    this.inUse,
    this.processName,
    this.pid,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TunnelProvider>();

    // 1. 真正的孤儿旧隧道进程冲突 (cloudflared/ngrok)
    if (orphan) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '残留进程: ${processName ?? "cloudflared"} (PID: $pid)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'Consolas',
                      color: AppColors.amber,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => provider.killOccupant(tunnel.id),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '释放端口',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 2. 检测中
    if (inUse == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textMuted),
          ),
          SizedBox(width: 5),
          Text('检测中...', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      );
    }

    // 3. Docker 代理监听中
    final isDocker = tunnel.dockerContainerName != null ||
        (processName?.toLowerCase().contains('docker') ?? false);

    if (inUse == true && isDocker) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'Docker 代理就绪',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.green,
              ),
            ),
          ],
        ),
      );
    }

    // 4. 普通本地服务监听中 (node, python, etc.)
    if (inUse == true) {
      final isRunning = tunnel.status == TunnelStatus.running;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isRunning
              ? AppColors.green.withValues(alpha: 0.1)
              : AppColors.sky.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isRunning
                ? AppColors.green.withValues(alpha: 0.3)
                : AppColors.sky.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: isRunning ? AppColors.green : AppColors.sky,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                isRunning
                    ? '本地端口正常'
                    : '本地服务已就绪: ${processName ?? ""}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isRunning ? AppColors.green : AppColors.sky,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 5. 端口空闲
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: AppColors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        const Text(
          '端口空闲',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _UrlBar extends StatelessWidget {
  final String url;

  const _UrlBar({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Text(
            '公网入口',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSub,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              url,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w600,
                color: AppColors.sky,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制: $url', style: const TextStyle(fontSize: 11)),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F1F),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('复制', style: TextStyle(fontSize: 10.5, color: AppColors.textSub)),
            ),
          ),
          const SizedBox(width: 5),
          InkWell(
            onTap: () => Process.run('cmd', ['/c', 'start', '', url]),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.4)),
              ),
              child: const Text('打开', style: TextStyle(fontSize: 10.5, color: AppColors.sky)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  final TunnelModel tunnel;

  const _StartStopButton({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TunnelProvider>();
    final running = tunnel.status == TunnelStatus.running ||
        tunnel.status == TunnelStatus.starting ||
        tunnel.status == TunnelStatus.reconnecting;

    return InkWell(
      onTap: () => running
          ? provider.stopTunnel(tunnel.id)
          : provider.startTunnel(tunnel.id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5.5),
        decoration: BoxDecoration(
          color: running ? const Color(0xFF261C1C) : AppColors.blue,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: running ? AppColors.red.withValues(alpha: 0.5) : AppColors.blue,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 13,
              color: running ? AppColors.red : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              running ? '停止' : '启动',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: running ? AppColors.red : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF262626) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppColors.borderLight : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? AppColors.sky : AppColors.textSub),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Colors.white : AppColors.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final TunnelModel tunnel;

  const _MoreMenu({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TunnelProvider>();

    return PopupMenuButton<String>(
      icon: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.more_horiz_rounded, size: 14, color: AppColors.textSub),
      ),
      color: const Color(0xFF1E1E1E),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      onSelected: (v) async {
        if (v == 'copy_port') {
          Clipboard.setData(ClipboardData(text: '127.0.0.1:${tunnel.targetPort}'));
        } else if (v == 'delete') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.borderLight),
              ),
              title: const Text('删除隧道', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              content: Text('确定删除隧道「${tunnel.name}」吗？',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除', style: TextStyle(color: AppColors.red)),
                ),
              ],
            ),
          );
          if (ok == true) {
            await provider.removeTunnel(tunnel.id);
          }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'copy_port',
          height: 34,
          child: Text('复制本地地址', style: TextStyle(fontSize: 11)),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'delete',
          height: 34,
          child: Text('删除隧道', style: TextStyle(fontSize: 11, color: AppColors.red)),
        ),
      ],
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  final String provider;
  final String mode;

  const _ProviderBadge({required this.provider, required this.mode});

  @override
  Widget build(BuildContext context) {
    final isCf = provider == 'cloudflare';
    final label = isCf ? (mode == 'custom' ? 'Cloudflare 专属' : 'Cloudflare 快速') : 'ngrok';
    final color = isCf ? AppColors.amber : AppColors.indigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TunnelStatus status;
  final int? pid;

  const _StatusBadge({required this.status, this.pid});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      TunnelStatus.running => (AppColors.green, '运行中${pid != null ? " ($pid)" : ""}'),
      TunnelStatus.starting => (AppColors.blue, '启动中...'),
      TunnelStatus.reconnecting => (AppColors.amber, '重连中...'),
      TunnelStatus.error => (AppColors.red, '异常'),
      TunnelStatus.stopped => (AppColors.textMuted, '已停止'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;

  const _TagChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '容器: $text',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          '容器: $text',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'Consolas',
            color: AppColors.textSub,
          ),
        ),
      ),
    );
  }
}

class _PortChip extends StatelessWidget {
  final String text;

  const _PortChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'Consolas',
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
      ),
    );
  }
}

class _TunnelMetricsBadge extends StatelessWidget {
  final TunnelModel tunnel;

  const _TunnelMetricsBadge({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final latency = tunnel.avgLatencyMs > 0 ? tunnel.avgLatencyMs : tunnel.lastLatencyMs;
    final Color latColor = latency == 0
        ? AppColors.textMuted
        : (latency < 60 ? AppColors.green : (latency < 150 ? AppColors.sky : AppColors.amber));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 12, color: latColor),
          const SizedBox(width: 4),
          Text(
            '延迟: ${tunnel.latencyDisplay}',
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w600,
              color: latColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '请求: ${tunnel.requestCount} 次',
            style: const TextStyle(
              fontSize: 10.5,
              fontFamily: 'Consolas',
              color: AppColors.textSub,
            ),
          ),
          if (tunnel.requestCount > 0) ...[
            const SizedBox(width: 8),
            Text(
              '成功率: ${(tunnel.successRate * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'Consolas',
                color: AppColors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

