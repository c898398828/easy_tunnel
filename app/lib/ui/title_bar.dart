// window_manager 0.7.0 moved the 0.5.x-compatible API to legacy.dart.
// ignore_for_file: deprecated_member_use
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/legacy.dart';

import '../theme.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 38,
        color: AppColors.sidebar,
        padding: const EdgeInsets.only(left: 14, right: 0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'assets/tray_icon.ico',
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: AppColors.blue,
                  ),
                  child: const Icon(Icons.bolt_rounded, size: 12, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Easy Tunnel',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'v1.0.1',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Consolas',
                color: AppColors.textMuted,
              ),
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: Icons.crop_square_rounded,
              iconSize: 13,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowButton(
              icon: Icons.close_rounded,
              hoverColor: AppColors.red,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color? hoverColor;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 15,
    this.hoverColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 38,
          color: _hover
              ? (widget.hoverColor ?? const Color(0xFF1E222B))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hover ? Colors.white : AppColors.textSub,
          ),
        ),
      ),
    );
  }
}
