import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'chat_sidebar_actions.dart';
import 'side_drawer_legacy.dart' as legacy;

class SideDrawer extends StatelessWidget {
  const SideDrawer({
    super.key,
    required this.userName,
    required this.assistantName,
    this.onSelectConversation,
    this.onNewConversation,
    this.closePickerTicker,
    this.loadingConversationIds = const <String>{},
    this.embedded = false,
    this.embeddedWidth,
    this.showBottomBar = true,
    this.useDesktopTabs = false,
    this.desktopAssistantsOnly = false,
    this.desktopTopicsOnly = false,
    this.globalSearchMode = false,
    this.globalSearchQuery = '',
    this.onGlobalSearchQueryChanged,
    this.onEnterGlobalSearch,
    this.onExitGlobalSearch,
    this.onOpenGlobalSearchResult,
  });
  final String userName;
  final String assistantName;
  final FutureOr<void> Function(String id, {bool closeDrawer})?
  onSelectConversation;
  final FutureOr<void> Function({bool closeDrawer})? onNewConversation;
  final ValueNotifier<int>? closePickerTicker;
  final Set<String> loadingConversationIds;
  final bool embedded;
  final double? embeddedWidth;
  final bool showBottomBar;
  final bool useDesktopTabs;
  final bool desktopAssistantsOnly;
  final bool desktopTopicsOnly;
  final bool globalSearchMode;
  final String globalSearchQuery;
  final ValueChanged<String>? onGlobalSearchQueryChanged;
  final VoidCallback? onEnterGlobalSearch;
  final VoidCallback? onExitGlobalSearch;
  final Future<void> Function(String conversationId, String messageId)?
  onOpenGlobalSearchResult;
  @override
  Widget build(BuildContext context) {
    final showActions = showBottomBar && (!embedded || !_isDesktopPlatform);
    return Stack(
      children: [
        Positioned.fill(
          child: legacy.SideDrawer(
            userName: userName,
            assistantName: assistantName,
            onSelectConversation: onSelectConversation,
            onNewConversation: onNewConversation,
            closePickerTicker: closePickerTicker,
            loadingConversationIds: loadingConversationIds,
            embedded: embedded,
            embeddedWidth: embeddedWidth,
            showBottomBar: false,
            useDesktopTabs: useDesktopTabs,
            desktopAssistantsOnly: desktopAssistantsOnly,
            desktopTopicsOnly: desktopTopicsOnly,
            globalSearchMode: globalSearchMode,
            globalSearchQuery: globalSearchQuery,
            onGlobalSearchQueryChanged: onGlobalSearchQueryChanged,
            onEnterGlobalSearch: onEnterGlobalSearch,
            onExitGlobalSearch: onExitGlobalSearch,
            onOpenGlobalSearchResult: onOpenGlobalSearchResult,
          ),
        ),
        if (showActions)
          const Align(
            alignment: Alignment.bottomCenter,
            child: ChatSidebarActions(),
          ),
      ],
    );
  }

  static bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}
