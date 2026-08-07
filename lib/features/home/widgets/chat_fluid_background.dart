import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A low-frequency fluid background for the chat surface.
///
/// The optional assistant image remains the lowest layer. Soft animated blobs
/// are deliberately subtle, while the translucent surface and blur preserve
/// message readability.
class ChatFluidBackground extends StatefulWidget {
  const ChatFluidBackground({super.key, this.background, this.maskStrength = 1});

  final Widget? background;
  final double maskStrength;

  @override
  State<ChatFluidBackground> createState() => _ChatFluidBackgroundState();
}

class _ChatFluidBackgroundState extends State<ChatFluidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final strength = widget.maskStrength.clamp(0.0, 1.0);

    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: cs.surface),
            if (widget.background != null)
              Opacity(opacity: 0.9, child: widget.background!),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                painter: _FluidBlobPainter(
                  progress: _controller.value,
                  primary: cs.primary,
                  secondary: cs.secondary,
                  warm: isDark ? Colors.orangeAccent : Colors.deepOrange,
                  opacity: isDark ? 0.17 : 0.11,
                ),
              ),
            ),
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(
                color: cs.surface.withValues(
                  alpha: (isDark ? 0.62 : 0.70) * strength,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.surface.withValues(alpha: 0.14 * strength),
                    cs.surface.withValues(alpha: 0.42 * strength),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FluidBlobPainter extends CustomPainter {
  const _FluidBlobPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.warm,
    required this.opacity,
  });

  final double progress;
  final Color primary;
  final Color secondary;
  final Color warm;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;
    final blobs = <_Blob>[
      _Blob(Offset(size.width * (0.18 + 0.10 * math.sin(t)), size.height * (0.20 + 0.11 * math.cos(t * 0.8))), size.width * 0.58, primary),
      _Blob(Offset(size.width * (0.78 + 0.12 * math.cos(t * 0.72)), size.height * (0.42 + 0.15 * math.sin(t * 0.65))), size.width * 0.54, secondary),
      _Blob(Offset(size.width * (0.45 + 0.18 * math.sin(t * 0.48)), size.height * (0.86 + 0.08 * math.cos(t * 0.55))), size.width * 0.48, warm),
    ];
    for (final blob in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            blob.color.withValues(alpha: opacity),
            blob.color.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: blob.center, radius: blob.radius),
        );
      canvas.drawCircle(blob.center, blob.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_FluidBlobPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary;
}

class _Blob {
  const _Blob(this.center, this.radius, this.color);
  final Offset center;
  final double radius;
  final Color color;
}