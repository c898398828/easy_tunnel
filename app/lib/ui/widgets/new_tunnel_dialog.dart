import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/tunnel_model.dart';
import '../../providers/tunnel_provider.dart';
import '../../services/cloudflare_api_service.dart';
import '../../services/port_monitor_service.dart';
import '../../theme.dart';
import 'engine_config_dialog.dart';

class NewTunnelDialog extends StatefulWidget {
  const NewTunnelDialog({super.key});

  @override
  State<NewTunnelDialog> createState() => _NewTunnelDialogState();
}

class _NewTunnelDialogState extends State<NewTunnelDialog> {
  final _nameCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8787');
  final _domainCtrl = TextEditingController();
  final _subDomainCtrl = TextEditingController(text: 't');

  String _provider = 'cloudflare';
  String _mode = 'quick';
  String? _dockerSelection;
  CloudflareZone? _selectedZone;
  PortStatus? _probe;
  bool _probing = false;
  final bool _autoSyncCf = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _portCtrl.dispose();
    _domainCtrl.dispose();
    _subDomainCtrl.dispose();
    super.dispose();
  }

  Future<void> _probePort() async {
    if (!mounted) return;
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) return;
    setState(() => _probing = true);
    final provider = context.read<TunnelProvider>();
    final result = await provider.inspectPort(port);
    if (!mounted) return;
    setState(() {
      _probe = result;
      _probing = false;
    });
  }

  Future<void> _killProbed() async {
    final probe = _probe;
    if (probe?.pid == null) return;
    final provider = context.read<TunnelProvider>();
    await provider.portMonitor.killProcessTree(probe!.pid!);
    if (!mounted) return;
    await _probePort();
  }

  void _applyDocker(String? label) {
    if (label == null) return;
    final provider = context.read<TunnelProvider>();
    for (final c in provider.dockerContainers) {
      if (c.label == label && c.hostPorts.isNotEmpty) {
        setState(() {
          _dockerSelection = c.name;
          _portCtrl.text = c.hostPorts.first.toString();
          if (_nameCtrl.text.isEmpty) _nameCtrl.text = c.name;
        });
        return;
      }
    }
  }

  Future<void> _save() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (_nameCtrl.text.trim().isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请填写隧道名称与合法端口 (1-65535)', style: TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final provider = context.read<TunnelProvider>();
    String? fullCustomDomain;

    if (_mode == 'custom') {
      if (_provider == 'cloudflare' && provider.cloudflareZones.isNotEmpty && _selectedZone != null) {
        final sub = _subDomainCtrl.text.trim();
        fullCustomDomain = sub.isEmpty ? _selectedZone!.name : '$sub.${_selectedZone!.name}';
      } else {
        fullCustomDomain = _domainCtrl.text.trim();
      }
    }

    setState(() => _isSaving = true);

    // 如果是 Cloudflare 专属模式且勾选了自动同步，自动通过官方 API 绑定路由与 DNS
    if (_provider == 'cloudflare' && _mode == 'custom' && _autoSyncCf && _selectedZone != null) {
      try {
        await provider.autoBindCloudflareTunnelRoute(
          zoneId: _selectedZone!.id,
          hostname: fullCustomDomain!,
          targetPort: port,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cloudflare 自动绑定提示: $e', style: const TextStyle(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }
    }

    final tunnel = TunnelModel(
      id: provider.newId(),
      name: _nameCtrl.text.trim(),
      targetPort: port,
      dockerContainerName: _dockerSelection,
      provider: _provider,
      mode: _mode,
      customDomain: fullCustomDomain,
    );

    await provider.addTunnel(tunnel);
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final dockerList = provider.dockerContainers.where((c) => c.hostPorts.isNotEmpty).toList();
    final hasCfApi = provider.cloudflareZones.isNotEmpty;

    if (_selectedZone == null && hasCfApi) {
      _selectedZone = provider.cloudflareZones.first;
    }

    String fullDomainPreview = '';
    if (_provider == 'cloudflare' && hasCfApi && _selectedZone != null) {
      final sub = _subDomainCtrl.text.trim();
      fullDomainPreview = sub.isEmpty ? _selectedZone!.name : '$sub.${_selectedZone!.name}';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 530,
        decoration: BoxDecoration(
          color: const Color(0xFF161920),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A303C)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏标题
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF222631))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.add_rounded, size: 18, color: AppColors.sky),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '新建内网穿透条目',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '将本地端口或 Docker 容器服务暴露发布至公网',
                        style: TextStyle(fontSize: 11, color: AppColors.textSub),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    hoverColor: const Color(0xFF222631),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 表单内容
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('隧道显示名称'),
                  TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: _inputDecoration('例如: 业务前端开发服务'),
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      const _FieldLabel('本地映射端口 (Target Port)'),
                      const Spacer(),
                      InkWell(
                        onTap: _probing ? null : _probePort,
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          _probing ? '探测中...' : '探测端口占用',
                          style: const TextStyle(fontSize: 11, color: AppColors.sky),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'Consolas',
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          decoration: _inputDecoration('8080'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          dropdownColor: const Color(0xFF161920),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                          decoration: _inputDecoration('从运行中的 Docker 容器快捷选择'),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textMuted),
                          items: dockerList
                              .map((c) => DropdownMenuItem(
                                    value: c.label,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.dns_outlined, size: 13, color: AppColors.sky),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            c.label,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                          onChanged: _applyDocker,
                        ),
                      ),
                    ],
                  ),

                  if (_probe != null) ...[
                    const SizedBox(height: 8),
                    _ProbeResult(
                      probe: _probe!,
                      onKill: _killProbed,
                    ),
                  ],

                  const SizedBox(height: 14),

                  const _FieldLabel('穿透服务商'),
                  Row(
                    children: [
                      _ChoiceTile(
                        icon: Icons.cloud_outlined,
                        iconColor: AppColors.amber,
                        label: 'Cloudflare',
                        subtitle: '免费无限制、高并发',
                        selected: _provider == 'cloudflare',
                        onTap: () => setState(() => _provider = 'cloudflare'),
                      ),
                      const SizedBox(width: 10),
                      _ChoiceTile(
                        icon: Icons.view_in_ar,
                        iconColor: AppColors.indigo,
                        label: 'ngrok',
                        subtitle: '极速稳定、易用',
                        selected: _provider == 'ngrok',
                        onTap: () => setState(() => _provider = 'ngrok'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  const _FieldLabel('公网域名分配'),
                  Row(
                    children: [
                      _ChoiceTile(
                        icon: Icons.shuffle_rounded,
                        label: '自动随机分配 (免配置)',
                        subtitle: _provider == 'cloudflare'
                            ? '即开即用 *.trycloudflare.com'
                            : '即开即用 *.ngrok-free.app',
                        selected: _mode == 'quick',
                        onTap: () => setState(() => _mode = 'quick'),
                      ),
                      const SizedBox(width: 10),
                      _ChoiceTile(
                        icon: Icons.lock_outline_rounded,
                        label: '专属自定义域名',
                        subtitle: _provider == 'cloudflare'
                            ? '绑定已有二级域名'
                            : '绑定已有二级或静态域名',
                        selected: _mode == 'custom',
                        onTap: () => setState(() => _mode = 'custom'),
                      ),
                    ],
                  ),

                  if (_mode == 'custom') ...[
                    const SizedBox(height: 12),

                    // 如果是 Cloudflare 且已同步到官方域名列表，展示全自动组合输入
                    if (_provider == 'cloudflare' && hasCfApi) ...[
                      Row(
                        children: [
                          // 子域名前缀输入框
                          SizedBox(
                            width: 130,
                            child: TextField(
                              controller: _subDomainCtrl,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'Consolas',
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              decoration: _inputDecoration('子域 (如 t)'),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                          ),
                          // 主域名下拉选择框
                          Expanded(
                            child: DropdownButtonFormField<CloudflareZone>(
                              initialValue: _selectedZone,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF161920),
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                              decoration: _inputDecoration('选择主域名'),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textMuted),
                              items: provider.cloudflareZones
                                  .map((z) => DropdownMenuItem(
                                        value: z,
                                        child: Text(z.name, style: const TextStyle(fontSize: 12, fontFamily: 'Consolas', color: Colors.white)),
                                      ))
                                  .toList(),
                              onChanged: (z) => setState(() => _selectedZone = z),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121418),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF222631)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 12, color: AppColors.sky),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '完整主机名: $fullDomainPreview (保存时自动添加 CNAME 与 Ingress 路由)',
                                style: const TextStyle(fontSize: 10.5, fontFamily: 'Consolas', color: AppColors.sky),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // 普通手动输入模式
                      TextField(
                        controller: _domainCtrl,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Consolas',
                          color: Colors.white,
                        ),
                        decoration: _inputDecoration('输入自定义域名，如 app.mydomain.com'),
                      ),
                      if (_provider == 'cloudflare' && !hasCfApi) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => const EngineConfigDialog(engine: EngineType.cloudflare),
                            );
                          },
                          child: const Text(
                            '💡 提示：在左侧 Cloudflare 配置中填入 API Token，即可自动列出域名并一键自动绑定',
                            style: TextStyle(fontSize: 10.5, color: AppColors.sky),
                          ),
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),

            // 底部操作按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF12141A),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: Color(0xFF222631))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _isSaving ? null : _save,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blue.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (_isSaving) ...[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _isSaving ? '自动绑定中...' : '保存并加入',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF0F1116),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF222631)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF222631)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSub,
          ),
        ),
      );
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E232E) : const Color(0xFF0F1116),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.blue : const Color(0xFF222631),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: iconColor ?? (selected ? AppColors.blue : AppColors.textMuted)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? Colors.white : AppColors.textMain,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProbeResult extends StatelessWidget {
  final PortStatus probe;
  final VoidCallback onKill;

  const _ProbeResult({required this.probe, required this.onKill});

  @override
  Widget build(BuildContext context) {
    if (!probe.inUse) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.green),
            const SizedBox(width: 6),
            Text('端口 ${probe.port} 空闲，可以立即进行穿透',
                style: const TextStyle(fontSize: 11, color: AppColors.green)),
          ],
        ),
      );
    }

    final isDocker = probe.processName?.toLowerCase().contains('docker') ?? false;
    final isOrphanTunnel = (probe.processName?.toLowerCase().contains('cloudflared') ?? false) ||
        (probe.processName?.toLowerCase().contains('ngrok') ?? false);

    if (isDocker) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.green),
            const SizedBox(width: 6),
            Text('端口 ${probe.port} 已由 Docker 容器正常监听中',
                style: const TextStyle(fontSize: 11, color: AppColors.green)),
          ],
        ),
      );
    }

    if (!isOrphanTunnel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.sky.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.sky.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.sensors_rounded, size: 12, color: AppColors.sky),
            const SizedBox(width: 6),
            Text('端口 ${probe.port} 已有本地服务监听: ${probe.processName ?? "未知"} (PID: ${probe.pid})',
                style: const TextStyle(fontSize: 11, color: AppColors.sky)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '端口 ${probe.port} 被残留隧道进程 ${probe.processName} (PID: ${probe.pid}) 占用',
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ),
          InkWell(
            onTap: onKill,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('强杀释放',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
