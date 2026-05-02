import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _markdownHarness(String text, {double? width}) {
  SharedPreferences.setMockInitialValues({});
  return ChangeNotifierProvider(
    create: (_) => SettingsProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: width == null
            ? MarkdownWithCodeHighlight(text: text)
            : Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: MarkdownWithCodeHighlight(text: text),
                ),
              ),
      ),
    ),
  );
}

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

  testWidgets(
    'MarkdownWithCodeHighlight renders details collapsed then expands',
    (tester) async {
      await tester.pumpWidget(
        _markdownHarness('<details><summary>更多信息</summary>隐藏内容</details>'),
      );
      await tester.pump();

      expect(find.text('更多信息'), findsOneWidget);
      expect(find.text('隐藏内容', findRichText: true), findsNothing);

      await tester.tap(find.text('更多信息'));
      await tester.pumpAndSettle();

      expect(find.text('隐藏内容', findRichText: true), findsOneWidget);

      await tester.tap(find.text('更多信息'));
      await tester.pumpAndSettle();

      expect(find.text('隐藏内容', findRichText: true), findsNothing);
    },
  );

  testWidgets('MarkdownWithCodeHighlight renders basic inline HTML tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      _markdownHarness(
        '<p>第一段<br>第二行</p><p><a href="https://example.com">链接</a></p>',
      ),
    );
    await tester.pump();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainText = richTexts.map((w) => w.text.toPlainText()).join('\n');

    expect(plainText, contains('第一段\n第二行'));
    expect(plainText, isNot(contains('<p>')));
    expect(plainText, isNot(contains('<br>')));
    expect(plainText, isNot(contains('<a href=')));
    expect(find.text('链接'), findsOneWidget);
  });

  testWidgets('MarkdownWithCodeHighlight keeps p tag spacing compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _markdownHarness('''
<p>这是一个 HTML 段落。</p>

<p>同一个 HTML 段落里的第一行<br>这里应该换到第二行。</p>
'''),
    );
    await tester.pump();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainText = richTexts.map((w) => w.text.toPlainText()).join('\n');

    expect(plainText, contains('这是一个 HTML 段落。\n\n同一个 HTML 段落里的第一行'));
    expect(plainText, isNot(contains('这是一个 HTML 段落。\n\n\n同一个 HTML 段落里的第一行')));
  });

  testWidgets('MarkdownWithCodeHighlight keeps p to markdown spacing compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _markdownHarness('''
<p>同一个 HTML 段落里的第一行<br>这里应该换到第二行。</p>

这里是普通 Markdown 链接：[Kelivo GitHub](https://github.com/kelivo/Kelivo)
'''),
    );
    await tester.pump();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainText = richTexts.map((w) => w.text.toPlainText()).join('\n');

    expect(plainText, contains('这里应该换到第二行。\n\n这里是普通 Markdown 链接'));
    expect(plainText, isNot(contains('这里应该换到第二行。\n\n\n这里是普通 Markdown 链接')));
  });

  testWidgets('MarkdownWithCodeHighlight animates details collapse', (
    tester,
  ) async {
    await tester.pumpWidget(
      _markdownHarness('<details><summary>更多信息</summary>隐藏内容</details>'),
    );
    await tester.pump();

    expect(find.text('隐藏内容', findRichText: true), findsNothing);

    await tester.tap(find.text('更多信息'));
    await tester.pumpAndSettle();

    expect(find.text('隐藏内容', findRichText: true), findsOneWidget);

    await tester.tap(find.text('更多信息'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('隐藏内容', findRichText: true), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('隐藏内容', findRichText: true), findsNothing);
  });

  testWidgets('MarkdownWithCodeHighlight stretches short details body', (
    tester,
  ) async {
    await tester.pumpWidget(
      _markdownHarness(
        '<details open><summary>短内容</summary>短</details>',
        width: 360,
      ),
    );
    await tester.pump();

    final expandedSize = tester.getSize(
      find.byKey(const ValueKey('details-expanded')),
    );

    expect(expandedSize.width, closeTo(360, 2));
  });

  testWidgets(
    'MarkdownWithCodeHighlight keeps full details around code blocks',
    (tester) async {
      await tester.pumpWidget(
        _markdownHarness('''
这里是 HTML 链接：<a href="https://example.com">Example HTML link</a>

<details>
<summary>点击展开：次要信息</summary>

这里是折叠内容的第一段。

- details 内的 Markdown 列表
- details 内的 **加粗文本**

```dart
void main() {
  print('code block inside details');
}
```
</details>

<details open>
<summary>默认展开：open 属性</summary>

这一块带有 `open` 属性，初始状态应该直接展开。
</details>
'''),
      );
      await tester.pump();

      expect(find.text('Example HTML link'), findsOneWidget);
      expect(find.text('点击展开：次要信息'), findsOneWidget);
      expect(find.text('默认展开：open 属性'), findsOneWidget);
      expect(find.text('这一块带有 ', findRichText: true), findsNothing);
      expect(find.text('这里是折叠内容的第一段。', findRichText: true), findsNothing);

      await tester.tap(find.text('点击展开：次要信息'));
      await tester.pumpAndSettle();

      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final plainText = richTexts.map((w) => w.text.toPlainText()).join('\n');

      expect(plainText, contains('这里是折叠内容的第一段。'));
      expect(plainText, contains('details 内的 Markdown 列表'));
      expect(
        find.textContaining("print('code block inside details');"),
        findsOneWidget,
      );
      expect(plainText, isNot(contains('<details>')));
      expect(plainText, isNot(contains('<a href=')));
    },
  );
}
