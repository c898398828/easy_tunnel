import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

enum TimeRangeOption {
  tenMinutes,
  oneHour,
  oneDay,
  oneWeek,
  oneMonth,
  fourHours,
  twentyFourHours,
  custom,
}

class CustomTimeDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final void Function(TimeRangeOption option, DateTime start, DateTime end) onSelected;

  const CustomTimeDialog({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.onSelected,
  });

  @override
  State<CustomTimeDialog> createState() => _CustomTimeDialogState();
}

class _CustomTimeDialogState extends State<CustomTimeDialog> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _startCtrl = TextEditingController(text: _formatDate(_start));
    _endCtrl = TextEditingController(text: _formatDate(_end));
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      alignment: Alignment.topRight,
      insetPadding: const EdgeInsets.only(top: 80, right: 30),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xF8181818),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2C2C2C)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部快捷选项 (对标图 17: 近4小时 / 近24小时)
            Row(
              children: [
                _QuickButton(
                  label: '近4小时',
                  onTap: () {
                    final now = DateTime.now();
                    widget.onSelected(TimeRangeOption.fourHours, now.subtract(const Duration(hours: 4)), now);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(width: 8),
                _QuickButton(
                  label: '近24小时',
                  onTap: () {
                    final now = DateTime.now();
                    widget.onSelected(TimeRangeOption.twentyFourHours, now.subtract(const Duration(hours: 24)), now);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 开始时间 (对标图 17)
            Row(
              children: [
                const Text(
                  '开始时间',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      controller: _startCtrl,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'Consolas',
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 结束时间 (对标图 17)
            Row(
              children: [
                const Text(
                  '结束时间',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      controller: _endCtrl,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'Consolas',
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 应用按钮
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  widget.onSelected(TimeRangeOption.custom, _start, _end);
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '确定',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSub,
            ),
          ),
        ),
      ),
    );
  }
}
