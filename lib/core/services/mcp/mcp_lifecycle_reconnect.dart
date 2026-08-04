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
    try {
      _provider = context.read<McpProvider>();
    } on ProviderNotFoundException {
      // App-level overlays are also used by lightweight surfaces and tests
      // that do not provide MCP. Reconnect is simply disabled for those trees.
      _provider = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStaleSessions());
    }
  }

  Future<void> _refreshStaleSessions() async {
    if (_refreshing || !mounted) return;
    final provider = _provider;
    if (provider == null) return;
    _refreshing = true;
    try {
      // Only sessions that were already live (or already failed) can be stale.
      // Servers left idle on purpose - such as the opt-in @kelivo/files server
      // that is skipped during auto-connect - must stay untouched here.
      final ids = provider.servers
          .where((server) => server.enabled)
          .map((server) => server.id)
          .where((id) {
            final status = provider.statusFor(id);
            return status == McpStatus.connected || status == McpStatus.error;
          })
          .toList(growable: false);
      for (final id in ids) {
        if (!mounted) return;
        // A tool call started before backgrounding may still be streaming.
        // Dropping its transport would turn a slow call into a failed call.
        if (_hasRunningCall(provider, id)) continue;
        try {
          // Drop the possibly dead transport first: ensureConnected() trusts
          // isConnected(), which still reports true for a stale session.
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

  bool _hasRunningCall(McpProvider provider, String serverId) {
    for (final entry in provider.callLogs) {
      if (entry.serverId == serverId &&
          entry.status == McpCallLogStatus.running) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}