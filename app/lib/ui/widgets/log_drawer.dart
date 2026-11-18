import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

class LogDrawer extends StatefulWidget {
  const LogDrawer({super.key});

  @override
  State<LogDrawer> createState() => _LogDrawerState();
}

class _LogDrawerState extends State<LogDrawer> {
  final _scrollCtrl = ScrollController();
  bool _collapsed = false;
  String? _lastTunnelId;
  int _lastLogCount = 0;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final selectedId = provider.selectedLogTunnelId;
    final tunnel =
        selectedId == null ? null : provider.tunnelById(selectedId);
    final id = tunnel?.id;
    final count = tunnel?.logs.length ?? 0;
    if (id != _lastTunnelId || count != _lastLogCount) {
      _scrollToBottom();
      _lastTunnelId = id;
      _lastLogCount = count;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: _collapsed ? 30 : 165,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0E12),
        border: Border(top: BorderSide(color: Color(0xFF1F242F))),
      ),
      child: Column(
        children: [
          // 终端控制条
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF12151B),
              border: Border(bottom: BorderSide(color: Color(0xFF1E232E))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded,
                    size: 13, color: AppColors.green),
                const SizedBox(width: 8),
                const Text(
                  '控制台实时输出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppColors.textSub,
                  ),
                ),
                if (tunnel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${tunnel.name} (127.0.0.1:${tunnel.targetPort})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                        fontWeight: FontWeight.w600,
                        color: AppColors.sky,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (tunnel != null)
                  InkWell(
                    onTap: () => provider.clearLogs(tunnel.id),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181C24),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF262E3C)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 11, color: AppColors.textMuted),
                          SizedBox(width: 4),
                          Text('清空',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textSub)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      _collapsed = !_collapsed;
                      if (!_collapsed) _scrollToBottom();
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    child: Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 终端日志展示区
          if (!_collapsed)
            Expanded(
              child: tunnel == null
                  ? const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14, color: AppColors.textMuted),
                          SizedBox(width: 6),
                          Text('点击任意隧道卡片上的「实时日志」即可在此查看实时输出',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    )
                  : tunnel.logs.isEmpty
                      ? const Center(
                          child: Text('暂无日志输出，等待进程就绪...',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          itemCount: tunnel.logs.length,
                          itemBuilder: (_, i) => _buildLogLine(tunnel.logs[i]),
                        ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogLine(String raw) {
    Color textColor = AppColors.textSub;
    final lower = raw.toLowerCase();

    if (lower.contains('err') || lower.contains('fail') || lower.contains('error')) {
      textColor = AppColors.red;
    } else if (lower.contains('trycloudflare') || lower.contains('ngrok') || lower.contains('https://')) {
      textColor = AppColors.amber;
    } else if (lower.contains('registered') || lower.contains('success') || lower.contains('200 ok')) {
      textColor = AppColors.green;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SelectableText(
        raw,
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          fontFamily: 'Consolas',
          color: textColor,
        ),
      ),
    );
  }
}
