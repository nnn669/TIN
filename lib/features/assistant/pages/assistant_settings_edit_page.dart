import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/services/chat/prompt_transformer.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:uuid/uuid.dart';

import '../../chat/widgets/chat_message_widget.dart';
import '../../home/widgets/assistant_avatar.dart';
import '../../chat/widgets/reasoning_budget_sheet.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../../core/models/app_control_policy.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/preset_message.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/models/skill.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/skill_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../home/services/local_tools_service.dart';
import '../../skills/pages/skills_page.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/emoji_picker_dialog.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../utils/assistant_edit_tab_layout.dart';
import 'assistant_regex_tab.dart';

part 'assistant_settings_edit_basic_tab.dart';
part 'assistant_settings_edit_prompt_tab.dart';
part 'assistant_settings_edit_memory_tab.dart';
part 'assistant_settings_edit_local_tools_tab.dart';
part 'assistant_settings_edit_mcp_tab.dart';
part 'assistant_settings_edit_quick_phrase_tab.dart';
part 'assistant_settings_edit_skills_tab.dart';
part 'assistant_settings_edit_custom_request_tab.dart';

const int _contextMessageMin = Assistant.minContextMessageSize;
const int _contextMessageMax = Assistant.maxContextMessageSize;

class _AssistantEditTabSpec {
  const _AssistantEditTabSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.child,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget child;
}

List<_AssistantEditTabSpec> _assistantEditTabSpecs(
  BuildContext context,
  String assistantId,
) {
  final l10n = AppLocalizations.of(context)!;
  return [
    _AssistantEditTabSpec(
      id: assistantEditTabBasic,
      label: l10n.assistantEditPageBasicTab,
      icon: Lucide.Settings2,
      child: _BasicSettingsTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabPrompts,
      label: l10n.assistantEditPagePromptsTab,
      icon: Lucide.FileText,
      child: _PromptTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabMemory,
      label: l10n.assistantEditPageMemoryTab,
      icon: Lucide.Brain,
      child: _MemoryTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabLocalTools,
      label: l10n.assistantEditPageLocalToolsTab,
      icon: Lucide.Wrench,
      child: _LocalToolsTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabMcp,
      label: l10n.assistantEditPageMcpTab,
      icon: Lucide.Terminal,
      child: _McpTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabQuickPhrase,
      label: l10n.assistantEditPageQuickPhraseTab,
      icon: Lucide.Zap,
      child: _QuickPhraseTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabSkills,
      label: l10n.assistantEditPageSkillsTab,
      icon: Lucide.Sparkles,
      child: _SkillsTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabCustom,
      label: l10n.assistantEditPageCustomTab,
      icon: Lucide.EthernetPort,
      child: _CustomRequestTab(assistantId: assistantId),
    ),
    _AssistantEditTabSpec(
      id: assistantEditTabRegex,
      label: l10n.assistantEditPageRegexTab,
      icon: Lucide.CaseSensitive,
      child: AssistantRegexTab(assistantId: assistantId),
    ),
  ];
}

List<_AssistantEditTabSpec> _orderedAssistantEditTabs(
  List<_AssistantEditTabSpec> tabs,
  List<String> order,
) {
  final byId = {for (final tab in tabs) tab.id: tab};
  return orderAssistantEditTabIds(
    savedOrder: order,
  ).map((id) => byId[id]).nonNulls.toList();
}

List<_AssistantEditTabSpec> _visibleAssistantEditTabs(
  List<_AssistantEditTabSpec> tabs,
  SettingsProvider settings,
) {
  final ordered = _orderedAssistantEditTabs(
    tabs,
    settings.mobileAssistantEditTabOrder,
  );
  final byId = {for (final tab in ordered) tab.id: tab};
  return visibleAssistantEditTabIds(
    savedOrder: settings.mobileAssistantEditTabOrder,
    hiddenIds: settings.hiddenMobileAssistantEditTabs,
  ).map((id) => byId[id]).nonNulls.toList();
}

