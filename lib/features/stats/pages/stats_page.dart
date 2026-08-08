import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../home/widgets/assistant_avatar.dart';
import '../../home/widgets/model_icon.dart';
import '../models/stats_models.dart';
import '../services/stats_aggregation_service.dart';
import '../widgets/stats_heatmap.dart';
import '../widgets/stats_metric_grid.dart';
import '../widgets/stats_rank_section.dart';
import '../widgets/stats_section_card.dart';
import '../widgets/stats_usage_chart.dart';
import '../../../theme/app_font_weights.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.snapshotOverride, this.showAppBar = true});

  final StatsSnapshot? snapshotOverride;
  final bool showAppBar;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late StatsDateRange _range;

  @override
  void initState() {
    super.initState();
    _range =
        widget.snapshotOverride?.range ??
        StatsDateRange.allTime(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = widget.snapshotOverride ?? _buildSnapshot(context);
    final assistantById = widget.snapshotOverride == null
        ? {
            for (final assistant
                in context.watch<AssistantProvider>().assistants)
              assistant.id: assistant,
          }
        : <String, Assistant>{};
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _RangeSelector(
          selected: _range.preset,
          onChanged: _setPreset,
        ),
        const SizedBox(height: 12),
        StatsSectionCard(
          title: l10n.statsPageHeatmapTitle,
          child: StatsHeatmap(days: snapshot.heatmap),
        ),
        const SizedBox(height: 12),
        StatsSectionCard(
          title: l10n.statsPageSummaryTitle,
          child: StatsMetricGrid(summary: snapshot.summary),
        ),
        const SizedBox(height: 12),
        StatsSectionCard(
          title: l10n.statsPageUsageTrendTitle,
          child: StatsUsageChart(days: snapshot.trend),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final sections = [
              StatsRankSection(
                title: l10n.statsPageModelUsageTitle,
                leftHeader: l10n.statsPageModelColumn,
                rightHeader: l10n.statsPageMessagesColumn,
                items: snapshot.modelRank,
                leadingBuilder: (context, item) => CurrentModelIcon(
                  key: ValueKey('stats-model-icon-${item.id}'),
                  providerKey: item.providerId,
                  modelId: item.id,
                  size: 32,
                  withBackground: false,
                ),
              ),
              StatsRankSection(
                title: l10n.statsPageAssistantUsageTitle,
                leftHeader: l10n.statsPageAssistantColumn,
                rightHeader: l10n.statsPageTopicsColumn,
                items: snapshot.assistantRank,
                leadingBuilder: (context, item) => AssistantAvatar(
                  key: ValueKey('stats-assistant-avatar-${item.id}'),
                  assistant: assistantById[item.id],
                  fallbackName: item.label,
                  size: 20,
                ),
              ),
              StatsRankSection(
                title: l10n.statsPageTopicVolumeTitle,
                leftHeader: l10n.statsPageTopicColumn,
                rightHeader: l10n.statsPageMessagesColumn,
                items: snapshot.topicRank,
                icon: Lucide.MessageSquare,
              ),
            ];
            if (!wide) {
              return Column(
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    sections[i],
                    if (i != sections.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  Expanded(child: sections[i]),
                  if (i != sections.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          },
        ),
      ],
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            minSize: 44,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.statsPageTitle),
      ),
      body: body,
    );
  }

  StatsSnapshot _buildSnapshot(BuildContext context) {
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context)!;
    final chatService = context.watch<ChatService>();
    final settings = context.watch<SettingsProvider>();
    final assistantProvider = context.watch<AssistantProvider>();
    final conversations = chatService.getAllConversations();
    final messagesByConversation = {
      for (final conversation in conversations)
        conversation.id: chatService.getMessages(conversation.id),
    };
    final assistantNames = {
      for (final assistant in assistantProvider.assistants)
        assistant.id: assistant.name,
      '_default': l10n.statsPageUnknownAssistant,
    };
    final existingAssistantIds = {
      for (final assistant in assistantProvider.assistants) assistant.id,
      '_default',
    };
    final providerNames = {
      for (final entry in settings.providerConfigs.entries)
        entry.key: entry.value.name,
    };
    return StatsAggregationService.buildSnapshot(
      now: now,
      range: _range,
      conversations: conversations,
      messagesByConversation: messagesByConversation,
      launchCount: settings.appLaunchCount,
      assistantNames: assistantNames,
      existingAssistantIds: existingAssistantIds,
      providerNames: providerNames,
      unknownProviderLabel: l10n.statsPageUnknownProvider,
      unknownTopicLabel: l10n.statsPageUnknownTopic,
    );
  }

  void _setPreset(StatsDateRangePreset preset) {
    final now = DateTime.now();
    setState(() {
      _range = switch (preset) {
        StatsDateRangePreset.allTime => StatsDateRange.allTime(now),
        StatsDateRangePreset.last30Days => StatsDateRange.last30Days(now),
        StatsDateRangePreset.previousMonth => StatsDateRange.previousMonth(now),
        StatsDateRangePreset.previousQuarter => StatsDateRange.previousQuarter(
          now,
        ),
        StatsDateRangePreset.custom => _range,
      };
    });
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({
    required this.selected,
    required this.onChanged,
  });

  final StatsDateRangePreset selected;
  final ValueChanged<StatsDateRangePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (StatsDateRangePreset.allTime, l10n.statsPageRangeAllTime),
      (StatsDateRangePreset.last30Days, l10n.statsPageRangeLast30Days),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            _RangeButton(
              label: options[i].$2,
              selected: selected == options[i].$1,
              onTap: () => onChanged(options[i].$1),
            ),
            if (i != options.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBackground = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFD9DDE2);
    final idleBackground = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEEF0F3);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 32,
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? selectedBackground : idleBackground,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? cs.onSurface.withValues(alpha: 0.9)
                  : cs.onSurface.withValues(alpha: isDark ? 0.7 : 0.62),
              fontSize: 12,
              fontWeight: selected
                  ? AppFontWeights.emphasis
                  : AppFontWeights.semibold,
            ),
          ),
        ),
      ),
    );
  }
}
