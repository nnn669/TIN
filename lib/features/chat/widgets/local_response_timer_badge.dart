import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/chat/local_response_timer.dart';

/// Displays process-local time-to-first-response beside the model name.
class LocalResponseTimerBadge extends StatefulWidget {
  const LocalResponseTimerBadge({super.key, required this.messageId});

  final String messageId;

  @override
  State<LocalResponseTimerBadge> createState() =>
      _LocalResponseTimerBadgeState();
}

class _LocalResponseTimerBadgeState extends State<LocalResponseTimerBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    LocalResponseTimer.listenable(widget.messageId).addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant LocalResponseTimerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId == widget.messageId) return;
    LocalResponseTimer.listenable(oldWidget.messageId)
        .removeListener(_syncTicker);
    LocalResponseTimer.listenable(widget.messageId).addListener(_syncTicker);
    _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) return;
    final running = LocalResponseTimer.listenable(widget.messageId).value.running;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    LocalResponseTimer.listenable(widget.messageId).removeListener(_syncTicker);
    _ticker?.cancel();
    super.dispose();
  }

  String _format(Duration duration) {
    final milliseconds = duration.inMilliseconds.clamp(0, 999999999);
    if (milliseconds < 60000) {
      return '${(milliseconds / 1000).toStringAsFixed(1)}s';
    }
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LocalResponseTimerSnapshot>(
      valueListenable: LocalResponseTimer.listenable(widget.messageId),
      builder: (context, snapshot, _) {
        Duration? elapsed = snapshot.elapsed;
        if (snapshot.running && snapshot.startedAt != null) {
          elapsed = DateTime.now().difference(snapshot.startedAt!);
        }
        if (elapsed == null) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        return Text(
          _format(elapsed),
          key: ValueKey('local-response-timer:${widget.messageId}'),
          style: TextStyle(
            fontSize: 11,
            color: snapshot.running
                ? cs.primary.withValues(alpha: 0.75)
                : cs.onSurface.withValues(alpha: 0.42),
          ),
        );
      },
    );
  }
}
