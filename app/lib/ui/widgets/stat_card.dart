import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Widget? gauge;
  final Color valueColor;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.gauge,
    this.valueColor = AppColors.textMain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 114,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 标题 + ⓘ 图标 (完全对标图 5)
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSub,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.info_outline_rounded,
                size: 11,
                color: AppColors.textMuted,
              ),
            ],
          ),

          if (gauge != null)
            Center(child: gauge!)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Segoe UI',
                    letterSpacing: -0.5,
                    color: valueColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// 半圆形速度计弧线仪表盘 (对标图 5 第一张卡片)
class SemiCircleGauge extends StatelessWidget {
  final double value; // 0..1
  final String label;

  const SemiCircleGauge({
    super.key,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);

    return SizedBox(
      width: 108,
      height: 54,
      child: CustomPaint(
        painter: _SemiCircleGaugePainter(clamped),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'Segoe UI',
                letterSpacing: -0.3,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SemiCircleGaugePainter extends CustomPainter {
  final double value;

  _SemiCircleGaugePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 4);
    final radius = size.width / 2 - 7;

    // 暗色背景半圆轨道
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF282828);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bg,
    );

    // 鲜绿高亮半圆弧
    if (value > 0.001) {
      final fg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = AppColors.green;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi,
        math.pi * value,
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SemiCircleGaugePainter oldDelegate) =>
      oldDelegate.value != value;
}

// 兼容接口
class RingProgress extends StatelessWidget {
  final double value;
  const RingProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) => SemiCircleGauge(
        value: value,
        label: '${(value.clamp(0.0, 1.0) * 100).toStringAsFixed(2)}%',
      );
}
