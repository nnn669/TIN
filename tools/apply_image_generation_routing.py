#!/usr/bin/env python3
"""Apply the image-generation provider/model association integration."""

from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]


class PatchError(RuntimeError):
    pass


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise PatchError(f"{path}: expected one anchor, found {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def append_arb_key(path: Path, key: str, value: str) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    if key in data:
        return
    text = path.read_text(encoding="utf-8").rstrip()
    if not text.endswith("}"):
        raise PatchError(f"{path}: invalid ARB ending")
    body = text[:-1].rstrip()
    if not body.endswith(","):
        body += ","
    body += "\n  " + json.dumps(key, ensure_ascii=False) + ": "
    body += json.dumps(value, ensure_ascii=False) + "\n}"
    path.write_text(body + "\n", encoding="utf-8")


def write_new(path: Path, content: str) -> None:
    if path.exists():
        current = path.read_text(encoding="utf-8")
        if current != content:
            raise PatchError(f"{path}: already exists with different content")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def patch_tool_handler() -> None:
    path = ROOT / "lib/features/home/services/tool_handler_service.dart"
    replace_once(
        path,
        "import '../../../core/services/api/chat_api_service.dart';\n",
        "import '../../../core/services/api/chat_api_service.dart';\n"
        "import '../../../core/services/image_generation_routing.dart';\n",
    )
    replace_once(
        path,
        "  ToolCallHandler? buildToolCallHandler(\n    SettingsProvider settings,\n    Assistant? assistant, {\n      ToolApprovalService? approvalService,\n      AskUserInteractionService? askUserService,\n    }) {",
        "  ToolCallHandler? buildToolCallHandler(\n    SettingsProvider settings,\n    Assistant? assistant, {\n      String? providerKey,\n      String? modelId,\n      ToolApprovalService? approvalService,\n      AskUserInteractionService? askUserService,\n    }) {",
    )
    replace_once(
        path,
        "        // MCP tools\n        final text = await toolSvc.callToolTextForAssistant(\n          mcp,\n          assistantProvider,\n          assistantId: assistant?.id,\n          toolName: name,\n          arguments: args,\n        );",
        "        // MCP tools\n        final routed = ImageGenerationRouting.resolveToolArguments(\n          name: name,\n          arguments: args,\n          settings: settings,\n          providerKey: providerKey,\n          modelId: modelId,\n        );\n        if (routed.error != null) {\n          return _toolError(\n            error: 'image_generation_not_configured',\n            message: routed.error!,\n            tool: name,\n            instruction: 'Configure imageProviderId and imageModelId on the chat model, then retry.',\n          );\n        }\n        final text = await toolSvc.callToolTextForAssistant(\n          mcp,\n          assistantProvider,\n          assistantId: assistant?.id,\n          toolName: name,\n          arguments: routed.arguments,\n        );",
    )


def patch_generation_controller() -> None:
    path = ROOT / "lib/features/home/controllers/generation_controller.dart"
    replace_once(
        path,
        "  ToolCallHandler? buildToolCallHandler(\n    SettingsProvider settings,\n    Assistant? assistant, {\n    ToolApprovalService? approvalService,\n    AskUserInteractionService? askUserService,\n  }) {",
        "  ToolCallHandler? buildToolCallHandler(\n    SettingsProvider settings,\n    Assistant? assistant, {\n    String? providerKey,\n    String? modelId,\n    ToolApprovalService? approvalService,\n    AskUserInteractionService? askUserService,\n  }) {",
    )
    replace_once(
        path,
        "      assistant,\n      approvalService: approvalService,\n      askUserService: askUserService,\n    );",
        "      assistant,\n      providerKey: providerKey,\n      modelId: modelId,\n      approvalService: approvalService,\n      askUserService: askUserService,\n    );",
    )


def patch_message_generation_service() -> None:
    path = ROOT / "lib/features/home/services/message_generation_service.dart"
    replace_once(
        path,
        "            settings,\n            assistant,\n            approvalService: approvalService,\n            askUserService: askUserService,\n          )",
        "            settings,\n            assistant,\n            providerKey: providerKey,\n            modelId: modelId,\n            approvalService: approvalService,\n            askUserService: askUserService,\n          )",
    )


def patch_model_detail_sheet() -> None:
    path = ROOT / "lib/features/model/widgets/model_detail_sheet.dart"
    replace_once(
        path,
        "  final List<_BodyKV> _bodies = [];\n",
        "  final List<_BodyKV> _bodies = [];\n\n"
        "  // Optional image-generation provider/model association for this chat model.\n"
        "  final _imageProviderCtrl = TextEditingController();\n"
        "  final _imageModelCtrl = TextEditingController();\n",
    )
    replace_once(
        path,
        "    _nameCtrl.dispose();\n",
        "    _nameCtrl.dispose();\n    _imageProviderCtrl.dispose();\n    _imageModelCtrl.dispose();\n",
    )
    replace_once(
        path,
        "    if (ov != null) {\n      final rawHdrs = ov['headers'];",
        "    if (ov != null) {\n      _imageProviderCtrl.text =\n          (ov['imageProviderId'] ?? ov['image_provider_id'] ?? '').toString();\n      _imageModelCtrl.text =\n          (ov['imageModelId'] ?? ov['image_model_id'] ?? '').toString();\n      final rawHdrs = ov['headers'];",
    )
    replace_once(
        path,
        "            const SizedBox(height: 8),\n            Center(\n              child: _OutlinedAddButton(\n                label: l10n.modelDetailSheetAddProviderOverride,\n                onTap: () {},\n              ),\n            ),",
        "            const SizedBox(height: 8),\n            Text(\n              l10n.imageGenerationAssociationTitle,\n              style: TextStyle(\n                fontSize: 15,\n                fontWeight: AppFontWeights.semibold,\n              ),\n            ),\n            const SizedBox(height: 4),\n            Text(\n              l10n.imageGenerationAssociationDescription,\n              style: TextStyle(\n                color: cs.onSurface.withValues(alpha: 0.7),\n                fontSize: 12,\n              ),\n            ),\n            const SizedBox(height: 8),\n            TextField(\n              controller: _imageProviderCtrl,\n              decoration: InputDecoration(\n                labelText: l10n.imageGenerationProviderLabel,\n                hintText: l10n.imageGenerationProviderHint,\n              ),\n            ),\n            const SizedBox(height: 8),\n            TextField(\n              controller: _imageModelCtrl,\n              decoration: InputDecoration(\n                labelText: l10n.imageGenerationModelLabel,\n                hintText: l10n.imageGenerationModelHint,\n              ),\n            ),\n            const SizedBox(height: 12),\n            Center(\n              child: _OutlinedAddButton(\n                label: l10n.modelDetailSheetAddProviderOverride,\n                onTap: () {},\n              ),\n            ),",
    )
    replace_once(
        path,
        "      'body': bodies,\n      if (!isEmbedding && builtInTools.isNotEmpty) 'builtInTools': builtInTools,\n",
        "      'body': bodies,\n      if (_imageProviderCtrl.text.trim().isNotEmpty)\n        'imageProviderId': _imageProviderCtrl.text.trim(),\n      if (_imageModelCtrl.text.trim().isNotEmpty)\n        'imageModelId': _imageModelCtrl.text.trim(),\n      if (!isEmbedding && builtInTools.isNotEmpty) 'builtInTools': builtInTools,\n",
    )


def patch_localizations() -> None:
    values = {
        "app_en.arb": {
            "imageGenerationAssociationTitle": "Image generation association",
            "imageGenerationAssociationDescription": "When this chat model calls image generation, use the provider and model configured here. The provider API key is never sent to the model.",
            "imageGenerationProviderLabel": "Image provider ID",
            "imageGenerationProviderHint": "For example: OpenAI or MyImagesProvider",
            "imageGenerationModelLabel": "Image model ID",
            "imageGenerationModelHint": "For example: gpt-image-1 or flux-pro",
        },
        "app_zh.arb": {
            "imageGenerationAssociationTitle": "生图服务关联",
            "imageGenerationAssociationDescription": "聊天模型调用生图工具时使用这里配置的服务和模型。服务密钥不会发送给模型。",
            "imageGenerationProviderLabel": "生图 Provider ID",
            "imageGenerationProviderHint": "例如：OpenAI 或 MyImagesProvider",
            "imageGenerationModelLabel": "生图模型 ID",
            "imageGenerationModelHint": "例如：gpt-image-1 或 flux-pro",
        },
        "app_zh_Hans.arb": {
            "imageGenerationAssociationTitle": "生图服务关联",
            "imageGenerationAssociationDescription": "聊天模型调用生图工具时使用这里配置的服务和模型。服务密钥不会发送给模型。",
            "imageGenerationProviderLabel": "生图 Provider ID",
            "imageGenerationProviderHint": "例如：OpenAI 或 MyImagesProvider",
            "imageGenerationModelLabel": "生图模型 ID",
            "imageGenerationModelHint": "例如：gpt-image-1 或 flux-pro",
        },
        "app_zh_Hant.arb": {
            "imageGenerationAssociationTitle": "生圖服務關聯",
            "imageGenerationAssociationDescription": "聊天模型呼叫生圖工具時使用這裡配置的服務和模型。服務密鑰不會發送給模型。",
            "imageGenerationProviderLabel": "生圖 Provider ID",
            "imageGenerationProviderHint": "例如：OpenAI 或 MyImagesProvider",
            "imageGenerationModelLabel": "生圖模型 ID",
            "imageGenerationModelHint": "例如：gpt-image-1 或 flux-pro",
        },
    }
    for filename, entries in values.items():
        path = ROOT / "lib/l10n" / filename
        for key, value in entries.items():
            append_arb_key(path, key, value)


def main() -> None:
    write_new(
        ROOT / "lib/core/services/image_generation_routing.dart",
        '''import '../providers/settings_provider.dart';
import 'api_key_manager.dart';
import 'model_override_payload_parser.dart';

class ImageGenerationRouteResult {
  const ImageGenerationRouteResult({required this.arguments, this.error});

  final Map<String, dynamic> arguments;
  final String? error;
}

/// Resolves a chat model's optional image-generation provider/model association.
/// API credentials are copied only into the internal MCP call arguments and are
/// never included in the tool schema or returned to the model.
class ImageGenerationRouting {
  const ImageGenerationRouting._();

  static const String toolName = 'kelivo_generate_image';

  static ImageGenerationRouteResult resolveToolArguments({
    required String name,
    required Map<String, dynamic> arguments,
    required SettingsProvider settings,
    required String? providerKey,
    required String? modelId,
  }) {
    if (name != toolName || providerKey == null || modelId == null) {
      return ImageGenerationRouteResult(arguments: arguments);
    }

    final chatProvider = settings.providerConfigs[providerKey];
    if (chatProvider == null) {
      return ImageGenerationRouteResult(arguments: arguments);
    }
    final override = ModelOverridePayloadParser.modelOverride(
      chatProvider.modelOverrides,
      modelId,
    );
    final imageProviderId = _firstString(override, const [
      'imageProviderId',
      'image_provider_id',
      'imageProvider',
      'image_provider',
    ]);
    final imageModelId = _firstString(override, const [
      'imageModelId',
      'image_model_id',
      'imageModel',
      'image_model',
    ]);

    if (imageProviderId.isEmpty && imageModelId.isEmpty) {
      return ImageGenerationRouteResult(arguments: arguments);
    }
    if (imageProviderId.isEmpty || imageModelId.isEmpty) {
      return const ImageGenerationRouteResult(
        arguments: <String, dynamic>{},
        error: 'Image generation association requires both a provider ID and a model ID.',
      );
    }

    final imageProvider = settings.providerConfigs[imageProviderId];
    if (imageProvider == null) {
      return ImageGenerationRouteResult(
        arguments: const <String, dynamic>{},
        error: 'The configured image provider was not found in provider settings.',
      );
    }
    final apiBaseUrl = imageProvider.baseUrl.trim();
    final apiKey = _effectiveApiKey(imageProvider);
    if (apiBaseUrl.isEmpty || apiKey.isEmpty) {
      return ImageGenerationRouteResult(
        arguments: const <String, dynamic>{},
        error: 'The configured image provider has no usable API URL or API key.',
      );
    }

    return ImageGenerationRouteResult(
      arguments: {
        ...arguments,
        'api_base_url': apiBaseUrl,
        'api_key': apiKey,
        'model': imageModelId,
      },
    );
  }

  static String _effectiveApiKey(ProviderConfig provider) {
    if (provider.multiKeyEnabled == true &&
        (provider.apiKeys?.isNotEmpty ?? false)) {
      final selected = ApiKeyManager().selectForProvider(provider).key;
      if (selected != null && selected.key.trim().isNotEmpty) {
        return selected.key.trim();
      }
    }
    return provider.apiKey.trim();
  }

  static String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
''',
    )
    patch_tool_handler()
    patch_generation_controller()
    patch_message_generation_service()
    patch_model_detail_sheet()
    patch_localizations()
    print('image generation routing patch applied')


if __name__ == '__main__':
    main()