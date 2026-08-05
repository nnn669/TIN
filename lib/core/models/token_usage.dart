class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int totalTokens;

  // A cumulative snapshot contains the totals from completed rounds plus the
  // latest round snapshot. These fields are intentionally private: token
  // usage serialization remains unchanged.
  final bool _isCumulative;
  final int _basePromptTokens;
  final int _baseCompletionTokens;
  final int _baseCachedTokens;
  final int _baseTotalTokens;
  final int _snapshotPromptTokens;
  final int _snapshotCompletionTokens;
  final int _snapshotCachedTokens;
  final int _snapshotTotalTokens;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cachedTokens = 0,
    this.totalTokens = 0,
  }) : _isCumulative = false,
       _basePromptTokens = 0,
       _baseCompletionTokens = 0,
       _baseCachedTokens = 0,
       _baseTotalTokens = 0,
       _snapshotPromptTokens = promptTokens,
       _snapshotCompletionTokens = completionTokens,
       _snapshotCachedTokens = cachedTokens,
       _snapshotTotalTokens = totalTokens;

  const TokenUsage._cumulative({
    required int basePromptTokens,
    required int baseCompletionTokens,
    required int baseCachedTokens,
    required int baseTotalTokens,
    required int snapshotPromptTokens,
    required int snapshotCompletionTokens,
    required int snapshotCachedTokens,
    required int snapshotTotalTokens,
  }) : promptTokens = basePromptTokens + snapshotPromptTokens,
       completionTokens = baseCompletionTokens + snapshotCompletionTokens,
       cachedTokens = baseCachedTokens + snapshotCachedTokens,
       totalTokens = _total(
         promptTokens: basePromptTokens + snapshotPromptTokens,
         completionTokens: baseCompletionTokens + snapshotCompletionTokens,
         baseTotalTokens: baseTotalTokens,
         snapshotTotalTokens: snapshotTotalTokens,
       ),
       _isCumulative = true,
       _basePromptTokens = basePromptTokens,
       _baseCompletionTokens = baseCompletionTokens,
       _baseCachedTokens = baseCachedTokens,
       _baseTotalTokens = baseTotalTokens,
       _snapshotPromptTokens = snapshotPromptTokens,
       _snapshotCompletionTokens = snapshotCompletionTokens,
       _snapshotCachedTokens = snapshotCachedTokens,
       _snapshotTotalTokens = snapshotTotalTokens;

  static int _total({
    required int promptTokens,
    required int completionTokens,
    required int baseTotalTokens,
    required int snapshotTotalTokens,
  }) {
    final splitTotal = promptTokens + completionTokens;
    return splitTotal > 0
        ? splitTotal
        : baseTotalTokens + snapshotTotalTokens;
  }

  /// Merge snapshots from one API request.
  ///
  /// A stable prompt count means the provider is still streaming the same
  /// request, so the newest non-zero fields replace the previous snapshot.
  /// When the prompt count grows, a tool-follow-up request has started; keep
  /// the completed-round base and add the new round snapshot.
  TokenUsage merge(TokenUsage other) {
    if (other._isCumulative) return other;

    if (_isCumulative) {
      final nextRound =
          other.promptTokens > _snapshotPromptTokens &&
          other.promptTokens > 0;
      return TokenUsage._cumulative(
        basePromptTokens: nextRound ? promptTokens : _basePromptTokens,
        baseCompletionTokens:
            nextRound ? completionTokens : _baseCompletionTokens,
        baseCachedTokens: nextRound ? cachedTokens : _baseCachedTokens,
        baseTotalTokens: nextRound ? totalTokens : _baseTotalTokens,
        snapshotPromptTokens: other.promptTokens,
        snapshotCompletionTokens: other.completionTokens,
        snapshotCachedTokens: other.cachedTokens,
        snapshotTotalTokens: other.totalTokens,
      );
    }

    final nextRound =
        other.promptTokens > promptTokens && other.promptTokens > 0;
    if (nextRound) {
      return TokenUsage._cumulative(
        basePromptTokens: promptTokens,
        baseCompletionTokens: completionTokens,
        baseCachedTokens: cachedTokens,
        baseTotalTokens: totalTokens,
        snapshotPromptTokens: other.promptTokens,
        snapshotCompletionTokens: other.completionTokens,
        snapshotCachedTokens: other.cachedTokens,
        snapshotTotalTokens: other.totalTokens,
      );
    }

    final prompt = other.promptTokens > 0 ? other.promptTokens : promptTokens;
    final completion = other.completionTokens > 0
        ? other.completionTokens
        : completionTokens;
    final cached = other.cachedTokens > 0 ? other.cachedTokens : cachedTokens;
    final splitTotal = prompt + completion;
    final explicitTotal = other.totalTokens > 0
        ? other.totalTokens
        : totalTokens;
    final total = splitTotal > 0 ? splitTotal : explicitTotal;
    return TokenUsage(
      promptTokens: prompt,
      completionTokens: completion,
      cachedTokens: cached,
      totalTokens: total,
    );
  }

  /// Add a completed request round explicitly.
  TokenUsage add(TokenUsage other) {
    return TokenUsage._cumulative(
      basePromptTokens: promptTokens,
      baseCompletionTokens: completionTokens,
      baseCachedTokens: cachedTokens,
      baseTotalTokens: totalTokens,
      snapshotPromptTokens: other.promptTokens,
      snapshotCompletionTokens: other.completionTokens,
      snapshotCachedTokens: other.cachedTokens,
      snapshotTotalTokens: other.totalTokens,
    );
  }
}
