import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'token_detail_popup.dart';

/// Compact token display that shows "123 tokens" and pops up a detail bubble.
///
/// - Mobile: tap to toggle popup (transparent barrier closes it)
/// - Desktop: hover with 200ms delay to show, 300ms delay to close
class TokenDisplayWidget extends StatefulWidget {
  const TokenDisplayWidget({
    super.key,
    required this.totalTokens,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
    this.durationMs,
  });

  final int totalTokens;
  final int? promptTokens;
  final int? completionTokens;
  final int? cachedTokens;
  final int? durationMs;

  @override
  State<TokenDisplayWidget> createState() => _TokenDisplayWidgetState();
}

class _TokenDisplayWidgetState extends State<TokenDisplayWidget>
    with WidgetsBindingObserver {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  OverlayEntry? _barrierEntry;
  bool _isShowing = false;

  // Desktop hover timers
  bool _isHoveringTarget = false;
  bool _isHoveringPopup = false;
  int _showTimerId = 0;
  int _hideTimerId = 0;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get _hasDetailData =>
      (widget.promptTokens != null && widget.promptTokens! > 0) ||
      (widget.completionTokens != null && widget.completionTokens! > 0) ||
      (widget.durationMs != null && widget.durationMs! > 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _removeOverlay();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Close popup on screen rotation / resize
    if (_isShowing) _removeOverlay();
  }

  void _showPopup() {
    if (_isShowing || !mounted) return;
    _isShowing = true;

    final overlay = Overlay.of(context, rootOverlay: false);

    // Transparent barrier for mobile tap-to-close
    if (!_isDesktop) {
      _barrierEntry = OverlayEntry(
        builder: (_) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _removeOverlay,
          child: const SizedBox.expand(),
        ),
      );
      overlay.insert(_barrierEntry!);
    }

    _overlayEntry = OverlayEntry(
      builder: (_) => UnconstrainedBox(
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -8),
          child: Material(
            type: MaterialType.transparency,
            child: _isDesktop
                ? MouseRegion(
                    onEnter: (_) {
                      _isHoveringPopup = true;
                      _cancelHideTimer();
                    },
                    onExit: (_) {
                      _isHoveringPopup = false;
                      _scheduleHide();
                    },
                    child: _buildPopup(),
                  )
                : _buildPopup(),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  Widget _buildPopup() {
    return TokenDetailPopup(
      promptTokens: widget.promptTokens,
      completionTokens: widget.completionTokens,
      cachedTokens: widget.cachedTokens,
      durationMs: widget.durationMs,
    );
  }

  void _removeOverlay() {
    _barrierEntry?.remove();
    _barrierEntry = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
    _isHoveringTarget = false;
    _isHoveringPopup = false;
  }

  void _togglePopup() {
    if (_isShowing) {
      _removeOverlay();
    } else {
      _showPopup();
    }
  }

  // Desktop hover helpers
  void _scheduleShow() {
    final id = ++_showTimerId;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (id == _showTimerId && _isHoveringTarget && mounted) {
        _showPopup();
      }
    });
  }

  void _scheduleHide() {
    final id = ++_hideTimerId;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (id == _hideTimerId &&
          !_isHoveringTarget &&
          !_isHoveringPopup &&
          mounted) {
        _removeOverlay();
      }
    });
  }

  void _cancelHideTimer() {
    _hideTimerId++;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final label = Text(
      l10n.tokenDetailTotalTokens(widget.totalTokens),
      style: TextStyle(
        fontSize: 11,
        color: cs.onSurface.withValues(alpha: 0.5),
      ),
    );

    // If no detailed data, just show plain text (no interaction)
    if (!_hasDetailData) {
      return CompositedTransformTarget(link: _layerLink, child: label);
    }

    Widget child = CompositedTransformTarget(
      link: _layerLink,
      child: label,
    );

    if (_isDesktop) {
      child = MouseRegion(
        onEnter: (_) {
          _isHoveringTarget = true;
          _cancelHideTimer();
          _scheduleShow();
        },
        onExit: (_) {
          _isHoveringTarget = false;
          _scheduleHide();
        },
        child: child,
      );
    } else {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePopup,
        child: child,
      );
    }

    return child;
  }
}