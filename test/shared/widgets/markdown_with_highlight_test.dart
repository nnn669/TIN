import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SelectableHighlightView 为已注册语言生成高亮 span', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectableHighlightView(
            'final value = 1;',
            language: 'dart',
            theme: {},
          ),
        ),
      ),
    );

    final richText = tester.widget<SelectableText>(find.byType(SelectableText));
    final root = richText.textSpan!;
    final children = root.children ?? const <InlineSpan>[];

    expect(children, isNotEmpty);
    expect(children.length, greaterThan(1));
  });
}
