import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../shared/widgets/ios_switch.dart';

class NetworkProxyPage extends StatefulWidget {
  const NetworkProxyPage({super.key});

  @override
  State<NetworkProxyPage> createState() => _NetworkProxyPageState();
}

class _NetworkProxyPageState extends State<NetworkProxyPage> {
  late final TextEditingController _hostCtl;
  late final TextEditingController _portCtl;
  late final TextEditingController _userCtl;
  late final TextEditingController _passCtl;
  final FocusNode _hostFn = FocusNode();
  final FocusNode _portFn = FocusNode();
  final FocusNode _userFn = FocusNode();
  final FocusNode _passFn = FocusNode();

  String _type = 'http';
  bool _enabled = false;

  final TextEditingController _testUrlCtl = TextEditingController(text: 'https://www.google.com');
  bool _testing = false;
  String? _testErr;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _enabled = sp.globalProxyEnabled;
    _type = sp.globalProxyType;
    _hostCtl = TextEditingController(text: sp.globalProxyHost);
    _portCtl = TextEditingController(text: sp.globalProxyPort);
    _userCtl = TextEditingController(text: sp.globalProxyUsername);
    _passCtl = TextEditingController(text: sp.globalProxyPassword);
    _hostFn.addListener(() { if (!_hostFn.hasFocus) sp.setGlobalProxyHost(_hostCtl.text); });
    _portFn.addListener(() { if (!_portFn.hasFocus) sp.setGlobalProxyPort(_portCtl.text); });
    _userFn.addListener(() { if (!_userFn.hasFocus) sp.setGlobalProxyUsername(_userCtl.text); });
    _passFn.addListener(() { if (!_passFn.hasFocus) sp.setGlobalProxyPassword(_passCtl.text); });
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    _hostFn.dispose();
    _portFn.dispose();
    _userFn.dispose();
    _passFn.dispose();
    _testUrlCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.settingsPageNetworkProxy),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _sectionCard(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.networkProxyEnableLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  IosSwitch(
                    value: _enabled,
                    onChanged: (v) async {
                      setState(() => _enabled = v);
                      await context.read<SettingsProvider>().setGlobalProxyEnabled(v);
                    },
                  ),
                ],
              ),
            ),
            _divider(context),
            _labeledField(
              context,
              label: l10n.networkProxyType,
              child: DropdownButtonFormField<String>(
                value: _type,
                decoration: _deskInputDecoration(context),
                items: [
                  DropdownMenuItem(value: 'http', child: Text(l10n.networkProxyTypeHttp)),
                  DropdownMenuItem(value: 'https', child: Text(l10n.networkProxyTypeHttps)),
                  DropdownMenuItem(value: 'socks5', child: Text(l10n.networkProxyTypeSocks5)),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _type = v);
                  await context.read<SettingsProvider>().setGlobalProxyType(v);
                },
              ),
            ),
            _divider(context),
            _labeledField(
              context,
              label: l10n.networkProxyServerHost,
              child: TextField(
                controller: _hostCtl,
                focusNode: _hostFn,
                decoration: _deskInputDecoration(context).copyWith(hintText: '127.0.0.1'),
              ),
            ),
            _divider(context),
            _labeledField(
              context,
              label: l10n.networkProxyPort,
              child: TextField(
                controller: _portCtl,
                focusNode: _portFn,
                keyboardType: TextInputType.number,
                decoration: _deskInputDecoration(context).copyWith(hintText: '8080'),
              ),
            ),
            _divider(context),
            _labeledField(
              context,
              label: l10n.networkProxyUsername,
              child: TextField(
                controller: _userCtl,
                focusNode: _userFn,
                decoration: _deskInputDecoration(context).copyWith(hintText: l10n.networkProxyOptionalHint),
              ),
            ),
            _divider(context),
            _labeledField(
              context,
              label: l10n.networkProxyPassword,
              child: TextField(
                controller: _passCtl,
                focusNode: _passFn,
                obscureText: true,
                decoration: _deskInputDecoration(context).copyWith(hintText: l10n.networkProxyOptionalHint),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(l10n.networkProxyPriorityNote, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ),
          ]),

          const SizedBox(height: 12),
          _sectionCard(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(l10n.networkProxyTestHeader, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _testUrlCtl,
                      decoration: _deskInputDecoration(context).copyWith(hintText: l10n.networkProxyTestUrlHint),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _DeskIosButton(
                    label: _testing ? l10n.networkProxyTesting : l10n.networkProxyTestButton,
                    filled: false,
                    dense: true,
                    onTap: _testing ? (){} : _onTest,
                  ),
                ],
              ),
            ),
            if (_ok == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(l10n.networkProxyTestSuccess, style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.w600)),
              ),
            if (_ok == false)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(l10n.networkProxyTestFailed(_testErr ?? ''), style: TextStyle(color: cs.error)),
              ),
          ]),
        ],
      ),
    );
  }

  Future<void> _onTest() async {
    final l10n = AppLocalizations.of(context)!;
    final url = _testUrlCtl.text.trim();
    if (url.isEmpty) {
      setState(() { _ok = false; _testErr = l10n.networkProxyNoUrl; });
      return;
    }
    setState(() { _testing = true; _ok = null; _testErr = null; });
    try {
      if (_type == 'socks5') {
        throw UnsupportedError('SOCKS5 not supported');
      }
      final host = _hostCtl.text.trim();
      final port = int.tryParse(_portCtl.text.trim()) ?? 8080;
      final user = _userCtl.text.trim();
      final pass = _passCtl.text;
      final io = HttpClient();
      io.findProxy = (_) => 'PROXY $host:$port';
      if (user.isNotEmpty) {
        io.addProxyCredentials(host, port, '', HttpClientBasicCredentials(user, pass));
      }
      final client = IOClient(io);
      final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      client.close();
      setState(() { _testing = false; _ok = (res.statusCode >= 200 && res.statusCode < 400); _testErr = _ok == true ? null : 'HTTP ${res.statusCode}'; });
    } catch (e) {
      setState(() { _testing = false; _ok = false; _testErr = e.toString(); });
    }
  }
}

