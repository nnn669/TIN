import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

/// Controller for managing scroll behavior in the chat home page.
///
/// This controller handles:
/// - Auto-scroll to bottom during streaming
/// - Jump to previous question navigation
/// - Scroll to specific message by ID (via ListObserverController)
/// - Scroll state monitoring (user scrolling detection)
/// - Visibility state for navigation buttons
class ChatScrollController {
  ChatScrollController({
    required ScrollController scrollController,
    required VoidCallback onStateChanged,
    required bool Function() getAutoScrollEnabled,
    required int Function() getAutoScrollIdleSeconds,
  }) : _scrollController = scrollController,
       _onStateChanged = onStateChanged,
       _getAutoScrollEnabled = getAutoScrollEnabled,
       _getAutoScrollIdleSeconds = getAutoScrollIdleSeconds {
    _scrollController.addListener(_onScrollControllerChanged);
    _observerController = ListObserverController(controller: scrollController)
      ..cacheJumpIndexOffset = false;
  }

  final ScrollController _scrollController;
  final VoidCallback _onStateChanged;
  final bool Function() _getAutoScrollEnabled;
  final int Function() _getAutoScrollIdleSeconds;

  /// Observer controller for precise index-based scroll navigation.
  late final ListObserverController _observerController;

  // ============================================================================
  // State Fields
  // ============================================================================

  /// Whether to show the jump-to-bottom button.
  bool _showJumpToBottom = false;
  bool get showJumpToBottom => _showJumpToBottom;

  /// Whether the navigation buttons should be visible (based on scroll activity).
  bool _showNavButtons = false;
  bool get showNavButtons => _showNavButtons;

  /// Timer for auto-hiding navigation buttons.
  Timer? _navButtonsHideTimer;
  static const int _navButtonsHideDelayMs = 2000;

  /// Whether the user is actively scrolling.
  bool _isUserScrolling = false;
  bool get isUserScrolling => _isUserScrolling;

  /// Whether auto-scroll should stick to bottom.
  bool _autoStickToBottom = true;
  bool get autoStickToBottom => _autoStickToBottom;

  /// Timer for detecting end of user scroll.
  Timer? _userScrollTimer;

  /// Scheduling state for batched auto-scroll.
  bool _autoScrollScheduled = false;
  bool _autoScrollForceNext = false;
  bool _autoScrollAnimateNext = true;

  /// Anchor for chained "jump to previous question" navigation.
  String? _lastJumpUserMessageId;
  String? get lastJumpUserMessageId => _lastJumpUserMessageId;

  /// Tolerance for "near bottom" detection.
  static const double _autoScrollSnapTolerance = 56.0;

  // ============================================================================
  // Public Getters
  // ============================================================================

  /// Get the underlying scroll controller.
  ScrollController get scrollController => _scrollController;

  /// Get the observer controller for wrapping ListView.
  ListObserverController get observerController => _observerController;

  /// Check if scroll controller has clients attached.
  bool get hasClients => _scrollController.hasClients;

  // ============================================================================
  // Scroll State Detection
  // ============================================================================

