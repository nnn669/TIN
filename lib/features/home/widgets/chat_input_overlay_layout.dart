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
          child: ChatFluidBackground(
            background: background ?? topBackground,
          ),
        ),
        Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(child: content),
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