// Local minimal copies of iOS-style bits to match app style
class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({required this.icon, required this.color, required this.size, required this.onTap});
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 80),
        child: Icon(widget.icon, size: widget.size, color: widget.color),
      ),
    );
  }
}

Widget _sectionCard({required List<Widget> children}) {
  return Builder(builder: (context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.08 : 0.06), width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    );
  });
}

Widget _divider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(height: 6, thickness: 0.6, indent: 12, endIndent: 12, color: cs.outlineVariant.withOpacity(0.18));
}

Widget _labeledField(BuildContext context, {required String label, required Widget child}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.7))),
        ),
        child,
      ],
    ),
  );
}

// Reuse desktop input styles to keep consistent look
InputDecoration _deskInputDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
    hintStyle: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.5)),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary.withOpacity(0.35), width: 0.8),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}

class _DeskIosButton extends StatefulWidget {
  const _DeskIosButton({required this.label, required this.filled, required this.dense, required this.onTap});
  final String label; final bool filled; final bool dense; final VoidCallback onTap;
  @override State<_DeskIosButton> createState() => _DeskIosButtonState();
}

class _DeskIosButtonState extends State<_DeskIosButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = widget.filled ? Colors.white : cs.onSurface.withOpacity(0.9);
    final bg = widget.filled
        ? cs.primary
        : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05));
    final borderColor = widget.filled ? Colors.transparent : cs.outlineVariant.withOpacity(isDark ? 0.22 : 0.18);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: widget.dense ? 8 : 12, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
          child: Text(widget.label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: widget.dense ? 13 : 14)),
        ),
      ),
    );
  }
}
