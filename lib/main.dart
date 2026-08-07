import 'dart:async';
import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/assistant_provider.dart';
import 'core/providers/backup_provider.dart';
import 'core/providers/backup_reminder_provider.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/instruction_injection_group_provider.dart';
import 'core/providers/instruction_injection_provider.dart';
import 'core/providers/mcp_provider.dart';
import 'core/providers/memory_provider.dart';
import 'core/providers/quick_phrase_provider.dart';
import 'core/providers/s3_backup_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/skill_provider.dart';
import 'core/providers/tag_provider.dart';
import 'core/providers/tts_provider.dart';
import 'core/providers/update_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/services/android_background.dart';
import 'core/services/chat/chat_service.dart';
import 'core/services/logging/flutter_logger.dart';
import 'core/services/mcp/mcp_tool_service.dart';
import 'core/services/notification_service.dart';
import 'features/home/pages/home_page.dart';
import 'features/home/services/ask_user_interaction_service.dart';
import 'features/home/services/tool_approval_service.dart';
import 'l10n/app_localizations.dart';
import 'shared/widgets/app_overlays.dart';
import 'theme/palettes.dart';
import 'theme/theme_factory.dart';
import 'utils/sandbox_path_resolver.dart';

final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();

Future<void> main() async {
  await runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterLogger.installGlobalHandlers();
      await _restoreFlutterLogState();
      _trimImageCache();
      await SandboxPathResolver.init();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      runApp(const MyApp());
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        FlutterLogger.logPrint(line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _restoreFlutterLogState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await FlutterLogger.setEnabled(
      prefs.getBool('flutter_log_enabled_v1') ?? false,
    );
  } catch (_) {}
}

void _trimImageCache() {
  try {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 200;
    cache.maximumSizeBytes = 48 << 20;
  } catch (_) {}
}

