import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../providers/tunnel_provider.dart';
import '../theme.dart';
import 'widgets/engine_config_dialog.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();

    return Container(
      width: 200,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部导航 (对标图 5: 数据概览 / 隧道管理)
          _NavItem(
            icon: Icons.show_chart_rounded,
            iconColor: AppColors.sky,
            label: '数据概览',
            active: provider.currentTab == 0,
            onTap: () => provider.currentTab = 0,
          ),
          _NavItem(
            icon: Icons.bar_chart_rounded,
            iconColor: AppColors.amber,
            label: '隧道管理',
            active: provider.currentTab == 1,
            onTap: () => provider.currentTab = 1,
          ),

          const SizedBox(height: 16),

          // 穿透引擎配置 (对标图 5: 模型配置 / 已接管 绿色药丸胶囊)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '穿透引擎配置',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _EngineRow(
            icon: Icons.cloud_outlined,
            iconColor: AppColors.amber,
            name: 'Cloudflare',
            badgeText: '已接管',
            isGreen: true,
            onTap: () => showDialog(
              context: context,
              builder: (_) => const EngineConfigDialog(engine: EngineType.cloudflare),
            ),
          ),
          _EngineRow(
            icon: Icons.view_in_ar_outlined,
            iconColor: AppColors.indigo,
            name: 'ngrok',
            badgeText: provider.ngrokReady ? '已就绪' : '未就绪',
            isGreen: provider.ngrokReady,
            onTap: () => showDialog(
              context: context,
              builder: (_) => const EngineConfigDialog(engine: EngineType.ngrok),
            ),
          ),

          const SizedBox(height: 16),

          // 设置分组 (对标图 5)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '设置',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            iconColor: const Color(0xFF94A3B8),
            label: '系统设置',
            active: provider.currentTab == 2,
            onTap: () => provider.currentTab = 2,
          ),

          const Spacer(),

          // 底部 Docker 服务状态 (极简紧凑)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, size: 14, color: AppColors.sky),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Docker 服务',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${provider.dockerContainers.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'Consolas',
                    fontWeight: FontWeight.w600,
                    color: AppColors.green,
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

class _NavItem extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.active
                  ? const Color(0xFF262626)
                  : (_hover ? const Color(0xFF1E1E1E) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 15, color: widget.iconColor),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                    color: widget.active ? Colors.white : AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EngineRow extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String badgeText;
  final bool isGreen;
  final VoidCallback onTap;

  const _EngineRow({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.badgeText,
    required this.isGreen,
    required this.onTap,
  });

  @override
  State<_EngineRow> createState() => _EngineRowState();
}

class _EngineRowState extends State<_EngineRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6.5),
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFF1E1E1E) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 14, color: widget.iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _hover ? Colors.white : AppColors.textSub,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.isGreen
                        ? AppColors.green.withValues(alpha: 0.1)
                        : const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: widget.isGreen
                          ? AppColors.green.withValues(alpha: 0.35)
                          : const Color(0xFF333333),
                    ),
                  ),
                  child: Text(
                    widget.badgeText,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      color: widget.isGreen ? AppColors.green : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
