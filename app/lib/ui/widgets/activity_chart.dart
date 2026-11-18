import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../providers/tunnel_provider.dart';
import '../../theme.dart';
import 'custom_time_dialog.dart';

class ActivityChart extends StatefulWidget {
  final TimeRangeOption timeRange;
  final DateTime? customStart;
  final DateTime? customEnd;

  const ActivityChart({
    super.key,
    this.timeRange = TimeRangeOption.oneMonth,
    this.customStart,
    this.customEnd,
  });

  @override
  State<ActivityChart> createState() => _ActivityChartState();
}

class _ActivityChartState extends State<ActivityChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final config = _getChartConfig(widget.timeRange, provider);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          MouseRegion(
            onExit: (_) => setState(() => _hoveredIndex = null),
            child: SizedBox(
              height: 126,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final slotWidth = totalWidth / config.totalSlots;

                  double tooltipLeft = 0;
                  if (_hoveredIndex != null) {
                    tooltipLeft = (_hoveredIndex! * slotWidth + slotWidth / 2 - 95)
                        .clamp(8.0, totalWidth - 198);
                  }

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 黄色平均虚线
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 56,
                        child: Row(
                          children: [
                            const Text(
                              '平均',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.amber,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: CustomPaint(
                                painter: _DashedLinePainter(
                                  color: AppColors.amber.withValues(alpha: 0.75),
                                  dashWidth: 4,
                                  dashSpace: 3,
                                ),
                                child: const SizedBox(height: 1),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 等高背景槽与动态真实生长柱
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(config.totalSlots, (i) {
                            final fillRatio = config.fills[i] ?? 0.0;
                            final hasData = fillRatio > 0.0;
                            final isHovered = _hoveredIndex == i;

                            return Expanded(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) => setState(() => _hoveredIndex = i),
                                child: Container(
                                  color: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      height: 96,
                                      decoration: BoxDecoration(
                                        color: isHovered
                                            ? const Color(0xFF333333)
                                            : AppColors.slotGray,
                                        borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(1.5)),
                                      ),
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: AnimatedFractionallySizedBox(
                                          duration: const Duration(milliseconds: 260),
                                          curve: Curves.easeOutCubic,
                                          heightFactor: hasData ? fillRatio : 0.0,
                                          child: hasData
                                              ? Column(
                                                  children: [
                                                    Expanded(
                                                      flex: 80,
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          color: isHovered
                                                              ? AppColors.greenBright
                                                              : AppColors.green,
                                                          borderRadius: const BorderRadius.vertical(
                                                              top: Radius.circular(1.5)),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 20,
                                                      child: Container(
                                                        color: isHovered
                                                            ? AppColors.blueLight
                                                            : AppColors.blue,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // 真实悬浮提示窗 (平时完全隐藏)
                      if (_hoveredIndex != null && _hoveredIndex! < config.totalSlots)
                        Positioned(
                          top: 0,
                          left: tooltipLeft,
                          child: IgnorePointer(
                            child: Container(
                              width: 190,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: const Color(0xF8181818),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF383838)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _buildTooltipContent(config, _hoveredIndex!, provider),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 10),

          // X 轴刻度
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: config.labels.map((l) => _AxisLabel(l)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltipContent(_ChartConfig config, int index, TunnelProvider provider) {
    final dateText = config.slotTitles[index];
    final reqs = config.counts[index] ?? 0;
    final success = config.successes[index] ?? 0;
    final avgLat = provider.globalAvgLatencyMs > 0 ? '${provider.globalAvgLatencyMs.toStringAsFixed(0)}ms' : '--';
    final successRate = reqs > 0 ? '${(success / reqs * 100).toStringAsFixed(0)}%' : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              dateText,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Text(
              '$reqs 请求',
              style: const TextStyle(
                fontSize: 9.5,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w600,
                color: AppColors.textSub,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _TooltipRow('请求调用', '$reqs 次', AppColors.sky),
        _TooltipRow('响应成功', '$success 次 ($successRate)', AppColors.green),
        _TooltipRow('平均延迟', avgLat, AppColors.amber),
      ],
    );
  }

  _ChartConfig _getChartConfig(TimeRangeOption option, TunnelProvider provider) {
    final now = DateTime.now();
    switch (option) {
      case TimeRangeOption.tenMinutes:
        // 最近 10 个自然分钟，最后一格为当前分钟。
        final start = DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .subtract(const Duration(minutes: 9));
        return _buildConfig(
          provider,
          start: start,
          slotCount: 10,
          slotDuration: const Duration(minutes: 1),
          granularity: 'minute',
          labels: ['10分前', '8分', '6分', '4分', '2分', '现在'],
        );

      case TimeRangeOption.oneHour:
        // 最近 12 个五分钟区间。
        final end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
        final start = end.subtract(const Duration(minutes: 60));
        return _buildConfig(
          provider,
          start: start,
          slotCount: 12,
          slotDuration: const Duration(minutes: 5),
          granularity: 'minute',
          labels: ['60分前', '50分', '40分', '30分', '20分', '10分', '现在'],
        );

      case TimeRangeOption.oneDay:
        // 自然日 00:00 至 23:00，每格一小时。
        final dayStart = DateTime(now.year, now.month, now.day);
        return _buildConfig(
          provider,
          start: dayStart,
          slotCount: 24,
          slotDuration: const Duration(hours: 1),
          granularity: 'hour',
          labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '23:00'],
        );

      case TimeRangeOption.oneWeek:
        // 本周一至周日。
        final today = DateTime(now.year, now.month, now.day);
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return _buildConfig(
          provider,
          start: monday,
          slotCount: 7,
          slotDuration: const Duration(days: 1),
          granularity: 'day',
          labels: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
        );

      case TimeRangeOption.fourHours:
        // 最近 16 个十五分钟区间。
        final end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
        final start = end.subtract(const Duration(hours: 4));
        return _buildConfig(
          provider,
          start: start,
          slotCount: 16,
          slotDuration: const Duration(minutes: 15),
          granularity: 'minute',
          labels: ['4小时前', '3小时', '2小时', '1小时', '现在'],
          titleFormatter: (t) =>
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        );

      case TimeRangeOption.twentyFourHours:
        // 滚动最近 24 小时。
        final end = DateTime(now.year, now.month, now.day, now.hour);
        final start = end.subtract(const Duration(hours: 23));
        return _buildConfig(
          provider,
          start: start,
          slotCount: 24,
          slotDuration: const Duration(hours: 1),
          granularity: 'hour',
          labels: ['24小时前', '18小时', '12小时', '6小时', '现在'],
          titleFormatter: (t) =>
              '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:00',
        );

      case TimeRangeOption.custom:
        final start = widget.customStart ?? now.subtract(const Duration(hours: 1));
        final end = widget.customEnd ?? now;
        final span = end.difference(start);
        final totalMinutes = span.inMinutes <= 0 ? 1 : span.inMinutes;
        // 自定义区间固定 16 格，每格宽度按跨度自适应；
        // 粒度为小时/天时把格宽对齐到整小时/整天，避免相邻格重复统计。
        var slotMinutes = (totalMinutes / 16).ceil().clamp(1, 24 * 60);
        final String granularity;
        if (slotMinutes >= 1440) {
          granularity = 'day';
          slotMinutes = (slotMinutes / 1440).ceil() * 1440;
        } else if (slotMinutes >= 60) {
          granularity = 'hour';
          slotMinutes = (slotMinutes / 60).ceil() * 60;
        } else {
          granularity = 'minute';
        }
        return _buildConfig(
          provider,
          start: DateTime(start.year, start.month, start.day, start.hour,
              granularity == 'minute' ? start.minute : 0),
          slotCount: 16,
          slotDuration: Duration(minutes: slotMinutes),
          granularity: granularity,
          labels: ['起始', '25%', '50%', '75%', '截止'],
          titleFormatter: (t) =>
              '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        );

      case TimeRangeOption.oneMonth:
        // 过去 31 个自然日，最后一格为今天。
        final today = DateTime(now.year, now.month, now.day);
        final start = today.subtract(const Duration(days: 30));
        return _buildConfig(
          provider,
          start: start,
          slotCount: 31,
          slotDuration: const Duration(days: 1),
          granularity: 'day',
          labels: null,
          titleFormatter: (t) => '${t.month}/${t.day}',
        );
    }
  }

  /// 按真实时间段从历史统计中取值，柱高按该时间跨度内的峰值归一化。
  _ChartConfig _buildConfig(
    TunnelProvider provider, {
    required DateTime start,
    required int slotCount,
    required Duration slotDuration,
    required String granularity,
    List<String>? labels,
    String Function(DateTime slotStart)? titleFormatter,
  }) {
    final counts = <int, int>{};
    final successes = <int, int>{};
    final slotTitles = <String>[];
    var maxCount = 0;

    final fmt = titleFormatter ??
        (DateTime t) => '${t.month}/${t.day}';

    for (var i = 0; i < slotCount; i++) {
      final slotStart = start.add(slotDuration * i);
      final slotEnd = slotStart.add(slotDuration);
      final bucket = provider.usage.range(slotStart, slotEnd, granularity);
      if (bucket.total > 0) {
        counts[i] = bucket.total;
        successes[i] = bucket.success;
        if (bucket.total > maxCount) maxCount = bucket.total;
      }
      slotTitles.add(fmt(slotStart));
    }

    final fills = <int, double>{};
    if (maxCount > 0) {
      for (final entry in counts.entries) {
        // 占比按峰值归一化；有数据但极小的区间保留最小可见高度。
        fills[entry.key] = (entry.value / maxCount).clamp(0.06, 1.0);
      }
    }

    if (labels == null) {
      // 31 天视图：等距抽 11 个刻度并标出今天。
      final ticks = <String>[];
      for (var i = 0; i < slotCount - 1; i += 3) {
        ticks.add(slotTitles[i]);
      }
      ticks.add('${slotTitles.last}(今)');
      labels = ticks;
    }

    return _ChartConfig(
      totalSlots: slotCount,
      fills: fills,
      counts: counts,
      successes: successes,
      labels: labels,
      slotTitles: slotTitles,
    );
  }
}

class _ChartConfig {
  final int totalSlots;
  final Map<int, double> fills;
  final Map<int, int> counts;
  final Map<int, int> successes;
  final List<String> labels;
  final List<String> slotTitles;

  _ChartConfig({
    required this.totalSlots,
    required this.fills,
    required this.counts,
    required this.successes,
    required this.labels,
    required this.slotTitles,
  });
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  _DashedLinePainter({
    required this.color,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}

class _AxisLabel extends StatelessWidget {
  final String text;

  const _AxisLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontFamily: 'Segoe UI',
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      );
}

class _TooltipRow extends StatelessWidget {
  final String label;
  final String value;
  final Color dotColor;

  const _TooltipRow(this.label, this.value, this.dotColor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                color: AppColors.textSub,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 9.5,
              fontFamily: 'Consolas',
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
