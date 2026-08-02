import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tin/core/providers/mcp_provider.dart';
import 'package:tin/core/services/mcp/mcp_lifecycle_reconnect.dart';

Future<void> _settleUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTicks = 40,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('keeps live MCP sessions usable after resume', (tester) async {
    final provider = McpProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: McpLifecycleReconnect(child: Text('TIN')),
        ),
      ),
    );

    expect(find.text('TIN'), findsOneWidget);

    // The built-in fetch server is enabled and auto-connects on load.
    await _settleUntil(tester, () => provider.servers.isNotEmpty);
    final fetch = provider.servers.firstWhere((s) => s.name == '@kelivo/fetch');
    await _settleUntil(tester, () => provider.isConnected(fetch.id));
    expect(provider.isConnected(fetch.id), isTrue);

    // Opt-in servers must stay untouched by the resume handler.
    final files = provider.servers.firstWhere((s) => s.name == '@kelivo/files');
    expect(files.enabled, isFalse);
    expect(provider.statusFor(files.id), McpStatus.idle);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // A fresh session replaces the possibly stale one.
    await _settleUntil(tester, () => provider.isConnected(fetch.id));
    expect(provider.isConnected(fetch.id), isTrue);
    expect(provider.statusFor(files.id), McpStatus.idle);
  });
}