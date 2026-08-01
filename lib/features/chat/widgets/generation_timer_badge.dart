import 'package:flutter/material.dart';

/// Compatibility placeholder for the removed chat generation timer badge.
///
/// The chat header no longer renders an extra response-duration indicator.
class GenerationTimerBadge extends StatelessWidget {
  const GenerationTimerBadge({
    super.key,
    required this.isStreaming,
    required this.startTime,
    this.durationMs,
  });

  final bool isStreaming;
  final DateTime startTime;
  final int? durationMs;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}