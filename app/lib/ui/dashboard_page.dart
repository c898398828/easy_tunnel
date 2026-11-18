import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../providers/tunnel_provider.dart';
import '../theme.dart';
import 'widgets/activity_chart.dart';
import 'widgets/custom_time_dialog.dart';
import 'widgets/stat_card.dart';
import 'widgets/tunnel_performance_board.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  TimeRangeOption _selectedRange = TimeRangeOption.oneMonth; // 默认为 "近一个月"
  DateTime _customStart = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _customEnd = DateTime.now();

  void _openCustomTimeDialog() {
    showDialog(
      context: context,
      builder: (_) => CustomTimeDialog(
        initialStart: _customStart,
        initialEnd: _customEnd,
        onSelected: (option, start, end) {
          setState(() {
            _selectedRange = option;
            _customStart = start;
            _customEnd = end;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final total = provider.tunnels.length;
    final running = provider.runningCount;
    final rate = provider.onlineRate;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏 + 时间筛选胶囊 (对标图 5/8/17)
          Row(
            children: [
              const Text(
                '概览',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _TimeChip('近1小时',
                        active: _selectedRange == TimeRangeOption.oneHour,
                        onTap: () => setState(() => _selectedRange = TimeRangeOption.oneHour)),
                    _TimeChip('近1自然日',
                        active: _selectedRange == TimeRangeOption.oneDay,
                        onTap: () => setState(() => _selectedRange = TimeRangeOption.oneDay)),
                    _TimeChip('近10分钟',
                        active: _selectedRange == TimeRangeOption.tenMinutes,
                        onTap: () => setState(() => _selectedRange = TimeRangeOption.tenMinutes)),
                    _TimeChip('近一周',
                        active: _selectedRange == TimeRangeOption.oneWeek,
                        onTap: () => setState(() => _selectedRange = TimeRangeOption.oneWeek)),
                    _TimeChip('近一个月',
                        active: _selectedRange == TimeRangeOption.oneMonth,
                        onTap: () => setState(() => _selectedRange = TimeRangeOption.oneMonth)),
                    _TimeChip('自定义',
                        active: _selectedRange == TimeRangeOption.custom ||
                            _selectedRange == TimeRangeOption.fourHours ||
                            _selectedRange == TimeRangeOption.twentyFourHours,
                        onTap: _openCustomTimeDialog),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () async {
                        await provider.inspectAllPorts();
                        await provider.refreshDocker();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已刷新系统端口与服务状态', style: TextStyle(fontSize: 12)),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        child: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textSub),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 核心活动堆叠图表 (动态响应时间切换，带平滑生长动画，平时纯净无浮窗)
          ActivityChart(
            timeRange: _selectedRange,
            customStart: _customStart,
            customEnd: _customEnd,
          ),

          const SizedBox(height: 10),

          // 核心指标 4 宫格 (完全由 Easy Tunnel 真实业务数据驱动！)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 隧道在线率 (真实半圆仪表盘)
              Expanded(
                child: StatCard(
                  title: '隧道在线率',
                  value: '${(rate * 100).toStringAsFixed(1)}%',
                  subtitle: '$running / $total 在线',
                  gauge: SemiCircleGauge(
                    value: rate,
                    label: '${(rate * 100).toStringAsFixed(1)}%',
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. 穿透连接数 (真实今日连接与成功/异常分布)
              Expanded(
                child: StatCard(
                  title: '穿透连接数',
                  value: '${provider.totalRequestsToday}',
                  subtitle: '成功 ${provider.successRequestsToday} / 异常 ${provider.errorRequestsToday}',
                ),
              ),
              const SizedBox(width: 10),

              // 3. 托管服务 (真实配置服务统计)
              Expanded(
                child: StatCard(
                  title: '托管服务',
                  value: '$total',
                  subtitle: 'Docker ${provider.dockerTunnelCount} / 本地 ${provider.localTunnelCount}',
                ),
              ),
              const SizedBox(width: 10),

              // 4. 端口健康 (真实端口监听与冲突诊断)
              Expanded(
                child: StatCard(
                  title: '端口状态',
                  value: provider.conflictCount > 0 ? '${provider.conflictCount} 处冲突' : 'active',
                  valueColor: provider.conflictCount > 0 ? AppColors.amber : AppColors.textMain,
                  subtitle: '监听中 ${provider.listeningPortCount} / 待启动 ${provider.idlePortCount}',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 底部各隧道实时运行性能与延迟看板 (完全由真实物理探测数据驱动！)
          const TunnelPerformanceBoard(),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TimeChip(this.label, {this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E2E2E) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Segoe UI',
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : AppColors.textSub,
          ),
        ),
      ),
    );
  }
}
