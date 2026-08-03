import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/models/assistant.dart';

void main() {
  test('legacy assistant sampling controls are discarded', () {
    final assistant = Assistant.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'temperature': 0.7,
      'topP': 0.9,
    });
    final json = assistant.toJson();
    expect(json.containsKey('temperature'), isFalse);
    expect(json.containsKey('topP'), isFalse);
    expect(Assistant.fromJson(json).name, 'Legacy');
  });
}
