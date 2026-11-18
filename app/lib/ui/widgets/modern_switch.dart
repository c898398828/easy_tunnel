import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

class ModernSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ModernSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          width: 36,
          height: 20,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: value ? AppColors.blue : const Color(0xFF2E2E2E),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: value ? AppColors.blue : const Color(0xFF3D3D3D),
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeInOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: value ? Colors.white : const Color(0xFFA1A1AA),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
