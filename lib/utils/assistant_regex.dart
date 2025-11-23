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
      out = out.replaceAll(RegExp(pattern), rule.replacement);
    } catch (_) {
      // Ignore invalid regex patterns
    }
  }
  return out;
}
