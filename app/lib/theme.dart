import 'package:material_ui/material_ui.dart';

class AppColors {
  // 原生纯正暗黑灰阶体系
  static const bg = Color(0xFF141414);
  static const sidebar = Color(0xFF181818);
  static const card = Color(0xFF1E1E1E);
  static const cardHover = Color(0xFF262626);
  static const border = Color(0xFF262626);
  static const borderLight = Color(0xFF333333);
  static const slotGray = Color(0xFF262626); // 柱状图等高深灰背景槽
  static const textMain = Color(0xFFEDEDED);
  static const textSub = Color(0xFFA1A1AA);
  static const textMuted = Color(0xFF71717A);

  // 状态指示色
  static const green = Color(0xFF10B981);
  static const greenBright = Color(0xFF34D399);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFF60A5FA);
  static const amber = Color(0xFFF59E0B);
  static const sky = Color(0xFF38BDF8);
  static const red = Color(0xFFEF4444);
  static const indigo = Color(0xFF818CF8);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    // 首选 Windows 原生 Segoe UI，中文自动平滑回退，排版锐利紧凑
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
    colorScheme: const ColorScheme.dark(
      primary: AppColors.blue,
      secondary: AppColors.green,
      surface: AppColors.card,
      error: AppColors.red,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: AppColors.textMain,
        fontSize: 11,
      ),
    ),
  );
}
