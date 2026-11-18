import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

class PortConfigDialog extends StatefulWidget {
  const PortConfigDialog({super.key});

  @override
  State<PortConfigDialog> createState() => _PortConfigDialogState();
}

class _PortConfigDialogState extends State<PortConfigDialog> {
  late final TextEditingController _metricsPortCtrl;
  late int _selectedInterval;

  @override
  void initState() {
    super.initState();
    final settings = context.read<TunnelProvider>().settings;
    _metricsPortCtrl = TextEditingController(text: settings.metricsPort.toString());
    _selectedInterval = settings.inspectIntervalSeconds;
  }

  @override
  void dispose() {
    _metricsPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_metricsPortCtrl.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请输入合法的非保留端口 (1024 - 65535)', style: TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final provider = context.read<TunnelProvider>();
    provider.settings.metricsPort = port;
    provider.settings.inspectIntervalSeconds = _selectedInterval;
    await provider.saveSettings();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('端口设置已更新', style: TextStyle(fontSize: 12)),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 1),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 440,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏标题
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 16, color: AppColors.sky),
                  const SizedBox(width: 8),
                  const Text(
                    '端口与健康巡检设置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),

            // 表单内容
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '指标代理端口 (Metrics Port)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _metricsPortCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '默认 20241',
                      hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF141414),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.blue),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    '健康巡检频率',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedInterval,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF161920),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF141414),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('每 3 秒 (极速灵敏)')),
                      DropdownMenuItem(value: 6, child: Text('每 6 秒 (默认推荐)')),
                      DropdownMenuItem(value: 10, child: Text('每 10 秒 (标准巡检)')),
                      DropdownMenuItem(value: 15, child: Text('每 15 秒 (轻量节能)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedInterval = val);
                      }
                    },
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      '端口被占用时会自动选择新的随机端口并保存。修改后需要重启软件才会生效。',
                      style: TextStyle(fontSize: 10.5, height: 1.4, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),

            // 底部操作按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF161616),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _save,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '保存配置',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
