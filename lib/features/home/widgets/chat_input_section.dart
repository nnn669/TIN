import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/skill_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../utils/model_display_helper.dart';
import 'chat_input_bar.dart';

defaultShouldStopBeforeSubmit({required bool isLoading, required ChatInputData input}) {
  return isLoading && input.text.trim().isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty;
}

typedef IsToolModelCallback = bool Function(String providerKey, String modelId);
typedef IsReasoningModelCallback = bool Function(String providerKey, String modelId);
typedef IsReasoningEnabledCallback = bool Function(int? budget);

class ChatInputSection extends StatelessWidget {
  const ChatInputSection({super.key, required this.inputBarKey, required this.inputFocus, required this.inputController, required this.mediaController, required this.isTablet, required this.isLoading, required this.isToolModel, required this.isReasoningModel, required this.isReasoningEnabled, this.onMore, this.onSelectModel, this.onLongPressSelectModel, this.onOpenMcp, this.onOpenSkills, this.onLongPressMcp, this.onOpenSearch, this.onConfigureReasoning, this.onSend, this.onStop, this.hasQueuedInput = false, this.queuedPreviewText, this.onCancelQueuedInput, this.onQuickPhrase, this.onLongPressQuickPhrase, this.onToggleOcr, this.onOpenMiniMap, this.onPickCamera, this.onPickPhotos, this.onUploadFiles, this.onToggleLearningMode, this.onLongPressLearning, this.onClearContext, this.onCompressContext, this.conversationId, this.sendButtonTooltip, this.backgroundImageActive = false});
  final GlobalKey inputBarKey;
  final FocusNode inputFocus;
  final TextEditingController inputController;
  final ChatInputBarController mediaController;
  final bool isTablet;
  final bool isLoading;
  final IsToolModelCallback isToolModel;
  final IsReasoningModelCallback isReasoningModel;
  final IsReasoningEnabledCallback isReasoningEnabled;
  final VoidCallback? onMore;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenMcp;
  final VoidCallback? onOpenSkills;
  final VoidCallback? onLongPressMcp;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onConfigureReasoning;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final Future<void> Function()? onStop;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final VoidCallback? onToggleOcr;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onUploadFiles;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onLongPressLearning;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final String? conversationId;
  final String? sendButtonTooltip;
  final bool backgroundImageActive;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;
    final assistantId = a?.id;
    final modelIds = getActiveModelIds(settings, assistant: a);
    final pk = modelIds.providerKey;
    final mid = modelIds.modelId;
    _enforceModelCapabilities(context, settings, ap, a, pk, mid);
    final isDesktop = _isDesktopPlatform(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: inputController,
      builder: (context, inputValue, _) {
        final hasInterruptingText = inputValue.text.trim().isNotEmpty;
        final showStopButton = isLoading && !hasInterruptingText;
        Future<ChatInputSubmissionResult> submit(ChatInputData input) async {
          if (defaultShouldStopBeforeSubmit(isLoading: isLoading, input: input)) {
            await onStop?.call();
          }
          return await onSend?.call(input) ?? ChatInputSubmissionResult.rejected;
        }
        return ChatInputBar(
          key: inputBarKey,
          onMore: onMore,
          onSelectModel: onSelectModel,
          onLongPressSelectModel: onLongPressSelectModel,
          conversationId: conversationId,
          onOpenMcp: onOpenMcp,
          onOpenSkills: onOpenSkills,
          onLongPressMcp: onLongPressMcp,
          onStop: onStop,
          modelIcon: (pk != null && mid != null) ? CurrentModelIcon(providerKey: pk, modelId: mid, size: 40, withBackground: true, backgroundColor: Colors.transparent) : null,
          focusNode: inputFocus,
          controller: inputController,
          mediaController: mediaController,
          onConfigureReasoning: onConfigureReasoning,
          reasoningActive: isReasoningEnabled(a?.thinkingBudget ?? settings.thinkingBudget),
          reasoningBudget: a?.thinkingBudget ?? settings.thinkingBudget,
          supportsReasoning: (pk != null && mid != null) ? isReasoningModel(pk, mid) : false,
          onOpenSearch: onOpenSearch,
          onSend: submit,
          loading: showStopButton,
          sendButtonTooltip: sendButtonTooltip,
          hasQueuedInput: hasQueuedInput,
          queuedPreviewText: queuedPreviewText,
          onCancelQueuedInput: onCancelQueuedInput,
          showMcpButton: _shouldShowMcpButton(context, settings, a, pk, mid),
          mcpActive: _isMcpActive(context, a),
          skillsActive: _isSkillsActive(context, a),
          showQuickPhraseButton: _hasQuickPhrases(context, a),
          onQuickPhrase: onQuickPhrase,
          onLongPressQuickPhrase: onLongPressQuickPhrase,
          showOcrButton: isTablet ? (settings.ocrModelProvider != null && settings.ocrModelId != null) : (isDesktop && settings.ocrModelProvider != null && settings.ocrModelId != null),
          ocrActive: settings.ocrEnabled,
          onToggleOcr: onToggleOcr,
          showMiniMapButton: isTablet,
          onOpenMiniMap: isTablet ? onOpenMiniMap : null,
          onPickCamera: isTablet ? (isDesktop ? null : onPickCamera) : null,
          onPickPhotos: isTablet ? (isDesktop ? null : onPickPhotos) : null,
          onUploadFiles: isTablet ? onUploadFiles : null,
          onToggleLearningMode: isTablet ? onToggleLearningMode : null,
          onLongPressLearning: isTablet ? onLongPressLearning : null,
          learningModeActive: isTablet ? context.watch<InstructionInjectionProvider>().activeIdsFor(assistantId).isNotEmpty : false,
          showMoreButton: !isTablet,
          onClearContext: isTablet ? onClearContext : null,
          onCompressContext: isTablet ? onCompressContext : null,
          backgroundImageActive: backgroundImageActive,
          inputBackgroundOpacityLight: settings.chatInputBackgroundOpacityLight,
          inputBackgroundOpacityDark: settings.chatInputBackgroundOpacityDark,
        );
      },
    );
  }

  bool _isDesktopPlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS || platform == TargetPlatform.windows || platform == TargetPlatform.linux;
  }

  void _enforceModelCapabilities(BuildContext context, SettingsProvider settings, AssistantProvider ap, Assistant? a, String? pk, String? mid) {
    if (pk == null || mid == null) return;
    final supportsTools = isToolModel(pk, mid);
    if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final aa = ap.currentAssistant;
        if (aa != null && aa.mcpServerIds.isNotEmpty) ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
      });
    }
    final supportsReasoning = isReasoningModel(pk, mid);
    if (!supportsReasoning && a != null) {
      final enabledNow = isReasoningEnabled(a.thinkingBudget ?? settings.thinkingBudget);
      if (enabledNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final aa = ap.currentAssistant;
          if (aa != null) await ap.updateAssistant(aa.copyWith(thinkingBudget: 0));
        });
      }
    }
  }

  bool _shouldShowMcpButton(BuildContext context, SettingsProvider settings, Assistant? a, String? pk, String? mid) {
    final pk2 = a?.chatModelProvider ?? settings.currentModelProvider;
    final mid3 = a?.chatModelId ?? settings.currentModelId;
    if (pk2 == null || mid3 == null) return false;
    final hasEnabledMcp = context.watch<McpProvider>().hasAnyEnabled;
    return isToolModel(pk2, mid3) && hasEnabledMcp;
  }

  bool _isMcpActive(BuildContext context, Assistant? a) {
    final connected = context.watch<McpProvider>().connectedServers;
    final selected = a?.mcpServerIds ?? const <String>[];
    if (selected.isEmpty || connected.isEmpty) return false;
    return connected.any((s) => selected.contains(s.id));
  }

  bool _isSkillsActive(BuildContext context, Assistant? a) {
    final selected = a?.skillIds ?? const <String>[];
    if (selected.isEmpty) return false;
    final provider = context.watch<SkillProvider>();
    return selected.any((id) => provider.getById(id)?.enabled ?? false);
  }

  bool _hasQuickPhrases(BuildContext context, Assistant? a) {
    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final globalCount = quickPhraseProvider.globalPhrases.length;
    final assistantCount = a != null ? quickPhraseProvider.getForAssistant(a.id).length : 0;
    return (globalCount + assistantCount) > 0;
  }
}