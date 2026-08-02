import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lightweight notifier for streaming message content updates.
///
/// This class provides a way to update streaming message content without
/// triggering a full page rebuild. Instead of using ChangeNotifier.notifyListeners()
/// which causes the entire HomePage to rebuild, this uses ValueNotifier
/// so only the specific message widget that's listening will rebuild.
///
/// Incoming stream chunks may be throttled by the controller. This notifier
/// publishes growing text at roughly the display frame rate so those chunks do
/// not appear as visible two-character jumps on Android.
class StreamingContentNotifier {
  static const Duration _smoothFrameInterval = Duration(milliseconds: 16);
  static const int _smoothCatchUpFrames = 6;
  static const int _smoothMaxCharsPerFrame = 40;

  /// Map of message ID to its content notifier.
  final Map<String, ValueNotifier<StreamingContentData>> _notifiers =
      <String, ValueNotifier<StreamingContentData>>{};
  final Map<String, StreamingContentData> _pendingData =
      <String, StreamingContentData>{};
  final Map<String, Timer> _smoothTimers = <String, Timer>{};

  /// Get or create a notifier for a message.
  ValueNotifier<StreamingContentData> getNotifier(String messageId) {
    return _notifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<StreamingContentData>(
        const StreamingContentData(content: '', totalTokens: 0),
      ),
    );
  }

  /// Check if a notifier exists for a message.
  bool hasNotifier(String messageId) => _notifiers.containsKey(messageId);

  /// Update content for a streaming message.
  /// This will only notify the specific widget listening to this message's notifier.
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

    final current = _pendingData[messageId] ?? notifier.value;
    final next = current.copyWith(
      content: content,
      totalTokens: totalTokens,
      contentSplitOffsets: contentSplitOffsets,
      reasoningCountAtSplit: reasoningCountAtSplit,
      toolCountAtSplit: toolCountAtSplit,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      cachedTokens: cachedTokens,
    );
    _pendingData[messageId] = next;

    final visible = notifier.value.content;
    if (content == visible) {
      notifier.value = next;
      _stopSmoothTimer(messageId);
      return;
    }
    if (!content.startsWith(visible)) {
      notifier.value = next;
      _stopSmoothTimer(messageId);
      return;
    }
    _smoothTimers.putIfAbsent(
      messageId,
      () => Timer.periodic(
        _smoothFrameInterval,
        (_) => _publishSmoothFrame(messageId),
      ),
    );
  }

  void _publishSmoothFrame(String messageId) {
    final notifier = _notifiers[messageId];
    final target = _pendingData[messageId];
    if (notifier == null || target == null) {
      _stopSmoothTimer(messageId);
      return;
    }

    final visible = notifier.value.content;
    if (visible == target.content || !target.content.startsWith(visible)) {
      if (notifier.value != target) notifier.value = target;
      _stopSmoothTimer(messageId);
      return;
    }

    final backlog = target.content.length - visible.length;
    final charsPerFrame = (backlog / _smoothCatchUpFrames)
        .ceil()
        .clamp(1, _smoothMaxCharsPerFrame);
    final nextLength = _safeSliceEnd(
      target.content,
      (visible.length + charsPerFrame).clamp(0, target.content.length),
    );
    notifier.value = target.copyWith(
      content: target.content.substring(0, nextLength),
    );
    if (nextLength >= target.content.length) _stopSmoothTimer(messageId);
  }

  int _safeSliceEnd(String text, int end) {
    if (end <= 0 || end >= text.length) return end;
    final previous = text.codeUnitAt(end - 1);
    final next = text.codeUnitAt(end);
    final splitsSurrogatePair =
        previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
    return splitsSurrogatePair ? end + 1 : end;
  }

  void _stopSmoothTimer(String messageId) {
    _smoothTimers.remove(messageId)?.cancel();
  }

  /// Update reasoning content for a streaming message.
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
    if (notifier != null) {
      final pending = _pendingData[messageId] ?? notifier.value;
      _pendingData[messageId] = pending.copyWith(
        reasoningText: reasoningText,
        reasoningStartAt: reasoningStartAt,
        reasoningFinishedAt: reasoningFinishedAt,
        contentSplitOffsets: contentSplitOffsets,
        reasoningCountAtSplit: reasoningCountAtSplit,
        toolCountAtSplit: toolCountAtSplit,
      );
      notifier.value = notifier.value.copyWith(
        reasoningText: reasoningText,
        reasoningStartAt: reasoningStartAt,
        reasoningFinishedAt: reasoningFinishedAt,
        contentSplitOffsets: contentSplitOffsets,
        reasoningCountAtSplit: reasoningCountAtSplit,
        toolCountAtSplit: toolCountAtSplit,
      );
    }
  }

  /// Notify that tool parts have been updated.
  /// Uses a version counter to trigger rebuild without copying tool data.
  void notifyToolPartsUpdated(
    String messageId, {
    List<int>? contentSplitOffsets,
    List<int>? reasoningCountAtSplit,
    List<int>? toolCountAtSplit,
  }) {
    final notifier = _notifiers[messageId];
    if (notifier != null) {
      final pending = _pendingData[messageId] ?? notifier.value;
      final version = pending.toolPartsVersion + 1;
      _pendingData[messageId] = pending.copyWith(
        contentSplitOffsets: contentSplitOffsets,
        reasoningCountAtSplit: reasoningCountAtSplit,
        toolCountAtSplit: toolCountAtSplit,
        toolPartsVersion: version,
      );
      notifier.value = notifier.value.copyWith(
        contentSplitOffsets: contentSplitOffsets,
        reasoningCountAtSplit: reasoningCountAtSplit,
        toolCountAtSplit: toolCountAtSplit,
        toolPartsVersion: version,
      );
    }
  }

  /// Force a rebuild of the streaming message widget.
  void forceRebuild(String messageId) {
    final notifier = _notifiers[messageId];
    if (notifier != null) {
      final pending = _pendingData[messageId] ?? notifier.value;
      final version = pending.uiVersion + 1;
      _pendingData[messageId] = pending.copyWith(uiVersion: version);
      notifier.value = notifier.value.copyWith(uiVersion: version);
    }
  }

  /// Remove notifier when streaming is complete.
  void removeNotifier(String messageId) {
    _stopSmoothTimer(messageId);
    _pendingData.remove(messageId);
    final notifier = _notifiers.remove(messageId);
    notifier?.dispose();
  }

  /// Clear all notifiers (e.g., when switching conversations).
  void clear() {
    for (final timer in _smoothTimers.values) {
      timer.cancel();
    }
    _smoothTimers.clear();
    _pendingData.clear();
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }

  /// Dispose all resources.
  void dispose() {
    clear();
  }
}

/// Data class for streaming content.
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

  /// Version counter for tool parts updates. Incrementing this triggers rebuild.
  final int toolPartsVersion;

  /// Version counter for UI state changes (e.g., reasoning expanded toggle).
  final int uiVersion;

  /// Detailed token usage fields.
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
  int get hashCode =>
      content.hashCode ^
      totalTokens.hashCode ^
      reasoningText.hashCode ^
      reasoningStartAt.hashCode ^
      reasoningFinishedAt.hashCode ^
      Object.hashAll(contentSplitOffsets ?? const <int>[]) ^
      Object.hashAll(reasoningCountAtSplit ?? const <int>[]) ^
      Object.hashAll(toolCountAtSplit ?? const <int>[]) ^
      toolPartsVersion.hashCode ^
      uiVersion.hashCode ^
      promptTokens.hashCode ^
      completionTokens.hashCode ^
      cachedTokens.hashCode;
}