int _clampContextMessages(num value) =>
    value.clamp(_contextMessageMin, _contextMessageMax).toInt();

Future<int?> _showContextMessageInputDialog(
  BuildContext context, {
  required int initialValue,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(
    text: _clampContextMessages(initialValue).toString(),
  );

  int? parseValue() => int.tryParse(controller.text);

  try {
    return await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final parsed = parseValue();
            void submit() {
              if (parsed == null) return;
              Navigator.of(ctx).pop(_clampContextMessages(parsed));
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(l10n.assistantEditContextMessagesTitle),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.assistantEditContextMessagesTitle} ($_contextMessageMin-$_contextMessageMax)',
                        helperText: '$_contextMessageMin-$_contextMessageMax',
                      ),
                      onChanged: (_) => setLocal(() {}),
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.assistantEditContextMessagesDescription} ($_contextMessageMin-$_contextMessageMax)',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.assistantEditEmojiDialogCancel),
                ),
                TextButton(
                  onPressed: parsed == null ? null : submit,
                  child: Text(l10n.assistantEditEmojiDialogSave),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}

class AssistantSettingsEditPage extends StatefulWidget {
  const AssistantSettingsEditPage({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantSettingsEditPage> createState() =>
      _AssistantSettingsEditPageState();
}

class _AssistantSettingsEditPageState extends State<AssistantSettingsEditPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    // Close IME when switching tabs and refresh state.
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() {});
  }

  void _syncTabController(int length) {
    if (_tabController.length == length) return;
    final nextIndex = math.min(_tabController.index, length - 1);
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _tabController = TabController(
      length: length,
      vsync: this,
      initialIndex: nextIndex,
    );
    _tabController.addListener(_handleTabChanged);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AssistantProvider>();
    final settings = context.watch<SettingsProvider>();
    final assistant = provider.getById(widget.assistantId);

    if (assistant == null) {
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
          title: Text(l10n.assistantEditPageTitle),
          actions: const [SizedBox(width: 12)],
        ),
        body: Center(child: Text(l10n.assistantEditPageNotFound)),
      );
    }

    final allTabs = _assistantEditTabSpecs(context, assistant.id);
    final visibleTabs = _visibleAssistantEditTabs(allTabs, settings);
    final useOutline = settings.mobileAssistantDetailOutlineEnabled;
    if (!useOutline) {
      _syncTabController(visibleTabs.length);
    }

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
        title: Text(
          assistant.name.isNotEmpty
              ? assistant.name
              : l10n.assistantEditPageTitle,
        ),
        actions: [
          Tooltip(
            message: l10n.assistantEditTabLayoutTooltip,
            child: IosIconButton(
              icon: Lucide.Settings2,
              color: cs.onSurface,
              size: 21,
              minSize: 44,
              semanticLabel: l10n.assistantEditTabLayoutTooltip,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _AssistantTabLayoutPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: useOutline
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegTabBar(
                          controller: _tabController,
                          tabs: visibleTabs.map((tab) => tab.label).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: useOutline
            ? _AssistantDetailOutlinePage(
                assistant: assistant,
                tabs: visibleTabs,
              )
            : TabBarView(
                controller: _tabController,
                children: visibleTabs.map((tab) => tab.child).toList(),
              ),
      ),
    );
  }
}

class _AssistantDetailOutlinePage extends StatelessWidget {
  const _AssistantDetailOutlinePage({
    required this.assistant,
    required this.tabs,
  });

  final Assistant assistant;
  final List<_AssistantEditTabSpec> tabs;

  @override
  Widget build(BuildContext context) {
    final prompt = assistant.systemPrompt.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        _AssistantOutlineHeader(assistant: assistant, prompt: prompt),
        const SizedBox(height: 18),
        _iosSectionCard(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              _AssistantOutlineItem(tab: tabs[i], assistantId: assistant.id),
              if (i != tabs.length - 1) _iosDivider(context),
            ],
          ],
        ),
      ],
    );
  }
}

class _AssistantOutlineHeader extends StatelessWidget {
  const _AssistantOutlineHeader({
    required this.assistant,
    required this.prompt,
  });

