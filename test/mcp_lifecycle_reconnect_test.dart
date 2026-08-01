import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tin/core/providers/mcp_provider.dart';
import 'package:tin/core/services/mcp/mcp_lifecycle_reconnect.dart';

void main() {
  testWidgets('mounts above the app and observes lifecycle changes', (tester) async {
    final provider = McpProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const McpLifecycleReconnect(child: Text('TIN')),
      ),
    );

    expect(find.text('TIN'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}