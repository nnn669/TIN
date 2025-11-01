import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../icons/lucide_adapter.dart' as lucide;
import '../l10n/app_localizations.dart';
import '../utils/brand_assets.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/assistant_provider.dart';
import '../core/services/api/chat_api_service.dart';
import '../shared/widgets/snackbar.dart';
import '../features/model/widgets/model_select_sheet.dart' show showModelSelector, ModelSelection;
import '../features/settings/widgets/language_select_sheet.dart' show LanguageOption, supportedLanguages;

class DesktopTranslatePage extends StatefulWidget {
  const DesktopTranslatePage({super.key});

  @override
  State<DesktopTranslatePage> createState() => _DesktopTranslatePageState();
}

class _DesktopTranslatePageState extends State<DesktopTranslatePage> {
  final TextEditingController _source = TextEditingController();
  final TextEditingController _output = TextEditingController();

  LanguageOption? _targetLang;
  String? _modelProviderKey;
  String? _modelId;

  StreamSubscription? _subscription;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    // Defer initializing model defaults until first frame to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaults());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _source.dispose();
    _output.dispose();
    super.dispose();
  }

  void _initDefaults() {
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    // Default language: if app locale is Chinese, default to English; else Simplified Chinese
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    setState(() {
      if (locale.startsWith('zh')) {
        _targetLang = supportedLanguages.firstWhere((e) => e.code == 'zh-CN', orElse: () => supportedLanguages.first);
      } else {
        _targetLang = supportedLanguages.firstWhere((e) => e.code == 'en', orElse: () => supportedLanguages.first);
      }
    });

    // Default model: translate model -> assistant's chat model -> global default
    final providerKey = settings.translateModelProvider ?? assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = settings.translateModelId ?? assistant?.chatModelId ?? settings.currentModelId;
    setState(() {
      _modelProviderKey = providerKey;
      _modelId = modelId;
    });
  }

  String _displayNameFor(AppLocalizations l10n, String code) {
    switch (code) {
      case 'zh-CN':
        return l10n.languageDisplaySimplifiedChinese;
      case 'en':
        return l10n.languageDisplayEnglish;
      case 'zh-TW':
        return l10n.languageDisplayTraditionalChinese;
      case 'ja':
        return l10n.languageDisplayJapanese;
      case 'ko':
        return l10n.languageDisplayKorean;
      case 'fr':
        return l10n.languageDisplayFrench;
      case 'de':
        return l10n.languageDisplayGerman;
      case 'it':
        return l10n.languageDisplayItalian;
      case 'es':
        return l10n.languageDisplaySpanish;
      default:
        return code;
    }
  }

  Future<void> _pickModel() async {
    if (_translating) return; // avoid switching mid-stream
    final sel = await showModelSelector(context);
    if (sel != null) {
      setState(() {
        _modelProviderKey = sel.providerKey;
        _modelId = sel.modelId;
      });
    }
  }

  Future<void> _startTranslate() async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();

    final text = _source.text.trim();
    if (text.isEmpty) return;

    final providerKey = _modelProviderKey;
    final modelId = _modelId;
    if (providerKey == null || modelId == null) {
      showAppSnackBar(context, message: l10n.homePagePleaseSetupTranslateModel, type: NotificationType.warning);
      return;
    }

    final cfg = settings.getProviderConfig(providerKey);

    final lang = _targetLang ?? supportedLanguages.first;
    final prompt = settings.translatePrompt
        .replaceAll('{source_text}', text)
        .replaceAll('{target_lang}', _displayNameFor(l10n, lang.code));

    setState(() {
      _translating = true;
      _output.text = '';
    });

    try {
      final stream = ChatApiService.sendMessageStream(
        config: cfg,
        modelId: modelId,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );

      _subscription = stream.listen(
        (chunk) {
          // live update
          _output.text += chunk.content;
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _translating = false);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _translating = false);
          showAppSnackBar(context, message: l10n.homePageTranslateFailed(e.toString()), type: NotificationType.error);
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() => _translating = false);
      showAppSnackBar(context, message: l10n.homePageTranslateFailed(e.toString()), type: NotificationType.error);
    }
  }

  Future<void> _stopTranslate() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    if (mounted) setState(() => _translating = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final topBar = SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: Text(
            l10n.desktopNavTranslateTooltip, // 显示“翻译”
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );

    final brandAsset = (_modelId != null) ? BrandAssets.assetForName(_modelId!) : null;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topBar,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            // Language dropdown
                            _LanguageDropdown(
                              value: _targetLang,
                              onChanged: _translating ? null : (v) => setState(() => _targetLang = v),
                            ),
                            const SizedBox(width: 8),
                            // Translate / Stop button with animation
                            _TranslateButton(
                              translating: _translating,
                              onTranslate: _startTranslate,
                              onStop: _stopTranslate,
                            ),
                            const Spacer(),
                            // Model picker button (brand icon)
                            _ModelPickerButton(
                              asset: brandAsset,
                              modelId: _modelId,
                              onTap: _pickModel,
                              enabled: !_translating,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Two large rounded rectangles: input (left) and output (right)
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _PaneContainer(
                                overlay: _PaneActionButton(
                                  icon: lucide.Lucide.Eraser,
                                  label: '清空',
                                  onTap: () {
                                    _source.clear();
                                    _output.clear();
                                  },
                                ),
                                child: TextField(
                                  controller: _source,
                                  keyboardType: TextInputType.multiline,
                                  maxLines: null,
                                  expands: true,
                                  decoration: const InputDecoration(
                                    hintText: '输入要翻译的内容…',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.all(14),
                                  ),
                                  style: const TextStyle(fontSize: 14.5, height: 1.4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _PaneContainer(
                                overlay: _PaneActionButton(
                                  icon: lucide.Lucide.Copy,
                                  label: '复制',
                                  onTap: () async {
                                    await Clipboard.setData(ClipboardData(text: _output.text));
                                    if (!mounted) return;
                                    showAppSnackBar(
                                      context,
                                      message: AppLocalizations.of(context)!.chatMessageWidgetCopiedToClipboard,
                                      type: NotificationType.success,
                                    );
                                  },
                                ),
                                child: TextField(
                                  controller: _output,
                                  readOnly: true,
                                  keyboardType: TextInputType.multiline,
                                  maxLines: null,
                                  expands: true,
                                  decoration: const InputDecoration(
                                    hintText: '翻译结果会显示在这里…',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.all(14),
                                  ),
                                  style: const TextStyle(fontSize: 14.5, height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneContainer extends StatelessWidget {
  const _PaneContainer({required this.child, this.overlay});
  final Widget child;
  final Widget? overlay;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        if (overlay != null)
          Positioned(
            top: 8,
            right: 8,
            child: overlay!,
          ),
      ],
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({required this.value, required this.onChanged});
  final LanguageOption? value;
  final ValueChanged<LanguageOption?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LanguageOption>(
          value: value ?? supportedLanguages.first,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(12),
          items: [
            for (final lang in supportedLanguages)
              DropdownMenuItem<LanguageOption>(
                value: lang,
                child: Row(
                  children: [
                    Text(lang.flag, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(_displayNameFor(l10n, lang.code), style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _displayNameFor(AppLocalizations l10n, String code) {
    switch (code) {
      case 'zh-CN':
        return l10n.languageDisplaySimplifiedChinese;
      case 'en':
        return l10n.languageDisplayEnglish;
      case 'zh-TW':
        return l10n.languageDisplayTraditionalChinese;
      case 'ja':
        return l10n.languageDisplayJapanese;
      case 'ko':
        return l10n.languageDisplayKorean;
      case 'fr':
        return l10n.languageDisplayFrench;
      case 'de':
        return l10n.languageDisplayGerman;
      case 'it':
        return l10n.languageDisplayItalian;
      case 'es':
        return l10n.languageDisplaySpanish;
      default:
        return code;
    }
  }
}

class _TranslateButton extends StatefulWidget {
  const _TranslateButton({required this.translating, required this.onTranslate, required this.onStop});
  final bool translating;
  final VoidCallback onTranslate;
  final VoidCallback onStop;

  @override
  State<_TranslateButton> createState() => _TranslateButtonState();
}

class _TranslateButtonState extends State<_TranslateButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final fg = isDark ? Colors.black : Colors.white;
    final base = cs.primary;
    final bg = _hover ? base.withOpacity(0.92) : base;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.translating ? widget.onStop : widget.onTranslate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: widget.translating
                ? Row(
                    key: const ValueKey('stop'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset('assets/icons/stop.svg', width: 16, height: 16, colorFilter: ColorFilter.mode(fg, BlendMode.srcIn)),
                      const SizedBox(width: 6),
                      Text('终止', style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ],
                  )
                : Row(
                    key: const ValueKey('translate'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(lucide.Lucide.Languages, size: 16, color: fg),
                      const SizedBox(width: 6),
                      Text('翻译', style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ModelPickerButton extends StatelessWidget {
  const _ModelPickerButton({required this.asset, required this.modelId, required this.onTap, required this.enabled});
  final String? asset;
  final String? modelId;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = enabled ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)) : Colors.transparent;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (asset != null)
                () {
                  if (asset!.toLowerCase().endsWith('.svg')) {
                    return SvgPicture.asset(asset!, width: 18, height: 18);
                  }
                  return Image.asset(asset!, width: 18, height: 18);
                }()
              else
                Icon(lucide.Lucide.Bot, size: 18, color: cs.onSurface.withOpacity(0.9)),
              if (modelId != null) ...[
                const SizedBox(width: 8),
                Text(
                  modelId!,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: cs.onSurface.withOpacity(0.85)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneActionButton extends StatefulWidget {
  const _PaneActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PaneActionButton> createState() => _PaneActionButtonState();
}

class _PaneActionButtonState extends State<_PaneActionButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06))
        : Colors.transparent;
    final fg = cs.onSurface.withOpacity(0.9);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        tooltip: widget.label,
        button: true,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
