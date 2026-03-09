import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';

class ProviderNetworkPage extends StatefulWidget {
  const ProviderNetworkPage({
    super.key,
    required this.providerKey,
    required this.providerDisplayName,
  });
  final String providerKey;
  final String providerDisplayName;

  @override
  State<ProviderNetworkPage> createState() => _ProviderNetworkPageState();
}

class _ProviderNetworkPageState extends State<ProviderNetworkPage> {
  bool _proxyEnabled = false;
  final _proxyHostCtrl = TextEditingController();
  final _proxyPortCtrl = TextEditingController(text: '8080');
  final _proxyUserCtrl = TextEditingController();
  final _proxyPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    _proxyEnabled = cfg.proxyEnabled ?? false;
    _proxyHostCtrl.text = cfg.proxyHost ?? '';
    _proxyPortCtrl.text = cfg.proxyPort ?? '8080';
    _proxyUserCtrl.text = cfg.proxyUsername ?? '';
    _proxyPassCtrl.text = cfg.proxyPassword ?? '';
  }

  @override
  void dispose() {
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    _proxyPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.providerDetailPageNetworkTab),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _switchRow(
            title: l10n.providerDetailPageEnableProxyTitle,
            value: _proxyEnabled,
            onChanged: (v) {
              setState(() => _proxyEnabled = v);
              _saveNetwork();
            },
          ),
          if (_proxyEnabled) ...[
            const SizedBox(height: 12),
            _inputRow(
              context,
              label: l10n.providerDetailPageHostLabel,
              controller: _proxyHostCtrl,
              hint: '127.0.0.1',
              onChanged: (_) => _saveNetwork(),
            ),
            const SizedBox(height: 12),
            _inputRow(
              context,
              label: l10n.providerDetailPagePortLabel,
              controller: _proxyPortCtrl,
              hint: '8080',
              onChanged: (_) => _saveNetwork(),
            ),
            const SizedBox(height: 12),
            _inputRow(
              context,
              label: l10n.providerDetailPageUsernameOptionalLabel,
              controller: _proxyUserCtrl,
              onChanged: (_) => _saveNetwork(),
            ),
            const SizedBox(height: 12),
            _inputRow(
              context,
              label: l10n.providerDetailPagePasswordOptionalLabel,
              controller: _proxyPassCtrl,
              obscure: true,
              onChanged: (_) => _saveNetwork(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _inputRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.transparent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveNetwork() async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(
      widget.providerKey,
      defaultName: widget.providerDisplayName,
    );
    final cfg = old.copyWith(
      proxyEnabled: _proxyEnabled,
      proxyHost: _proxyHostCtrl.text.trim(),
      proxyPort: _proxyPortCtrl.text.trim(),
      proxyUsername: _proxyUserCtrl.text.trim(),
      proxyPassword: _proxyPassCtrl.text.trim(),
    );
    await settings.setProviderConfig(widget.providerKey, cfg);
    // Silent auto-save (no snackbar) to match immediate-save UX
    if (!mounted) return;
  }
}
