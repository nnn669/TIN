import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/reasoning_budget_sheet.dart';
import 'package:Kelivo/features/chat/widgets/thinking_effort_stack.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Future<SettingsProvider> _settingsForClaudeModel(
  WidgetTester tester,
  String modelId,
) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();

  await settings.setProviderConfig(
    'Claude',
    ProviderConfig(
      id: 'Claude',
      enabled: true,
      name: 'Claude',
      apiKey: 'test-key',
      baseUrl: 'https://api.anthropic.com/v1',
      providerType: ProviderKind.claude,
      models: <String>[modelId],
    ),
  );
  await settings.setCurrentModel('Claude', modelId);
  return settings;
}

Future<void> _pumpSheetLauncher(
  WidgetTester tester, {
  required SettingsProvider settings,
  String? modelProvider,
  String? modelId,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AssistantProvider>(
          create: (_) => AssistantProvider(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                key: const ValueKey('open-reasoning-sheet'),
                onPressed: () => showReasoningBudgetSheet(
                  context,
                  modelProvider: modelProvider,
                  modelId: modelId,
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-reasoning-sheet')));
  await tester.pumpAndSettle();
}

Future<void> _tapOption(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ThinkingEffortStack.optionKey(id)));
  await tester.pump(const Duration(milliseconds: 240));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReasoningBudgetSheet (stacked layout)', () {
    testWidgets('renders the five base levels in stacked order', (tester) async {
      final settings = await _settingsForClaudeModel(
        tester,
        'claude-sonnet-4-5',
      );
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: 'claude-sonnet-4-5',
      );

      await _openSheet(tester);

      expect(find.byKey(ThinkingEffortStack.stackKey), findsOneWidget);
      for (final id in const ['off', 'auto', 'light', 'medium', 'heavy']) {
        expect(
          find.byKey(ThinkingEffortStack.optionKey(id)),
          findsOneWidget,
          reason: 'option "$id" should be present',
        );
      }
    });

    testWidgets('tapping a level writes the matching thinkingBudget', (
      tester,
    ) async {
      final settings = await _settingsForClaudeModel(
        tester,
        'claude-sonnet-4-5',
      );
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: 'claude-sonnet-4-5',
      );

      await _openSheet(tester);

      await _tapOption(tester, 'light');
      expect(settings.thinkingBudget, 1024);

      await _tapOption(tester, 'medium');
      expect(settings.thinkingBudget, 16000);

      await _tapOption(tester, 'heavy');
      expect(settings.thinkingBudget, 32000);
    });

    testWidgets('exposes Ultracode and max reasoning for Claude Fable 5', (
      tester,
    ) async {
      const modelId = 'claude-fable-5';
      final settings = await _settingsForClaudeModel(tester, modelId);
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: modelId,
      );

      await _openSheet(tester);

      expect(find.byKey(ThinkingEffortStack.optionKey('max')), findsOneWidget);
      expect(
        find.byKey(ThinkingEffortStack.optionKey('ultracode')),
        findsOneWidget,
      );

      await _tapOption(tester, 'ultracode');
      expect(settings.thinkingBudget, 128000);
      expect(find.text('Ultracode'), findsOneWidget);
    });

    testWidgets('keeps max reasoning hidden for older Claude models', (
      tester,
    ) async {
      final settings = await _settingsForClaudeModel(
        tester,
        'claude-sonnet-4-5',
      );
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: 'claude-sonnet-4-5',
      );

      await _openSheet(tester);

      expect(find.byKey(ThinkingEffortStack.optionKey('max')), findsNothing);
      expect(find.byKey(ThinkingEffortStack.optionKey('xhigh')), findsNothing);
      expect(
        find.byKey(ThinkingEffortStack.optionKey('ultracode')),
        findsNothing,
      );
      expect(find.text('Ultracode'), findsNothing);
    });

    testWidgets('off level maps to budget 0 and closes the sheet', (
      tester,
    ) async {
      final settings = await _settingsForClaudeModel(
        tester,
        'claude-sonnet-4-5',
      );
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: 'claude-sonnet-4-5',
      );

      await _openSheet(tester);
      await _tapOption(tester, 'off');
      await tester.pumpAndSettle();

      expect(settings.thinkingBudget, 0);
      expect(find.byKey(ThinkingEffortStack.stackKey), findsNothing);
    });
  });
}