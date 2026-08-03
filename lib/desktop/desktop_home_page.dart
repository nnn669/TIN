import 'package:flutter/material.dart';
import 'package:tin/theme/app_font_weights.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'desktop_nav_rail.dart';
import 'desktop_chat_page.dart';
import 'window_title_bar.dart';
import 'desktop_settings_page.dart';
import '../features/stats/pages/stats_page.dart';
import '../features/settings/pages/storage_space_page.dart';
import '../l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'hotkeys/hotkey_event_bus.dart';
import 'hotkeys/chat_action_bus.dart';
import 'desktop_settings_navigation_bus.dart';

/// Desktop home screen: left compact rail + main content.
class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({
    super.key,
    this.initialTabIndex,
    this.initialProviderKey,
  });

  final int? initialTabIndex; // 0=Chat,1=Stats,2=Storage,3=Settings
  final String? initialProviderKey;

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  int _tabIndex = 0; // 0=Chat, 1=Stats, 2=Storage, 3=Settings
  bool _storageVisited = false;
  bool _globalSearchActive = false;
  StreamSubscription<HotkeyAction>? _hotkeySub;
  StreamSubscription<ChatAction>? _chatActionSub;
  StreamSubscription<DesktopSettingsNavigationTarget>? _settingsNavSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialTabIndex != null) {
      _tabIndex = widget.initialTabIndex!.clamp(0, 3);
    }
    _storageVisited = _tabIndex == 2;
    if (_tabIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ChatActionBus.instance.fire(ChatAction.focusInput);
      });
    }
    _hotkeySub = HotkeyEventBus.instance.stream.listen((action) async {
      switch (action) {
        case HotkeyAction.openSettings:
          if (mounted) {
            setState(() {
              _tabIndex = 3;
              _globalSearchActive = false;
            });
            ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
          }
          break;
        case HotkeyAction.closeWindow:
          try {
            await windowManager.close();
          } catch (_) {}
          break;
        case HotkeyAction.toggleAppVisibility:
          try {
            final visible = await windowManager.isVisible();
            final minimized = await windowManager.isMinimized();
            final focused = await windowManager.isFocused();
            if (!visible || minimized) {
              await windowManager.show();
              await windowManager.focus();
              if (_tabIndex == 0) {
                ChatActionBus.instance.fire(ChatAction.focusInput);
              }
            } else if (!focused) {
              await windowManager.focus();
              if (_tabIndex == 0) {
                ChatActionBus.instance.fire(ChatAction.focusInput);
              }
            } else {
              await windowManager.hide();
            }
          } catch (_) {}
          break;
        case HotkeyAction.newTopic:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.newTopic);
          }
          break;
        case HotkeyAction.switchModel:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.switchModel);
          }
          break;
        case HotkeyAction.toggleLeftPanelAssistants:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.toggleLeftPanelAssistants);
          }
          break;
        case HotkeyAction.toggleLeftPanelTopics:
          if (_tabIndex == 0) {
            ChatActionBus.instance.fire(ChatAction.toggleLeftPanelTopics);
          }
          break;
      }
    });

    _chatActionSub = ChatActionBus.instance.stream.listen((action) {
      if (!mounted) return;
      switch (action) {
        case ChatAction.enterGlobalSearch:
          setState(() {
            _tabIndex = 0;
            _globalSearchActive = true;
          });
          break;
        case ChatAction.exitGlobalSearch:
          setState(() {
            _globalSearchActive = false;
          });
          break;
        default:
          break;
      }
    });
    _settingsNavSub = DesktopSettingsNavigationBus.instance.stream.listen((
      target,
    ) {
      if (!mounted) return;
      switch (target) {
        case DesktopSettingsNavigationTarget.backup:
          setState(() {
            _tabIndex = 3;
            _globalSearchActive = false;
          });
          ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const minWidth = 960.0;
    const minHeight = 640.0;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final needsWidthPad = w < minWidth;
        final needsHeightPad = h < minHeight;

        Widget body = Row(
          children: [
            DesktopNavRail(
              activeIndex: _tabIndex,
              globalSearchActive: _globalSearchActive,
              onTapChat: () {
                setState(() {
                  _tabIndex = 0;
                  _globalSearchActive = false;
                });
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
                ChatActionBus.instance.fire(ChatAction.focusInput);
              },
              onTapGlobalSearch: () {
                setState(() {
                  _tabIndex = 0;
                  _globalSearchActive = true;
                });
                ChatActionBus.instance.fire(ChatAction.enterGlobalSearch);
              },
              onTapStats: () {
                setState(() {
                  _tabIndex = 1;
                  _globalSearchActive = false;
                });
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
              },
              onTapStorage: () => setState(() {
                _tabIndex = 2;
                _globalSearchActive = false;
                _storageVisited = true;
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
              }),
              onTapSettings: () {
                setState(() {
                  _tabIndex = 3;
                  _globalSearchActive = false;
                });
                ChatActionBus.instance.fire(ChatAction.exitGlobalSearch);
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  const DesktopChatPage(),
                  const StatsPage(
                    key: ValueKey('stats_page'),
                    showAppBar: false,
                  ),
                  _storageVisited
                      ? const StorageSpacePage(
                          key: ValueKey('storage_space_page'),
                          embedded: true,
                        )
                      : const SizedBox.shrink(),
                  DesktopSettingsPage(
                    key: const ValueKey('settings_page'),
                    initialProviderKey: widget.initialProviderKey,
                  ),
                ],
              ),
            ),
          ],
        );

        final content = isWindows
            ? Column(
                children: [
                  WindowTitleBar(
                    leftChildren: [
                      SizedBox(width: DesktopNavRail.width / 2 - 8 - 6 - 12),
                      const _TitleBarLeading(),
                    ],
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        body,
                        if (_tabIndex == 3) const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              )
            : body;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: minWidth,
              minHeight: minHeight,
            ),
            child: SizedBox(
              width: needsWidthPad ? minWidth : w,
              height: needsHeightPad ? minHeight : h,
              child: content,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    try {
      _hotkeySub?.cancel();
    } catch (_) {}
    try {
      _chatActionSub?.cancel();
    } catch (_) {}
    try {
      _settingsNavSub?.cancel();
    } catch (_) {}
    super.dispose();
  }
}

class _TitleBarLeading extends StatelessWidget {
  const _TitleBarLeading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icons/kelivo.png',
          width: 16,
          height: 16,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(width: 8),
        Text(
          l10n.aboutPageAppName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.8),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}