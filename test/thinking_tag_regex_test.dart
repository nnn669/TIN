import 'package:flutter_test/flutter_test.dart';

/// Mirrors the regex used across the codebase for extracting inline thinking
/// blocks. Tests both `<think>` and `<thought>` variants.
void main() {
  // Capturing regex (chat_message_widget.dart, message_export_sheet.dart)
  final capturingRe = RegExp(
    r'<(?:think|thought)>([\s\S]*?)(?:</(?:think|thought)>|$)',
    dotAll: true,
  );

  // Stripping regex (mini_map_sheet.dart, mini_map_popover.dart, search service)
  final strippingRe = RegExp(
    r'<(?:think|thought)>[\s\S]*?<\/(?:think|thought)>',
    caseSensitive: false,
  );

  group('Capturing regex', () {
    test('matches <think> block', () {
      const input = '<think>reasoning here</think>answer';
      final match = capturingRe.firstMatch(input);
      expect(match, isNotNull);
      expect(match!.group(1), 'reasoning here');
    });

    test('matches <thought> block', () {
      const input = '<thought>reasoning here</thought>answer';
      final match = capturingRe.firstMatch(input);
      expect(match, isNotNull);
      expect(match!.group(1), 'reasoning here');
    });

    test('matches unclosed <think> (streaming)', () {
      const input = '<think>partial reasoning';
      final match = capturingRe.firstMatch(input);
      expect(match, isNotNull);
      expect(match!.group(1), 'partial reasoning');
    });

    test('matches unclosed <thought> (streaming)', () {
      const input = '<thought>partial reasoning';
      final match = capturingRe.firstMatch(input);
      expect(match, isNotNull);
      expect(match!.group(1), 'partial reasoning');
    });

    test('matches multiline content', () {
      const input = '<thought>line1\nline2\nline3</thought>rest';
      final match = capturingRe.firstMatch(input);
      expect(match, isNotNull);
      expect(match!.group(1), 'line1\nline2\nline3');
    });

    test('no match on plain text', () {
      const input = 'just a normal message';
      expect(capturingRe.hasMatch(input), isFalse);
    });
  });

  group('Stripping regex', () {
    test('strips <think> block', () {
      const input = 'before<think>hidden</think>after';
      expect(input.replaceAll(strippingRe, ''), 'beforeafter');
    });

    test('strips <thought> block', () {
      const input = 'before<thought>hidden</thought>after';
      expect(input.replaceAll(strippingRe, ''), 'beforeafter');
    });

    test('strips multiple blocks', () {
      const input = '<think>a</think>mid<thought>b</thought>end';
      expect(input.replaceAll(strippingRe, ''), 'midend');
    });

    test('no match leaves text unchanged', () {
      const input = 'hello world';
      expect(input.replaceAll(strippingRe, ''), 'hello world');
    });
  });
}
