import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chat_fluid_motion_controller.dart';

/// A low-frequency fluid background for the chat surface.
///
/// The optional assistant image remains the lowest layer. The fluid layer uses
/// broad, slow-moving color fields and a light blur so it remains visible in
/// light mode without competing with chat content.
class ChatFluidBackground extends StatelessWidget {
  const ChatFluidBackground({super.key, this.background, this.maskStrength = 1});

  final Widget? background;
  final double maskStrength;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChatFluidMotionController.instance,
      builder: (context, _) {
        if (!ChatFluidMotionController.instance.enabled) {
          return _StaticChatBackground(background: background);
        }
        return _AnimatedChatFluidBackground(
          background: background,
          maskStrength: maskStrength,
        );
      },
    );
  }
}

class _StaticChatBackground extends StatelessWidget {
  const _StaticChatBackground({this.background});

  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: surface),
          if (background != null) background!,
        ],
      ),
    );
  }
}

class _AnimatedChatFluidBackground extends StatefulWidget {
  const _AnimatedChatFluidBackground({this.background, this.maskStrength = 1});

  final Widget? background;
  final double maskStrength;

  @override
  State<_AnimatedChatFluidBackground> createState() =>
      _AnimatedChatFluidBackgroundState();
}

class _AnimatedChatFluidBackgroundState extends State<_AnimatedChatFluidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
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
              Opacity(opacity: 0.82, child: widget.background!),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                painter: _FluidBlobPainter(
                  progress: _controller.value,
                  primary: cs.primary,
                  secondary: cs.secondary,
                  tertiary: Color.lerp(cs.primary, cs.tertiary, 0.62)!,
                  accent: cs.tertiary,
                  warm: isDark ? Colors.orangeAccent : Colors.deepOrange,
                  opacity: isDark ? 0.36 : 0.51,
                ),
              ),
            ),
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: ColoredBox(
                color: cs.surface.withValues(
                  alpha: (isDark ? 0.42 : 0.20) * strength,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.surface.withValues(alpha: 0.04 * strength),
                    cs.surface.withValues(alpha: 0.16 * strength),
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
    required this.tertiary,
    required this.accent,
    required this.warm,
    required this.opacity,
  });

  final double progress;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color accent;
  final Color warm;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;
    final blobs = <_Blob>[
      _Blob(
        Offset(
          size.width * (0.16 + 0.18 * math.sin(t)),
          size.height * (0.18 + 0.14 * math.cos(t)),
        ),
        size.width * 0.70,
        primary,
      ),
      _Blob(
        Offset(
          size.width * (0.82 + 0.17 * math.cos(t + 0.60)),
          size.height * (0.38 + 0.17 * math.sin(t + 0.60)),
        ),
        size.width * 0.64,
        secondary,
      ),
      _Blob(
        Offset(
          size.width * (0.43 + 0.22 * math.sin(t * 2 + 1.20)),
          size.height * (0.83 + 0.13 * math.cos(t * 2 + 1.20)),
        ),
        size.width * 0.62,
        warm,
      ),
      _Blob(
        Offset(
          size.width * (0.56 + 0.14 * math.cos(t * 2 + 2.10)),
          size.height * (0.55 + 0.18 * math.sin(t * 2 + 2.10)),
        ),
        size.width * 0.48,
        tertiary,
      ),
      _Blob(
        Offset(
          size.width * (0.72 + 0.16 * math.sin(t * 3 + 0.35)),
          size.height * (0.16 + 0.12 * math.cos(t * 3 + 0.35)),
        ),
        size.width * 0.44,
        accent,
      ),
    ];
    for (final blob in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            blob.color.withValues(alpha: opacity),
            blob.color.withValues(alpha: opacity * 0.42),
            blob.color.withValues(alpha: 0),
          ],
          stops: const [0, 0.50, 1],
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
      oldDelegate.secondary != secondary ||
      oldDelegate.tertiary != tertiary ||
      oldDelegate.accent != accent ||
      oldDelegate.warm != warm;
}

class _Blob {
  const _Blob(this.center, this.radius, this.color);
  final Offset center;
  final double radius;
  final Color color;
}