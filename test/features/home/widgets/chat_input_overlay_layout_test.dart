import 'package:Kelivo/features/home/widgets/chat_input_overlay_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('底部覆盖层贴住可用区域底部', (tester) async {
    const rootKey = Key('root');
    const contentKey = Key('content');
    const overlayKey = Key('overlay');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: rootKey,
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(key: contentKey, color: Colors.blue),
              bottomOverlay: SizedBox(key: overlayKey, width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 100);
    expect(tester.getBottomLeft(find.byKey(contentKey)).dy, 600);
    expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
  });

  testWidgets('底部覆盖层内的居中包装不会把输入框推到中间', (tester) async {
    const overlayKey = Key('overlay');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: Center(
                child: SizedBox(key: overlayKey, width: 200, height: 50),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
  });
}
