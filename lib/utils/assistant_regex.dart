import '../core/models/assistant.dart';
import '../core/models/assistant_regex.dart';

String applyAssistantRegexes(
  String input, {
  required Assistant? assistant,
  required AssistantRegexScope scope,
  required bool visual,
}) {
  if (input.isEmpty) return input;
  if (assistant == null) return input;
  if (assistant.regexRules.isEmpty) return input;

  String out = input;
  for (final rule in assistant.regexRules) {
    if (!rule.enabled) continue;
    if (rule.visualOnly != visual) continue;
    if (!rule.scopes.contains(scope)) continue;
    final pattern = rule.pattern.trim();
    if (pattern.isEmpty) continue;
    try {
      final regex = RegExp(pattern);
      out = out.replaceAllMapped(regex, (match) {
        return _expandReplacement(rule.replacement, match);
      });
    } catch (_) {
      // Ignore invalid regex patterns
    }
  }
  return out;
}

/// Expands replacement string with capture group references ($0, $1, $2, etc.)
String _expandReplacement(String replacement, Match match) {
  // Pattern to match $0, $1, $2, ... $99
  final refPattern = RegExp(r'\$(\d{1,2})');
  return replacement.replaceAllMapped(refPattern, (m) {
    final groupIndex = int.parse(m.group(1)!);
    if (groupIndex <= match.groupCount) {
      return match.group(groupIndex) ?? '';
    }
    // Return original reference if group doesn't exist
    return m.group(0)!;
  });
}
