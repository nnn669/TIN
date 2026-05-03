import 'package:flutter/material.dart';

class ChatInputOverlayLayout extends StatelessWidget {
  const ChatInputOverlayLayout({
    super.key,
    required this.topInset,
    required this.content,
    required this.bottomOverlay,
    this.background,
    this.foreground,
  });

  final double topInset;
  final Widget content;
  final Widget bottomOverlay;
  final Widget? background;
  final Widget? foreground;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (background != null) Positioned.fill(child: background!),
        Positioned.fill(
          top: topInset,
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Align(
                alignment: Alignment.bottomCenter,
                child: UnconstrainedBox(
                  constrainedAxis: Axis.horizontal,
                  alignment: Alignment.bottomCenter,
                  child: bottomOverlay,
                ),
              ),
            ],
          ),
        ),
        if (foreground != null) Positioned.fill(child: foreground!),
      ],
    );
  }
}
