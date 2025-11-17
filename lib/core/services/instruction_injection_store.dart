import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/instruction_injection.dart';
import 'learning_mode_store.dart';

class InstructionInjectionStore {
  static const String _itemsKey = 'instruction_injections_v1';
  static const String _activeIdKey = 'instruction_injections_active_id_v1';
  static const String _activeIdsKey = 'instruction_injections_active_ids_v1';

  static List<InstructionInjection>? _cache;
  static String? _activeIdCache;
  static List<String>? _activeIdsCache;

  static Future<List<InstructionInjection>> getAll() async {
    if (_cache != null) return List<InstructionInjection>.from(_cache!);
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_itemsKey);
    if (json == null || json.isEmpty) {
      // Seed with a default "Learning Mode" card using existing learning mode prompt/settings.
      final seeded = await _seedDefaultFromLearningMode(prefs);
      _cache = seeded;
      return List<InstructionInjection>.from(seeded);
    }
    try {
      final list = jsonDecode(json) as List;
      _cache = list
          .map((e) => InstructionInjection.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: true);
      return List<InstructionInjection>.from(_cache!);
    } catch (_) {
      _cache = const <InstructionInjection>[];
      return const <InstructionInjection>[];
    }
  }

  static Future<List<InstructionInjection>> _seedDefaultFromLearningMode(SharedPreferences prefs) async {
    // Use existing learning mode prompt and enabled flag to create a default card.
    String prompt;
    bool enabled;
    try {
      prompt = await LearningModeStore.getPrompt();
    } catch (_) {
      prompt = LearningModeStore.defaultPrompt;
    }
    try {
      enabled = await LearningModeStore.isEnabled();
    } catch (_) {
      enabled = false;
    }
    final id = const Uuid().v4();
    final item = InstructionInjection(
      id: id,
      title: '',
      prompt: prompt,
    );
    final list = <InstructionInjection>[item];
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList(growable: false));
    await prefs.setString(_itemsKey, encoded);
    _cache = list;
    if (enabled) {
      _activeIdsCache = <String>[id];
      _activeIdCache = id;
      await prefs.setString(_activeIdKey, id);
      try {
        await prefs.setString(_activeIdsKey, jsonEncode(<String>[id]));
      } catch (_) {}
    }
    return list;
  }

  static Future<void> save(List<InstructionInjection> items) async {
    _cache = List<InstructionInjection>.from(items);
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(items.map((e) => e.toJson()).toList(growable: false));
    await prefs.setString(_itemsKey, json);
  }

  static Future<void> add(InstructionInjection item) async {
    final all = await getAll();
    all.add(item);
    await save(all);
  }

  static Future<void> update(InstructionInjection item) async {
    final all = await getAll();
    final index = all.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      all[index] = item;
      await save(all);
    }
  }

  static Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((e) => e.id == id);
    await save(all);
    final prefs = await SharedPreferences.getInstance();
    if (_activeIdCache == id) {
      _activeIdCache = null;
      await prefs.remove(_activeIdKey);
    }
    // Remove from multi-select cache
    try {
      final ids = await getActiveIds();
      if (ids.contains(id)) {
        final updated = ids.where((e) => e != id).toList(growable: false);
        await setActiveIds(updated);
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cache = const <InstructionInjection>[];
    _activeIdCache = null;
    _activeIdsCache = const <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_itemsKey);
    await prefs.remove(_activeIdKey);
    await prefs.remove(_activeIdsKey);
  }

  static Future<void> reorder({required int oldIndex, required int newIndex}) async {
    final list = await getAll();
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await save(list);
  }

  static Future<String?> getActiveId() async {
    final ids = await getActiveIds();
    if (ids.isEmpty) return null;
    return ids.first;
  }

  static Future<void> setActiveId(String? id) async {
    if (id == null || id.isEmpty) {
      await setActiveIds(const <String>[]);
      return;
    }
    await setActiveIds(<String>[id]);
  }

  static Future<List<String>> getActiveIds() async {
    if (_activeIdsCache != null) return List<String>.from(_activeIdsCache!);
    final prefs = await SharedPreferences.getInstance();
    // Prefer new multi-select key
    final json = prefs.getString(_activeIdsKey);
    if (json != null && json.isNotEmpty) {
      try {
        final list = (jsonDecode(json) as List).map((e) => e.toString()).toList();
        _activeIdsCache = list;
        return List<String>.from(list);
      } catch (_) {
        _activeIdsCache = const <String>[];
      }
    }
    // Fallback to legacy single active id if present
    final legacy = prefs.getString(_activeIdKey);
    if (legacy != null && legacy.isNotEmpty) {
      _activeIdCache = legacy;
      _activeIdsCache = <String>[legacy];
      try {
        await prefs.setString(_activeIdsKey, jsonEncode(_activeIdsCache));
      } catch (_) {}
      return List<String>.from(_activeIdsCache!);
    }
    _activeIdsCache = const <String>[];
    return const <String>[];
  }

  static Future<void> setActiveIds(List<String> ids) async {
    final clean = ids.where((e) => e.trim().isNotEmpty).toSet().toList(growable: false);
    _activeIdsCache = clean;
    final prefs = await SharedPreferences.getInstance();
    if (clean.isEmpty) {
      await prefs.remove(_activeIdKey);
      await prefs.remove(_activeIdsKey);
      return;
    }
    // Persist new multi-select key
    try {
      await prefs.setString(_activeIdsKey, jsonEncode(clean));
    } catch (_) {}
    // Maintain legacy single-id key with the first active id for backward compatibility
    final first = clean.first;
    _activeIdCache = first;
    await prefs.setString(_activeIdKey, first);
  }

  static Future<InstructionInjection?> getActive() async {
    final list = await getActives();
    if (list.isEmpty) return null;
    return list.first;
  }

  static Future<List<InstructionInjection>> getActives() async {
    final ids = await getActiveIds();
    if (ids.isEmpty) return const <InstructionInjection>[];
    final all = await getAll();
    if (all.isEmpty) return const <InstructionInjection>[];
    final map = <String, InstructionInjection>{for (final e in all) e.id: e};
    final result = <InstructionInjection>[];
    for (final id in ids) {
      final item = map[id];
      if (item != null) result.add(item);
    }
    return result;
  }
}
