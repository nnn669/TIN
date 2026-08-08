import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tin/features/home/widgets/model_icon.dart';

void main() {
  testWidgets('tapping a model icon shows its upstream model identifier', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CurrentModelIcon(
            providerKey: 'test-provider',
            modelId: 'actual-model-id',
          ),
        ),
      ),
    );

    final icon = find.byTooltip('actual-model-id');
    expect(icon, findsOneWidget);

    await tester.tap(icon);
    await tester.pumpAndSettle();

    expect(find.text('actual-model-id'), findsOneWidget);
  });
}
