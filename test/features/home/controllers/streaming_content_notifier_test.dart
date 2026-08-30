import 'package:flutter_test/flutter_test.dart';
import 'package:tin/features/home/controllers/streaming_content_notifier.dart';

void main() {
  testWidgets(
    'publishes each prepared frame immediately without a second timer',
    (tester) async {
      final streaming = StreamingContentNotifier();
      final notifier = streaming.getNotifier('message');
      final contents = <String>[];
      notifier.addListener(() => contents.add(notifier.value.content));

      streaming.updateContent('message', 'first frame', 2);

      expect(notifier.value.content, 'first frame');
      expect(contents, const ['first frame']);

      await tester.pump(const Duration(milliseconds: 100));
      expect(contents, const ['first frame']);

      streaming.updateContent('message', 'final frame', 3);
      expect(notifier.value.content, 'final frame');
      expect(contents, const ['first frame', 'final frame']);

      streaming.dispose();
    },
  );
}
