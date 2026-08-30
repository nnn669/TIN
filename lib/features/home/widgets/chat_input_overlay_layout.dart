import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chat_fluid_background.dart';

class ChatInputOverlayLayout extends StatelessWidget {
  const ChatInputOverlayLayout({
    super.key,
    required this.topInset,
    required this.content,
    required this.bottomOverlay,
    this.background,
    this.topBackground,
    this.foreground,
    this.backgroundImageActive = false,
  });

  final double topInset;
  final Widget content;
  final Widget bottomOverlay;
  final Widget? background;
  final Widget? topBackground;
  final Widget? foreground;
  final bool backgroundImageActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ChatFluidBackground(background: background ?? topBackground),
        ),
        // Keep the title area readable without hiding the fluid motion.
        // The lower gradient edge fades the veil into the background naturally.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topInset + 36,
          child: IgnorePointer(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.30),
                        Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.22),
                        Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.56, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  clipper: _TopOverlayClipper(topInset),
                  child: content,
                ),
              ),
              if (foreground != null) Positioned.fill(child: foreground!),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: UnconstrainedBox(
            constrainedAxis: Axis.horizontal,
            alignment: Alignment.bottomCenter,
            child: bottomOverlay,
          ),
        ),
      ],
    );
  }
}

class _TopOverlayClipper extends CustomClipper<Rect> {
  const _TopOverlayClipper(this.topInset);

  final double topInset;

  @override
  Rect getClip(Size size) {
    final clipTop = topInset.clamp(0.0, size.height).toDouble();
    return Rect.fromLTWH(0, clipTop, size.width, size.height - clipTop);
  }

  @override
  bool shouldReclip(_TopOverlayClipper oldClipper) =>
      oldClipper.topInset != topInset;
}