  final Assistant assistant;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final name = assistant.name.trim().isNotEmpty
        ? assistant.name.trim()
        : l10n.assistantEditPageTitle;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.1 : 0.08),
          width: 0.7,
        ),
      ),
      child: Column(
        children: [
          AssistantAvatar(assistant: assistant, fallbackName: name, size: 82),
          const SizedBox(height: 14),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              height: 1.18,
              fontWeight: AppFontWeights.emphasis,
              color: cs.onSurface.withValues(alpha: 0.94),
            ),
          ),
          if (prompt.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantOutlineItem extends StatelessWidget {
  const _AssistantOutlineItem({required this.tab, required this.assistantId});

  final _AssistantEditTabSpec tab;
  final String assistantId;

  @override
  Widget build(BuildContext context) {
    return _iosNavRow(
      context,
      icon: tab.icon,
      label: tab.label,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _AssistantDetailSectionPage(
              assistantId: assistantId,
              tabId: tab.id,
            ),
          ),
        );
      },
    );
  }
}

class _AssistantDetailSectionPage extends StatelessWidget {
  const _AssistantDetailSectionPage({
    required this.assistantId,
    required this.tabId,
  });

  final String assistantId;
  final String tabId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AssistantProvider>();
    final assistant = provider.getById(assistantId);

    if (assistant == null) {
      return Scaffold(
        appBar: AppBar(
          leading: Tooltip(
            message: l10n.settingsPageBackButton,
            child: IosIconButton(
              icon: Lucide.ArrowLeft,
              color: cs.onSurface,
              size: 22,
              minSize: 44,
              semanticLabel: l10n.settingsPageBackButton,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          title: Text(l10n.assistantEditPageTitle),
          actions: const [SizedBox(width: 12)],
        ),
        body: Center(child: Text(l10n.assistantEditPageNotFound)),
      );
    }

    final tabs = _assistantEditTabSpecs(context, assistant.id);
    final tab = tabs.firstWhere(
      (candidate) => candidate.id == tabId,
      orElse: () => tabs.first,
    );

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(tab.label),
        actions: const [SizedBox(width: 12)],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: tab.child,
      ),
    );
  }
}