  /// Check if the scroll position is near the bottom.
  bool isNearBottom([double tolerance = _autoScrollSnapTolerance]) {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) <= tolerance;
  }

  /// Check if the scroll view has enough content to scroll.
  ///
  /// [minExtent] - Minimum scroll extent to consider scrollable (default: 56.0).
  bool hasEnoughContentToScroll([double minExtent = 56.0]) {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.maxScrollExtent >= minExtent;
  }

  /// Refresh auto-stick-to-bottom state based on current position.
  void refreshAutoStickToBottom() {
    try {
      final nearBottom = isNearBottom();
      if (!nearBottom) {
        _autoStickToBottom = false;
      } else if (!_isUserScrolling) {
        final enabled = _getAutoScrollEnabled();
        if (enabled || _autoStickToBottom) {
          _autoStickToBottom = true;
        }
      }
    } catch (_) {}
  }

  /// Handle scroll controller changes (called from scroll listener).
  void _onScrollControllerChanged() {
    try {
      if (!_scrollController.hasClients) return;
      final autoScrollEnabled = _getAutoScrollEnabled();

      // Detect user scrolling
      if (_scrollController.position.userScrollDirection !=
          ScrollDirection.idle) {
        _isUserScrolling = true;
        _autoStickToBottom = false;
        // Reset chained jump anchor when user manually scrolls
        _lastJumpUserMessageId = null;

        // Show navigation buttons on scroll activity
        if (!_showNavButtons) {
          _showNavButtons = true;
          _onStateChanged();
        }
        _resetNavButtonsHideTimer();

        // Cancel previous timer and set a new one
        _userScrollTimer?.cancel();
        final secs = _getAutoScrollIdleSeconds();
        _userScrollTimer = Timer(Duration(seconds: secs), () {
          _isUserScrolling = false;
          refreshAutoStickToBottom();
          _onStateChanged();
        });
      }

      // Only show when not near bottom
      final atBottom = isNearBottom(24);
      if (!atBottom) {
        _autoStickToBottom = false;
      } else if (!_isUserScrolling &&
          (autoScrollEnabled || _autoStickToBottom)) {
        _autoStickToBottom = true;
      }
      final shouldShow = !atBottom;
      if (_showJumpToBottom != shouldShow) {
        _showJumpToBottom = shouldShow;
        _onStateChanged();
      }
    } catch (_) {}
  }

  /// Reset the auto-hide timer for navigation buttons.
  void _resetNavButtonsHideTimer() {
    _navButtonsHideTimer?.cancel();
    _navButtonsHideTimer = Timer(
      const Duration(milliseconds: _navButtonsHideDelayMs),
      () {
        if (_showNavButtons) {
          _showNavButtons = false;
          _onStateChanged();
        }
      },
    );
  }

  /// Show navigation buttons manually (e.g., when user taps a button).
  void revealNavButtons() {
    if (!_showNavButtons) {
      _showNavButtons = true;
      _onStateChanged();
    }
    _resetNavButtonsHideTimer();
  }

  /// Hide navigation buttons immediately.
  void hideNavButtons() {
    _navButtonsHideTimer?.cancel();
    if (_showNavButtons) {
      _showNavButtons = false;
      _onStateChanged();
    }
  }

  // ============================================================================
  // Scroll To Bottom Methods
  // ============================================================================

  /// Scroll to the bottom of the list.
  ///
  /// [animate] - Whether to animate the scroll (default: true).
  void scrollToBottom({bool animate = true}) {
    _autoStickToBottom = true;
    _scheduleAutoScrollToBottom(force: true, animate: animate);
  }

  /// Force scroll to bottom (used when user explicitly clicks the button).
  void forceScrollToBottom() {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    _lastJumpUserMessageId = null;
    revealNavButtons();
    scrollToBottom();
  }

  /// Force scroll after rebuilds when switching topics/conversations.
  void forceScrollToBottomSoon({
    bool animate = true,
    Duration postSwitchDelay = const Duration(milliseconds: 220),
  }) {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scrollToBottom(animate: animate),
    );
    Future.delayed(postSwitchDelay, () => scrollToBottom(animate: animate));
  }

  /// Ensure scroll reaches bottom even after widget tree transitions.
  void scrollToBottomSoon({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scrollToBottom(animate: animate),
    );
    Future.delayed(
      const Duration(milliseconds: 120),
      () => scrollToBottom(animate: animate),
    );
  }

  /// Auto-scroll to bottom if conditions are met.
  void autoScrollToBottomIfNeeded() {
    final enabled = _getAutoScrollEnabled();
    if (!enabled && !_autoStickToBottom) return;
    _scheduleAutoScrollToBottom(force: false);
  }

  /// Schedule an auto-scroll to bottom (batched via post-frame callback).
  void _scheduleAutoScrollToBottom({required bool force, bool animate = true}) {
    if (!force) {
      final enabled = _getAutoScrollEnabled();
      if (!enabled && !_autoStickToBottom) return;
    }
    _autoScrollForceNext = _autoScrollForceNext || force;
    _autoScrollAnimateNext = _autoScrollAnimateNext && animate;
    if (_autoScrollScheduled) return;
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoScrollScheduled = false;
      final forceNow = _autoScrollForceNext;
      final animateNow = _autoScrollAnimateNext;
      _autoScrollForceNext = false;
      _autoScrollAnimateNext = true;
      await _animateToBottom(force: forceNow, animate: animateNow);
    });
  }

  /// Animate or jump to the bottom of the scroll view.
  ///
  /// Optimized for streaming: uses jumpTo when close to bottom (< 300px)
  /// to avoid animation flickering from rapid animateTo calls. Content growth
  /// provides the visual scrolling effect naturally.
  /// Uses animateTo only for explicit user-triggered "scroll to bottom".
  Future<void> _animateToBottom({
    required bool force,
    bool animate = true,
  }) async {
    try {
      if (!_scrollController.hasClients) return;
      if (!force) {
        if (_isUserScrolling) return;
        if (!_autoStickToBottom && !isNearBottom()) return;
      }

      // Prevent using controller while it is still attached to old/new list
      if (_scrollController.positions.length != 1) {
        Future.microtask(
          () => _animateToBottom(force: force, animate: animate),
        );
        return;
      }
      final pos = _scrollController.position;
      final max = pos.maxScrollExtent;
      final distance = (max - pos.pixels).abs();
      if (distance < 0.5) {
        _updateJumpToBottomVisibility(false);
        return;
      }

      // Streaming path: distance < 300px → jumpTo for smooth content growth
      // User-triggered path: force + animate → animateTo for smooth navigation
      // No-animate path: jumpTo (conversation switch, etc.)
      if (!animate || (!force && distance < 300)) {
        pos.jumpTo(max);
      } else {
        final durationMs = distance < 500
            ? 250
            : distance < 2000
            ? 350
            : 450;
        await pos.animateTo(
          max,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
      }

      _updateJumpToBottomVisibility(false);
      _autoStickToBottom = true;
    } catch (_) {}
  }

  void _updateJumpToBottomVisibility(bool show) {
    if (_showJumpToBottom != show) {
      _showJumpToBottom = show;
      _onStateChanged();
    }
  }

  // ============================================================================
  // Navigation Methods
  // ============================================================================

  /// Scroll to the top of the list.
  void scrollToTop({bool animate = true}) {
    try {
      if (!_scrollController.hasClients) return;
      _lastJumpUserMessageId = null;
      revealNavButtons();

      if (animate) {
        final pos = _scrollController.position;
        final distance = pos.pixels;
        final durationMs = distance < 200
            ? 150
            : distance < 800
            ? 220
            : 300;
        pos.animateTo(
          0.0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    } catch (_) {}
  }

  /// Jump to the previous user message (question) above the current viewport.
  ///
  /// Uses ListObserverController for precise index-based navigation.
  Future<void> jumpToPreviousQuestion({
    required List<dynamic> messages,
    required int Function(String id) indexOfId,
  }) async {
    try {
      if (!_scrollController.hasClients) return;
      if (messages.isEmpty) return;

      revealNavButtons();

      // Determine anchor index
      int anchor;
      if (_lastJumpUserMessageId != null) {
        final idx = indexOfId(_lastJumpUserMessageId!);
        anchor = idx >= 0 ? idx : messages.length - 1;
      } else {
        // Use observer to find currently visible items
        final result = await _observerController.dispatchOnceObserve();
        final visible = result.observeResult?.displayingChildIndexList;
        anchor = (visible != null && visible.isNotEmpty)
            ? visible.last
            : messages.length - 1;
      }

      // Search backward for previous user message
      int target = -1;
      for (int i = anchor - 1; i >= 0; i--) {
        if (messages[i].role == 'user') {
          target = i;
          break;
        }
      }
      if (target < 0) {
        _scrollController.jumpTo(0.0);
        _lastJumpUserMessageId = null;
        return;
      }

      await _observerController.animateTo(
        index: target,
        alignment: 0.08,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      _lastJumpUserMessageId = messages[target].id;
    } catch (_) {}
  }

  /// Jump to the next user message (question) below the current viewport.
  ///
  /// Uses ListObserverController for precise index-based navigation.
  Future<void> jumpToNextQuestion({
    required List<dynamic> messages,
    required int Function(String id) indexOfId,
  }) async {
    try {
      if (!_scrollController.hasClients) return;
      if (messages.isEmpty) return;

      revealNavButtons();

      // Determine anchor index
      int anchor;
      if (_lastJumpUserMessageId != null) {
        final idx = indexOfId(_lastJumpUserMessageId!);
        anchor = idx >= 0 ? idx : 0;
      } else {
        // Use observer to find currently visible items
        final result = await _observerController.dispatchOnceObserve();
        final visible = result.observeResult?.displayingChildIndexList;
        anchor = (visible != null && visible.isNotEmpty) ? visible.first : 0;
      }

      // Search forward for next user message
      int target = -1;
      for (int i = anchor + 1; i < messages.length; i++) {
        if (messages[i].role == 'user') {
          target = i;
          break;
        }
      }
      if (target < 0) {
        forceScrollToBottom();
        _lastJumpUserMessageId = null;
        return;
      }

      await _observerController.animateTo(
        index: target,
        alignment: 0.08,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
      _lastJumpUserMessageId = messages[target].id;
    } catch (_) {}
  }

  /// Scroll to a specific message by index (from mini map or search).
  ///
  /// Uses ListObserverController for precise index-based scrolling,
  /// replacing the old linear-ratio + paging-loop approach.
  Future<void> scrollToMessageId({
    required String targetId,
    required int targetIndex,
  }) async {
    try {
      if (!_scrollController.hasClients) return;
      if (targetIndex < 0) return;

      await _observerController.animateTo(
        index: targetIndex,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      _lastJumpUserMessageId = targetId;
    } catch (_) {}
  }

  // ============================================================================
  // Observer Cache Management
  // ============================================================================

  /// Clear observer's cached offset data (call on conversation switch).
  void clearObserverCache() {
    _observerController.clearScrollIndexCache();
  }

  // ============================================================================
  // State Modifiers
  // ============================================================================

  /// Reset the last jump user message ID (e.g., when starting new navigation).
  void resetLastJumpUserMessageId() {
    _lastJumpUserMessageId = null;
  }

  /// Set auto-stick-to-bottom state.
  void setAutoStickToBottom(bool value) {
    _autoStickToBottom = value;
  }

  /// Reset user scrolling state (e.g., when force scrolling).
  void resetUserScrolling() {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources.
  void dispose() {
    _scrollController.removeListener(_onScrollControllerChanged);
    _userScrollTimer?.cancel();
    _navButtonsHideTimer?.cancel();
  }
}
