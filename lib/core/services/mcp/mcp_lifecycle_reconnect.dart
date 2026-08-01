import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/mcp_provider.dart';

/// Keeps MCP sessions usable after Android suspends the Flutter isolate while
/// the app is in the background. Android may pause timers and close idle
/// sockets, so a connection that was healthy before backgrounding can be
/// stale when the app becomes visible again.
class McpLifecycleReconnect extends StatefulWidget {
  const McpLifecycleReconnect({super.key, required this.child});

  final Widget child;

  @override
  State<McpLifecycleReconnect> createState() => _McpLifecycleReconnectState();
}

class _McpLifecycleReconnectState extends State<McpLifecycleReconnect>
    with WidgetsBindingObserver {
  McpProvider? _provider;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<McpProvider>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconnectEnabledServers());
    }
  }

  Future<void> _reconnectEnabledServers() async {
    if (_refreshing || !mounted) return;
    final provider = _provider;
    if (provider == null) return;
    _refreshing = true;
    try {
      // Reconnect every enabled server, including built-in @kelivo/github.
      // This intentionally creates a fresh MCP client/session instead of
      // trusting a status that may have become stale while Android paused us.
      final ids = provider.servers
          .where((server) => server.enabled)
          .map((server) => server.id)
          .toList(growable: false);
      for (final id in ids) {
        if (!mounted) return;
        try {
          await provider.disconnect(id);
          await provider.ensureConnected(id);
        } catch (_) {
          // The provider records the connection error and the normal retry
          // path remains available when the next tool call is made.
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}