class _AssistantTabLayoutPage extends StatelessWidget {
  const _AssistantTabLayoutPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final tabs = _orderedAssistantEditTabs(
      _assistantEditTabSpecs(context, ''),
      settings.mobileAssistantEditTabOrder,
    );
    final hidden = settings.hiddenMobileAssistantEditTabs;
    final visibleCount = tabs.where((tab) => !hidden.contains(tab.id)).length;

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.assistantEditTabLayoutTitle),
        actions: [
          Tooltip(
            message: l10n.assistantEditTabLayoutResetTooltip,
            child: IosIconButton(
              icon: Lucide.RotateCcw,
              color: cs.onSurface,
              size: 20,
              minSize: 44,
              semanticLabel: l10n.assistantEditTabLayoutResetTooltip,
              onTap: () async {
                final settings = context.read<SettingsProvider>();
                await settings.setMobileAssistantEditTabOrder(const []);
                await settings.setHiddenMobileAssistantEditTabs(const {});
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AssistantOutlineModeSwitch(settings: settings),
                const SizedBox(height: 12),
                Text(
                  l10n.assistantEditTabLayoutSubtitle,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.68),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
              itemCount: tabs.length,
              onReorderItem: (oldIndex, newIndex) async {
                final next = tabs.map((tab) => tab.id).toList();
                final moved = next.removeAt(oldIndex);
                next.insert(newIndex, moved);
                await context
                    .read<SettingsProvider>()
                    .setMobileAssistantEditTabOrder(next);
              },
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final t = Curves.easeOutCubic.transform(animation.value);
                    return Transform.scale(
                      scale: 0.98 + 0.02 * t,
                      child: Material(
                        color: Colors.transparent,
                        elevation: 0,
                        child: child,
                      ),
                    );
                  },
                );
              },
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final visible = !hidden.contains(tab.id);
                return Padding(
                  key: ValueKey('assistant-tab-layout-${tab.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AssistantTabLayoutTile(
                    tab: tab,
                    index: index,
                    visible: visible,
                    onVisibleChanged: (nextVisible) async {
                      if (!nextVisible && visibleCount <= 1) {
                        showAppSnackBar(
                          context,
                          message: l10n.assistantEditTabLayoutAtLeastOneVisible,
                          type: NotificationType.warning,
                        );
                        return;
                      }
                      final nextHidden = {...hidden};
                      if (nextVisible) {
                        nextHidden.remove(tab.id);
                      } else {
                        nextHidden.add(tab.id);
                      }
                      await context
                          .read<SettingsProvider>()
                          .setHiddenMobileAssistantEditTabs(nextHidden);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantOutlineModeSwitch extends StatelessWidget {
  const _AssistantOutlineModeSwitch({required this.settings});

  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _iosSectionCard(
      children: [
        _iosSwitchRow(
          context,
          icon: Lucide.ListTree,
          label: l10n.assistantEditOutlineModeTitle,
          value: settings.mobileAssistantDetailOutlineEnabled,
          onChanged: (enabled) => context
              .read<SettingsProvider>()
              .setMobileAssistantDetailOutlineEnabled(enabled),
        ),
        _iosDivider(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(60, 4, 14, 8),
          child: Text(
            l10n.assistantEditOutlineModeSubtitle,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.56),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantTabLayoutTile extends StatelessWidget {
  const _AssistantTabLayoutTile({
    required this.tab,
    required this.index,
    required this.visible,
    required this.onVisibleChanged,
  });

  final _AssistantEditTabSpec tab;
  final int index;
  final bool visible;
  final ValueChanged<bool> onVisibleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96);
    final fg = visible
        ? cs.onSurface.withValues(alpha: 0.9)
        : cs.onSurface.withValues(alpha: 0.42);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.08),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            SizedBox(width: 34, child: Icon(tab.icon, size: 20, color: fg)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
            ),
            IosSwitch(
              value: visible,
              semanticLabel: tab.label,
              onChanged: onVisibleChanged,
            ),
            Tooltip(
              message: l10n.assistantEditTabLayoutDragHandle(tab.label),
              child: ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Lucide.GripVertical,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.42),
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

class _SegTabBar extends StatelessWidget {
  const _SegTabBar({required this.controller, required this.tabs});
  final TabController controller;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    const double outerHeight = 44;
    const double innerPadding = 4;
    const double gap = 6;
    const double minSegWidth = 88;
    final double pillRadius = 18;
    final double innerRadius = ((pillRadius - innerPadding).clamp(
      0.0,
      pillRadius,
    )).toDouble();

    return AnimatedBuilder(
      animation: controller.animation ?? controller,
      builder: (context, _) {
        final rawIndex =
            controller.animation?.value ?? controller.index.toDouble();
        final selectedIndex = visualAssistantEditTabIndex(
          animationValue: rawIndex,
          tabCount: tabs.length,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final double availWidth = constraints.maxWidth;
            final double innerAvailWidth = availWidth - innerPadding * 2;
            final double segWidth = math.max(
              minSegWidth,
              (innerAvailWidth - gap * (tabs.length - 1)) / tabs.length,
            );
            final double rowWidth =
                segWidth * tabs.length + gap * (tabs.length - 1);

            final Color shellBg = isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white;

            List<Widget> children = [];
            for (int index = 0; index < tabs.length; index++) {
              final bool selected = selectedIndex == index;
              children.add(
                SizedBox(
                  width: segWidth,
                  height: double.infinity,
                  child: _TactileRow(
                    onTap: () => controller.animateTo(index),
                    builder: (pressed) {
                      final Color baseBg = selected
                          ? cs.primary.withValues(alpha: 0.14)
                          : Colors.transparent;
                      final Color bg = baseBg;
                      final Color baseTextColor = selected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.82);
                      final Color targetTextColor = pressed
                          ? Color.lerp(baseTextColor, Colors.white, 0.22) ??
                                baseTextColor
                          : baseTextColor;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(
                            innerRadius,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TweenAnimationBuilder<Color?>(
                            tween: ColorTween(end: targetTextColor),
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            builder: (context, color, _) {
                              return Text(
                                tabs[index],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: color ?? baseTextColor,
                                  fontWeight: AppFontWeights.medium,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
              if (index != tabs.length - 1) {
                children.add(const SizedBox(width: gap));
              }
            }

            return Container(
              height: outerHeight,
              decoration: BoxDecoration(
                color: shellBg,
                borderRadius: BorderRadius.circular(pillRadius),
              ),
              clipBehavior: Clip.hardEdge,
              child: Padding(
                padding: const EdgeInsets.all(innerPadding),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: innerAvailWidth),
                    child: SizedBox(
                      width: rowWidth,
                      child: Row(children: children),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.label,
    required this.controller,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: AppFontWeights.semibold),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandAvatarLike extends StatelessWidget {
  const _BrandAvatarLike({required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint = (isDark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            asset,
            width: size * 0.62,
            height: size * 0.62,
            colorFilter: tint,
          ),
        );
      } else {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Image.asset(
            asset,
            width: size * 0.62,
            height: size * 0.62,
            fit: BoxFit.contain,
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          FocusManager.instance.primaryFocus?.unfocus();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed
        ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.haptics = true,
    this.pressedScale = 1.0,
    this.releaseDelayMs = 60,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final bool haptics;
  final double pressedScale;
  final int releaseDelayMs;

  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.builder(_pressed);
    if (widget.pressedScale != 1.0) {
      child = AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null
          ? null
          : (_) async {
              if (widget.releaseDelayMs > 0) {
                await Future.delayed(
                  Duration(milliseconds: widget.releaseDelayMs),
                );
              }
              if (mounted) _setPressed(false);
            },
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics &&
                  context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              FocusManager.instance.primaryFocus?.unfocus();
              widget.onTap!.call();
            },
      child: child,
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  String? detailText,
  Widget? accessory,
  VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  return _TactileRow(
    onTap: onTap,
    haptics: true,
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (accessory != null) accessory,
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _iosSwitchRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  return _TactileRow(
    onTap: () => onChanged(!value),
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15, color: c)),
                ),
                IosSwitch(value: value, onChanged: onChanged),
              ],
            ),
          );
        },
      );
    },
  );
}

class _IosButton extends StatefulWidget {
  const _IosButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.neutral = true,
    this.dense = false,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool filled;
  final bool neutral;
  final bool dense;

  @override
  State<_IosButton> createState() => _IosButtonState();
}

class _IosButtonState extends State<_IosButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isMaterialIcon =
        widget.icon != null &&
        (widget.icon == Icons.image ||
            widget.icon.runtimeType.toString().contains('MaterialIcons'));

    final iconColor = widget.filled
        ? cs.onPrimary
        : (widget.neutral ? cs.onSurface.withValues(alpha: 0.75) : cs.primary);

    final textColor = widget.filled
        ? cs.onPrimary
        : (widget.neutral ? cs.onSurface.withValues(alpha: 0.9) : cs.primary);

    final borderColor = widget.neutral
        ? cs.outlineVariant.withValues(alpha: 0.35)
        : cs.primary.withValues(alpha: 0.45);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            color: widget.filled
                ? cs.primary
                : (isDark ? Colors.white10 : const Color(0xFFF2F3F5)),
            borderRadius: BorderRadius.circular(12),
            border: widget.filled ? null : Border.all(color: borderColor),
          ),
          padding: EdgeInsets.symmetric(
            vertical: widget.dense ? 8 : 12,
            horizontal: widget.dense ? 12 : 16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Padding(
                  padding: EdgeInsets.only(left: isMaterialIcon ? 2.0 : 0.0),
                  child: Icon(widget.icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: AppFontWeights.semibold,
                  fontSize: widget.dense ? 13 : 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
