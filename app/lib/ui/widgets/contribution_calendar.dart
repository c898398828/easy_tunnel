import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

class ContributionCalendar extends StatelessWidget {
  const ContributionCalendar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 7 行 x 48 列的小方格点阵 (完全复刻图 5 底部)
          SizedBox(
            height: 82,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const rows = 7;
                const cols = 50;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(cols, (col) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(rows, (row) {
                        // 10月和11月末端有部分活跃绿色块 (对标图 5)
                        final isRecentHighlight = (col == 47 && (row == 0 || row == 3 || row == 4 || row == 5 || row == 6)) ||
                            (col == 48 && (row == 3 || row == 5)) ||
                            (col == 49 && (row == 1 || row == 4));
                        final isSporadic = (col == 30 && row == 0) || (col == 12 && row == 3) || (col == 4 && row == 4);

                        final Color blockColor;
                        if (isRecentHighlight) {
                          blockColor = (row % 2 == 0) ? AppColors.greenBright : AppColors.green;
                        } else if (isSporadic) {
                          blockColor = const Color(0xFF059669);
                        } else {
                          blockColor = const Color(0xFF242424);
                        }

                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: blockColor,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        );
                      }),
                    );
                  }),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // 月份时间刻度 (完全对标图 5: 11月 1月 2月 3月 4月 5月 6月 7月 8月 9月 10月 11月)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MonthLabel('11月'),
                _MonthLabel('1月'),
                _MonthLabel('2月'),
                _MonthLabel('3月'),
                _MonthLabel('4月'),
                _MonthLabel('5月'),
                _MonthLabel('6月'),
                _MonthLabel('7月'),
                _MonthLabel('8月'),
                _MonthLabel('9月'),
                _MonthLabel('10月'),
                _MonthLabel('11月'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthLabel extends StatelessWidget {
  final String text;

  const _MonthLabel(this.text);

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
