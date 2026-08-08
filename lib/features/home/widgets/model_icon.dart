import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/model_override_payload_parser.dart';
import '../../../core/utils/openai_model_compat.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/brand_assets.dart';

/// Widget that displays the current model's icon.
///
/// Shows either:
/// - A brand SVG/PNG icon if available for the model/provider
/// - A circular placeholder with the first letter of the model name
class CurrentModelIcon extends StatelessWidget {
  const CurrentModelIcon({
    super.key,
    required this.providerKey,
    required this.modelId,
    this.size = 28,
    this.withBackground = true,
    this.backgroundColor,
  });

  final String? providerKey;
  final String? modelId;
  final double size;
  final bool withBackground;
  final Color? backgroundColor;

  String _upstreamModelId(BuildContext context) {
    final requestedModelId = modelId?.trim() ?? '';
    if (requestedModelId.isEmpty || providerKey == null) {
      return requestedModelId;
    }

    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final config = settings.getProviderConfig(providerKey!);
      final override = ModelOverridePayloadParser.modelOverride(
        config.modelOverrides,
        requestedModelId,
      );
      return resolveApiModelIdOverride(override, requestedModelId);
    } catch (_) {
      return requestedModelId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (providerKey == null || modelId == null) return const SizedBox.shrink();

    final upstreamModelId = _upstreamModelId(context);
    String? asset = BrandAssets.assetForName(upstreamModelId);
    asset ??= BrandAssets.assetForName(providerKey!);

    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint =
            (Theme.of(context).brightness == Brightness.dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        upstreamModelId.isNotEmpty
            ? upstreamModelId.characters.first.toUpperCase()
            : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.43,
        ),
      );
    }

    return Tooltip(
      message: upstreamModelId,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: withBackground
              ? (backgroundColor ??
                    (isDark
                        ? Colors.white10
                        : cs.primary.withValues(alpha: 0.1)))
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: size * 0.64,
          height: size * 0.64,
          child: Center(
            child: inner is SvgPicture || inner is Image
                ? inner
                : FittedBox(child: inner),
          ),
        ),
      ),
    );
  }
}
