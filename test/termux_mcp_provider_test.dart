import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tin/core/providers/mcp_provider.dart';

Future<void> waitUntil(bool Function() condition) async {
  for (var tick = 0; tick < 100; tick++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition was not reached before timeout');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('connects Termux by default with mandatory approval', () async {
    final provider = McpProvider();
    addTearDown(() => disposeProvider(provider));

    await waitUntil(
      () => provider.servers.any((server) => server.name == '@kelivo/termux'),
    );
    final termux = provider.servers.firstWhere(
      (server) => server.name == '@kelivo/termux',
    );
    await waitUntil(() => provider.isConnected(termux.id));
    final connected = provider.getById(termux.id)!;

    expect(connected.enabled, isTrue);
    expect(connected.tools.single.name, 'termux_run_command');
    expect(connected.tools.single.needsApproval, isTrue);
    expect(
      provider.toolRequiresMandatoryApproval('termux_run_command'),
      isTrue,
    );
  });

  test('enables a previously disabled Termux server once on upgrade', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mcp_servers_v1': jsonEncode([
        {
          'id': McpProvider.builtinTermuxId,
          'enabled': false,
          'name': McpProvider.builtinTermuxName,
          'transport': 'inmemory',
          'tools': <Object>[],
        },
      ]),
    });
    final provider = McpProvider();
    addTearDown(() => disposeProvider(provider));

    await waitUntil(
      () => provider.getById(McpProvider.builtinTermuxId)?.enabled == true,
    );

    expect(provider.getById(McpProvider.builtinTermuxId)?.enabled, isTrue);
  });

  test('respects manual disable after the automatic migration', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mcp_termux_auto_enable_migrated_v1': true,
      'mcp_servers_v1': jsonEncode([
        {
          'id': McpProvider.builtinTermuxId,
          'enabled': false,
          'name': McpProvider.builtinTermuxName,
          'transport': 'inmemory',
          'tools': <Object>[],
        },
      ]),
    });
    final provider = McpProvider();
    addTearDown(() => disposeProvider(provider));

    await waitUntil(() => provider.servers.length >= 5);
    final termux = provider.getById(McpProvider.builtinTermuxId)!;

    expect(termux.enabled, isFalse);
    expect(provider.statusFor(termux.id), McpStatus.idle);
  });
}

Future<void> disposeProvider(McpProvider provider) async {
  for (final server in provider.servers) {
    await provider.disconnect(server.id);
  }
  provider.dispose();
}
