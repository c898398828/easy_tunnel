import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../providers/tunnel_provider.dart';
import '../../theme.dart';

enum EngineType { cloudflare, ngrok }

class EngineConfigDialog extends StatefulWidget {
  final EngineType engine;

  const EngineConfigDialog({super.key, required this.engine});

  @override
  State<EngineConfigDialog> createState() => _EngineConfigDialogState();
}

class _EngineConfigDialogState extends State<EngineConfigDialog> {
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _apiTokenCtrl;
  bool _obscure = true;
  bool _obscureApi = true;
  bool _rechecking = false;
  bool _syncingApi = false;
  int _activeMode = 0; // 0: API 全自动模式, 1: 纯手动 Token 模式

  bool get _isCf => widget.engine == EngineType.cloudflare;

  @override
  void initState() {
    super.initState();
    final settings = context.read<TunnelProvider>().settings;
    _tokenCtrl = TextEditingController(
      text: _isCf ? settings.cloudflareToken : settings.ngrokToken,
    );
    _apiTokenCtrl = TextEditingController(
      text: settings.cloudflareApiToken,
    );
    if (_isCf && settings.cloudflareApiToken.isNotEmpty) {
      _activeMode = 0;
    } else if (_isCf && settings.cloudflareToken.isNotEmpty) {
      _activeMode = 1;
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _apiTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<TunnelProvider>();
    final val = _tokenCtrl.text.trim();
    if (_isCf) {
      provider.settings.cloudflareToken = val;
      provider.settings.cloudflareApiToken = _apiTokenCtrl.text.trim();
    } else {
      provider.settings.ngrokToken = val;
    }
    await provider.saveSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_isCf ? "Cloudflare" : "ngrok"} 凭据已保存',
          style: const TextStyle(fontSize: 12)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
    ));
    Navigator.pop(context);
  }

  Future<void> _syncCloudflare() async {
    final token = _apiTokenCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请输入有效 Cloudflare API Token', style: TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _syncingApi = true);
    final provider = context.read<TunnelProvider>();
    try {
      await provider.syncCloudflareAccount(token: token);
      if (!mounted) return;
      _tokenCtrl.text = provider.settings.cloudflareToken;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '账号同步成功！已自动获取 ${provider.cloudflareZones.length} 个域名与 Tunnel 凭据',
          style: const TextStyle(fontSize: 12),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('同步失败: $e', style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _syncingApi = false);
    }
  }

  Future<void> _recheck() async {
    setState(() => _rechecking = true);
    final provider = context.read<TunnelProvider>();
    await provider.recheckDependencies();
    if (!mounted) return;
    setState(() => _rechecking = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('依赖二进制检测完毕', style: TextStyle(fontSize: 12)),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 1),
    ));
  }

  String _mask(String token) {
    if (token.length <= 8) return token.isEmpty ? '未配置' : '****';
    return '${token.substring(0, 4)}****${token.substring(token.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final ready = _isCf ? provider.cloudflaredReady : provider.ngrokReady;
    final binPath = _isCf ? provider.deps.cloudflaredPath : provider.deps.ngrokPath;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
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
                  Icon(
                    _isCf ? Icons.cloud_outlined : Icons.view_in_ar_outlined,
                    size: 16,
                    color: _isCf ? AppColors.amber : AppColors.indigo,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isCf ? 'Cloudflare Tunnel 引擎配置' : 'ngrok 引擎配置',
                    style: const TextStyle(
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

            // 表单内容区
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 二进制组件状态行
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: ready ? AppColors.green : AppColors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isCf ? 'cloudflared.exe' : 'ngrok.exe',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Consolas',
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                binPath,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'Consolas',
                                  color: AppColors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: _rechecking ? null : _recheck,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              _rechecking ? '检测中...' : '重新检测',
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textSub),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (_isCf) ...[
                    // Cloudflare 配置方式分段选择
                    Row(
                      children: [
                        _ModeChip(
                          label: 'API 全自动同步 (推荐)',
                          selected: _activeMode == 0,
                          onTap: () => setState(() => _activeMode = 0),
                        ),
                        const SizedBox(width: 8),
                        _ModeChip(
                          label: '手动 Tunnel Token',
                          selected: _activeMode == 1,
                          onTap: () => setState(() => _activeMode = 1),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    if (_activeMode == 0) ...[
                      // API Token 模式
                      Row(
                        children: [
                          const Text('Cloudflare API Token',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                          const Spacer(),
                          Text('当前: ${_mask(provider.settings.cloudflareApiToken)}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _apiTokenCtrl,
                              obscureText: _obscureApi,
                              style: const TextStyle(fontSize: 12, fontFamily: 'Consolas', color: Colors.white),
                              decoration: _inputDecoration(
                                hint: '粘贴在官网生成的拥有 DNS+Tunnel 权限的 API 令牌',
                                obscure: _obscureApi,
                                onToggle: () => setState(() => _obscureApi = !_obscureApi),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _syncingApi ? null : _syncCloudflare,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.blue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _syncingApi ? '同步中...' : '同步账号与域名',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (provider.cloudflareZones.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.green),
                                  const SizedBox(width: 6),
                                  const Text('账号已连接，已加载托管域名：',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.green)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                provider.cloudflareZones.map((z) => z.name).join('、'),
                                style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', color: AppColors.textMain),
                              ),
                              if (provider.settings.cloudflareTunnelId.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '绑定隧道: ${provider.settings.cloudflareTunnelId}',
                                  style: const TextStyle(fontSize: 10, fontFamily: 'Consolas', color: AppColors.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      // 手动 Token 模式
                      Row(
                        children: [
                          const Text('Tunnel Token (eyJh...)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                          const Spacer(),
                          Text('当前: ${_mask(provider.settings.cloudflareToken)}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _tokenCtrl,
                        obscureText: _obscure,
                        style: const TextStyle(fontSize: 12, fontFamily: 'Consolas', color: Colors.white),
                        decoration: _inputDecoration(
                          hint: '粘贴 Cloudflare Tunnel 的运行长 Token',
                          obscure: _obscure,
                          onToggle: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ],
                  ] else ...[
                    // ngrok 模式
                    Row(
                      children: [
                        const Text('ngrok Authtoken',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                        const Spacer(),
                        Text('当前: ${_mask(provider.settings.ngrokToken)}',
                            style: const TextStyle(fontSize: 11, fontFamily: 'Consolas', color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _tokenCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(fontSize: 12, fontFamily: 'Consolas', color: Colors.white),
                      decoration: _inputDecoration(
                        hint: '输入 ngrok 个人控制台提供的 Authtoken',
                        obscure: _obscure,
                        onToggle: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ],
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
                      child: const Text('保存配置',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
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

  InputDecoration _inputDecoration({
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF141414),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 15,
            color: AppColors.textMuted,
          ),
          onPressed: onToggle,
        ),
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
      );
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue.withValues(alpha: 0.15) : const Color(0xFF181818),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AppColors.textSub,
          ),
        ),
      ),
    );
  }
}
