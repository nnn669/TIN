import 'package:flutter_test/flutter_test.dart';
import 'package:tin/features/home/controllers/streaming_content_notifier.dart';

void main() {
  testWidgets('growing stream content is published in frame-sized slices', (
    tester,
  ) async {
    final streaming = StreamingContentNotifier();
    addTearDown(streaming.dispose);
    final notifier = streaming.getNotifier('message');

    streaming.updateContent(
      'message',
      'abcdef',
      12,
      promptTokens: 4,
      completionTokens: 8,
    );

    expect(notifier.value.content, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expect(notifier.value.content, 'a');
    expect(notifier.value.totalTokens, 12);
    expect(notifier.value.promptTokens, 4);
    expect(notifier.value.completionTokens, 8);

    await tester.pump(const Duration(milliseconds: 80));
    expect(notifier.value.content, 'abcdef');
  });

  testWidgets('stream smoothing never exposes half of a surrogate pair', (
    tester,
  ) async {
    final streaming = StreamingContentNotifier();
    final notifier = streaming.getNotifier('emoji');

    streaming.updateContent('emoji', '😀ok', 0);
    await tester.pump(const Duration(milliseconds: 16));

    expect(notifier.value.content, '😀');
    expect(notifier.value.content.codeUnits, <int>[0xD83D, 0xDE00]);
    streaming.dispose();
  });

  testWidgets('non-growing replacements are published immediately', (
    tester,
  ) async {
    final streaming = StreamingContentNotifier();
    addTearDown(streaming.dispose);
    final notifier = streaming.getNotifier('replacement');

    streaming.updateContent('replacement', 'old', 0);
    await tester.pump(const Duration(milliseconds: 48));
    expect(notifier.value.content, 'old');

    streaming.updateContent('replacement', 'new', 0);
    expect(notifier.value.content, 'new');
  });
}