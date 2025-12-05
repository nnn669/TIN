import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Glassy scroll navigation button with backdrop blur effect.
///
/// Used for scroll-to-bottom and scroll-to-previous-question buttons.
/// Includes fade and scale animation support via [visible] parameter.
class GlassyScrollButton extends StatelessWidget {
  const GlassyScrollButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.bottomOffset,
    required this.visible,
    this.iconSize = 16,
    this.padding = 6,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double bottomOffset;
  final bool visible;
  final double iconSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        top: false,
        bottom: false,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedScale(
            scale: visible ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: visible ? 1 : 0,
              child: Padding(
                padding: EdgeInsets.only(right: 16, bottom: bottomOffset),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.white.withOpacity(0.07),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.10)
                              : Theme.of(context).colorScheme.outline.withOpacity(0.20),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onTap,
                          child: Padding(
                            padding: EdgeInsets.all(padding),
                            child: Icon(
                              icon,
                              size: iconSize,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