bool get isAndroidPlatform => Platform.isAndroid;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final settings = SettingsProvider();
            unawaited(settings.incrementAppLaunchCount());
            return settings;
          },
        ),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => McpToolService()),
        ChangeNotifierProvider(create: (_) => McpProvider()),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
        ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
        ChangeNotifierProvider(
          create: (ctx) => AssistantProvider(
            chatService: ctx.read<ChatService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => TagProvider()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => QuickPhraseProvider()),
        ChangeNotifierProvider(create: (_) => SkillProvider()),
        ChangeNotifierProvider(create: (_) => InstructionInjectionProvider()),
        ChangeNotifierProvider(create: (_) => InstructionInjectionGroupProvider()),
        ChangeNotifierProvider(create: (_) => MemoryProvider()),
        ChangeNotifierProvider(create: (_) => BackupReminderProvider()),
        ChangeNotifierProvider(
          create: (ctx) => BackupProvider(
            chatService: ctx.read<ChatService>(),
            initialConfig: ctx.read<SettingsProvider>().webDavConfig,
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => S3BackupProvider(
            chatService: ctx.read<ChatService>(),
            initialConfig: ctx.read<SettingsProvider>().s3Config,
          ),
        ),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _didCheckUpdates = false;
  bool _didEnsureLocalizedDefaults = false;
  bool _didSyncAndroidBackground = false;
  bool? _lastDynamicColorSupported;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    settings.applyGlobalProxyOverridesIfNeeded();

    if (settings.showAppUpdates && !_didCheckUpdates) {
      _didCheckUpdates = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          context.read<UpdateProvider>().checkForUpdates();
        } catch (_) {}
      });
    }

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final isAndroid = Theme.of(context).platform == TargetPlatform.android;
        final dynSupported =
            isAndroid && (lightDynamic != null || darkDynamic != null);
        _scheduleDynamicColorCapabilityUpdate(settings, dynSupported);
        _scheduleAndroidBackgroundSync(settings);

        final useDynamicColor = isAndroid && settings.useDynamicColor;
        final palette = ThemePalettes.byId(settings.themePaletteId);
        final themedLight = _applyAppFont(
          buildLightThemeForScheme(
            palette.light,
            dynamicScheme: useDynamicColor ? lightDynamic : null,
            pureBackground: settings.usePureBackground,
          ),
          settings,
        );
        final themedDark = _applyAppFont(
          buildDarkThemeForScheme(
            palette.dark,
            dynamicScheme: useDynamicColor ? darkDynamic : null,
            pureBackground: settings.usePureBackground,
          ),
          settings,
        );
        final effectiveAppFont = _effectiveAppFontFamily(settings);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Kelivo',
          locale: settings.appLocaleForMaterialApp,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: themedLight,
          darkTheme: themedDark,
          themeMode: settings.themeMode,
          navigatorObservers: <NavigatorObserver>[routeObserver],
          home: const HomePage(),
          builder: (ctx, child) {
            _scheduleLocalizedDefaults(ctx);
            final appWithOverlays = AppOverlays(
              child: child ?? const SizedBox.shrink(),
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _overlayStyleFor(Theme.of(ctx).brightness),
              child: effectiveAppFont == null
                  ? appWithOverlays
                  : DefaultTextStyle.merge(
                      style: TextStyle(fontFamily: effectiveAppFont),
                      child: appWithOverlays,
                    ),
            );
          },
        );
      },
    );
  }

  void _scheduleDynamicColorCapabilityUpdate(
    SettingsProvider settings,
    bool supported,
  ) {
    if (_lastDynamicColorSupported == supported) return;
    _lastDynamicColorSupported = supported;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        settings.setDynamicColorSupported(supported);
      } catch (_) {}
    });
  }

  void _scheduleAndroidBackgroundSync(SettingsProvider settings) {
    if (_didSyncAndroidBackground || !isAndroidPlatform) return;
    final mode = settings.androidBackgroundChatMode;
    if (mode == AndroidBackgroundChatMode.off) return;
    _didSyncAndroidBackground = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final l10n = AppLocalizations.of(context);
        if (l10n == null) return;
        final enabled = await AndroidBackgroundManager.isEnabled();
        if (!enabled) {
          await AndroidBackgroundManager.ensureInitialized(
            notificationTitle: l10n.androidBackgroundNotificationTitle,
            notificationText: l10n.androidBackgroundNotificationText,
          );
          await AndroidBackgroundManager.setEnabled(true);
        }
        if (mode == AndroidBackgroundChatMode.onNotify) {
          await NotificationService.ensureInitialized();
          await NotificationService.ensureAndroidNotificationsPermission();
        }
      } catch (_) {}
    });
  }

  void _scheduleLocalizedDefaults(BuildContext ctx) {
    if (_didEnsureLocalizedDefaults) return;
    _didEnsureLocalizedDefaults = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(ctx);
      if (l10n == null) return;
      try {
        ctx.read<AssistantProvider>().ensureDefaults(ctx);
      } catch (_) {}
      try {
        ctx.read<ChatService>().setDefaultConversationTitle(
              l10n.chatServiceDefaultConversationTitle,
            );
      } catch (_) {}
      try {
        ctx.read<UserProvider>().setDefaultNameIfUnset(
              l10n.userProviderDefaultUserName,
            );
      } catch (_) {}
    });
  }

  ThemeData _applyAppFont(ThemeData base, SettingsProvider settings) {
    final effectiveAppFont = _effectiveAppFontFamily(settings);
    if (effectiveAppFont == null || effectiveAppFont.isEmpty) return base;

    TextStyle? withFamily(TextStyle? style) =>
        style?.copyWith(fontFamily: effectiveAppFont);
    TextTheme apply(TextTheme theme) => theme.copyWith(
          displayLarge: withFamily(theme.displayLarge),
          displayMedium: withFamily(theme.displayMedium),
          displaySmall: withFamily(theme.displaySmall),
          headlineLarge: withFamily(theme.headlineLarge),
          headlineMedium: withFamily(theme.headlineMedium),
          headlineSmall: withFamily(theme.headlineSmall),
          titleLarge: withFamily(theme.titleLarge),
          titleMedium: withFamily(theme.titleMedium),
          titleSmall: withFamily(theme.titleSmall),
          bodyLarge: withFamily(theme.bodyLarge),
          bodyMedium: withFamily(theme.bodyMedium),
          bodySmall: withFamily(theme.bodySmall),
          labelLarge: withFamily(theme.labelLarge),
          labelMedium: withFamily(theme.labelMedium),
          labelSmall: withFamily(theme.labelSmall),
        );

    final appBar = base.appBarTheme.copyWith(
      titleTextStyle: (base.appBarTheme.titleTextStyle ?? const TextStyle())
          .copyWith(fontFamily: effectiveAppFont),
      toolbarTextStyle: (base.appBarTheme.toolbarTextStyle ?? const TextStyle())
          .copyWith(fontFamily: effectiveAppFont),
    );
    return base.copyWith(
      textTheme: apply(base.textTheme),
      primaryTextTheme: apply(base.primaryTextTheme),
      appBarTheme: appBar,
    );
  }

  String? _effectiveAppFontFamily(SettingsProvider settings) {
    final family = settings.appFontFamily;
    if (family == null || family.isEmpty) return null;
    if (!settings.appFontIsGoogle) return family;
    try {
      return GoogleFonts.getFont(family).fontFamily ?? family;
    } catch (_) {
      return family;
    }
  }

  SystemUiOverlayStyle _overlayStyleFor(Brightness brightness) {
    return brightness == Brightness.dark
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          );
  }
}
