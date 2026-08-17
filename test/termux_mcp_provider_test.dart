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
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('registers Termux as an opt-in MCP with approval required', () async {
    final provider = McpProvider();
    addTearDown(() async {
      for (final server in provider.servers) {
        await provider.disconnect(server.id);
      }
      provider.dispose();
    });

    await waitUntil(
      () => provider.servers.any((server) => server.name == '@kelivo/termux'),
    );
    final initial = provider.servers.firstWhere(
      (server) => server.name == '@kelivo/termux',
    );
    expect(initial.enabled, isFalse);
    expect(provider.statusFor(initial.id), McpStatus.idle);

    await provider.updateServer(initial.copyWith(enabled: true));
    await waitUntil(() => provider.isConnected(initial.id));
    final connected = provider.getById(initial.id)!;

    expect(connected.tools.single.name, 'termux_run_command');
    expect(connected.tools.single.needsApproval, isTrue);
  });
}
