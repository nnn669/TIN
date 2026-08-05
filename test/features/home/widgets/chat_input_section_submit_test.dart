import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/models/chat_input_data.dart';
import 'package:tin/features/home/widgets/chat_input_section.dart';

void main() {
  test('input text is queued without stopping active generation', () {
    expect(
      defaultShouldStopBeforeSubmit(
        isLoading: true,
        input: const ChatInputData(text: 'follow-up'),
      ),
      isFalse,
    );
  });

  test('empty input still stops active generation', () {
    expect(
      defaultShouldStopBeforeSubmit(
        isLoading: true,
        input: const ChatInputData(text: ''),
      ),
      isTrue,
    );
  });

  test('attachments are also submitted while generation is active', () {
    expect(
      defaultShouldStopBeforeSubmit(
        isLoading: true,
        input: const ChatInputData(
          text: '',
          documents: <DocumentAttachment>[
            DocumentAttachment(
              path: '/tmp/file.txt',
              fileName: 'file.txt',
              mime: 'text/plain',
            ),
          ],
        ),
      ),
      isFalse,
    );
  });
}