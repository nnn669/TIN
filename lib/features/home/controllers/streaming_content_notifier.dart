import 'package:flutter/foundation.dart';

/// Lightweight notifier for streaming message content updates.
///
/// Frame pacing belongs to [StreamController]. This notifier publishes each
/// prepared frame immediately so the rendering path has only one scheduler.
class StreamingContentNotifier {
  final Map<String, ValueNotifier<StreamingContentData>> _notifiers =
      <String, ValueNotifier<StreamingContentData>>{};

  ValueNotifier<StreamingContentData> getNotifier(String messageId) {
    return _notifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<StreamingContentData>(
        const StreamingContentData(content: '', totalTokens: 0),
      ),
    );
  }

  bool hasNotifier(String messageId) => _notifiers.containsKey(messageId);

  void updateContent(
    String messageId,
    String content,
    int totalTokens, {
    List<int>? contentSplitOffsets,
    List<int>? reasoningCountAtSplit,
    List<int>? toolCountAtSplit,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
  }) {
    final notifier = _notifiers[messageId];
    if (notifier == null) return;
    notifier.value = notifier.value.copyWith(
      content: content,
      totalTokens: totalTokens,
      contentSplitOffsets: contentSplitOffsets,
      reasoningCountAtSplit: reasoningCountAtSplit,
      toolCountAtSplit: toolCountAtSplit,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      cachedTokens: cachedTokens,
    );
  }

  void updateReasoning(
    String messageId, {
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    List<int>? contentSplitOffsets,
    List<int>? reasoningCountAtSplit,
    List<int>? toolCountAtSplit,
  }) {
    final notifier = _notifiers[messageId];
    if (notifier == null) return;
    notifier.value = notifier.value.copyWith(
      reasoningText: reasoningText,
      reasoningStartAt: reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt,
      contentSplitOffsets: contentSplitOffsets,
      reasoningCountAtSplit: reasoningCountAtSplit,
      toolCountAtSplit: toolCountAtSplit,
    );
  }

  void notifyToolPartsUpdated(
    String messageId, {
    List<int>? contentSplitOffsets,
    List<int>? reasoningCountAtSplit,
    List<int>? toolCountAtSplit,
  }) {
    final notifier = _notifiers[messageId];
    if (notifier == null) return;
    notifier.value = notifier.value.copyWith(
      contentSplitOffsets: contentSplitOffsets,
      reasoningCountAtSplit: reasoningCountAtSplit,
      toolCountAtSplit: toolCountAtSplit,
      toolPartsVersion: notifier.value.toolPartsVersion + 1,
    );
  }

  void forceRebuild(String messageId) {
    final notifier = _notifiers[messageId];
    if (notifier == null) return;
    notifier.value = notifier.value.copyWith(
      uiVersion: notifier.value.uiVersion + 1,
    );
  }

  void removeNotifier(String messageId) {
    _notifiers.remove(messageId)?.dispose();
  }

  void clear() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }

  void dispose() => clear();
}

@immutable
class StreamingContentData {
  const StreamingContentData({
    required this.content,
    required this.totalTokens,
    this.reasoningText,
    this.reasoningStartAt,
    this.reasoningFinishedAt,
    this.contentSplitOffsets,
    this.reasoningCountAtSplit,
    this.toolCountAtSplit,
    this.toolPartsVersion = 0,
    this.uiVersion = 0,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
  });

  final String content;
  final int totalTokens;
  final String? reasoningText;
  final DateTime? reasoningStartAt;
  final DateTime? reasoningFinishedAt;
  final List<int>? contentSplitOffsets;
  final List<int>? reasoningCountAtSplit;
  final List<int>? toolCountAtSplit;
  final int toolPartsVersion;
  final int uiVersion;
  final int? promptTokens;
  final int? completionTokens;
  final int? cachedTokens;

  StreamingContentData copyWith({
    String? content,
    int? totalTokens,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    List<int>? contentSplitOffsets,
    List<int>? reasoningCountAtSplit,
    List<int>? toolCountAtSplit,
    int? toolPartsVersion,
    int? uiVersion,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
  }) {
    return StreamingContentData(
      content: content ?? this.content,
      totalTokens: totalTokens ?? this.totalTokens,
      reasoningText: reasoningText ?? this.reasoningText,
      reasoningStartAt: reasoningStartAt ?? this.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? this.reasoningFinishedAt,
      contentSplitOffsets: contentSplitOffsets ?? this.contentSplitOffsets,
      reasoningCountAtSplit:
          reasoningCountAtSplit ?? this.reasoningCountAtSplit,
      toolCountAtSplit: toolCountAtSplit ?? this.toolCountAtSplit,
      toolPartsVersion: toolPartsVersion ?? this.toolPartsVersion,
      uiVersion: uiVersion ?? this.uiVersion,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamingContentData &&
          runtimeType == other.runtimeType &&
          content == other.content &&
          totalTokens == other.totalTokens &&
          reasoningText == other.reasoningText &&
          reasoningStartAt == other.reasoningStartAt &&
          reasoningFinishedAt == other.reasoningFinishedAt &&
          listEquals(contentSplitOffsets, other.contentSplitOffsets) &&
          listEquals(reasoningCountAtSplit, other.reasoningCountAtSplit) &&
          listEquals(toolCountAtSplit, other.toolCountAtSplit) &&
          toolPartsVersion == other.toolPartsVersion &&
          uiVersion == other.uiVersion &&
          promptTokens == other.promptTokens &&
          completionTokens == other.completionTokens &&
          cachedTokens == other.cachedTokens;

  @override
  int get hashCode => Object.hash(
    content,
    totalTokens,
    reasoningText,
    reasoningStartAt,
    reasoningFinishedAt,
    Object.hashAll(contentSplitOffsets ?? const <int>[]),
    Object.hashAll(reasoningCountAtSplit ?? const <int>[]),
    Object.hashAll(toolCountAtSplit ?? const <int>[]),
    toolPartsVersion,
    uiVersion,
    promptTokens,
    completionTokens,
    cachedTokens,
  );
}