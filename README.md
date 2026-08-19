# TIN

TIN (package name `Kelivo`) is a cross-platform LLM chat client built with Flutter.
It targets Android, iOS, macOS, Windows and Linux, with a mobile-first custom iOS-style UI.

## Features

- **Multi-provider chat**: OpenAI-compatible endpoints (Chat Completions / Responses / Images),
  Google Gemini & Vertex AI (incl. service-account auth), and the Anthropic Claude official API.
  Widely tested against OpenAI, DeepSeek, Kimi (Moonshot), Zhipu GLM, SiliconFlow, Qwen/DashScope and OpenRouter.
- **Streaming responses** (SSE) with reasoning/thinking steps support and collapsed thinking display.
- **Provider & model management**: provider groups, per-provider headers, custom providers,
  model overrides and payload overrides, reasoning budget control.
- **Assistants & memory**: assistant profiles, tags, long-term memory, learning mode.
- **MCP client**: connect to MCP servers, manage tools with per-tool approval policies,
  tool loop guard, plus local tools.
- **Skills & instruction injection**: reusable prompt skills and conditional instruction groups.
- **Content tools**: web search (DuckDuckGo), translation, document text extraction,
  Markdown rendering (incl. Mermaid and math), PDF export, image input/cropping, image generation.
- **Productivity**: quick phrases, chat statistics, QR code scanning, webview, share, haptics, TTS.
- **Background generation** with local notifications on Android and iOS.
- **Backup & restore**: local file backup and S3-compatible remote backup.
- **Localization**: English, Simplified Chinese and Traditional Chinese.
- **Desktop shell**: tray icon, hotkeys and a custom window title bar on macOS/Windows/Linux.

## Platforms

| Platform | Entry point |
| --- | --- |
| Android / iOS | `lib/main.dart` → `HomePage` |
| macOS / Windows / Linux | `lib/main.dart` → `DesktopHomePage` |

Android builds are released as a single **arm64-v8a** APK.

## Build

Requirements: Flutter `>=3.44.1` (Dart `^3.12.1`), Android SDK with NDK 28.

```bash
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Release builds require a configured signing key in `android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword`).
Never commit credentials, tokens, keystores, or build artifacts.

For other platforms:

```bash
flutter run -d macos    # or windows / linux
```

## Project layout

```text
lib/
  core/        models, providers (state), services (API, chat, MCP, storage, network...)
  features/    feature modules: chat, home, provider, model, assistant, mcp, skills,
               instruction_injection, quick_phrase, search, translate, backup,
               scan, settings, stats
  desktop/     desktop app shell: nav rail, tray, hotkeys, title bar, desktop settings
  shared/      reusable UI primitives (iOS-style widgets, dialogs, responsive helpers)
  theme/       theming tokens and dynamic color
  l10n/        ARB localization templates
dependencies/  local path dependencies (mcp_client, gpt_markdown, flutter_tts, ...)
test/          unit and widget tests
```

## Localization

Localization is generated from 4 ARB files that must stay in sync:

- `lib/l10n/app_en.arb`
- `lib/l10n/app_zh.arb`
- `lib/l10n/app_zh_Hans.arb`
- `lib/l10n/app_zh_Hant.arb`

Regenerate after ARB changes:

```bash
flutter gen-l10n
```

## CI

GitHub Actions (`Android Test Release`) runs `flutter analyze`, targeted regression tests,
and builds a signed arm64-v8a APK on every push to `main`. Use the
`workflow_dispatch` with `release_type: formal` to publish a formal (non-prerelease) GitHub Release.

## License

This project is licensed under AGPL-3.0. See [LICENSE](LICENSE).