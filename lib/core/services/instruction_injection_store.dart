import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/instruction_injection.dart';
import 'learning_mode_store.dart';

class InstructionInjectionStore {
  static const String _itemsKey = 'instruction_injections_v1';
  static const String _activeIdKey = 'instruction_injections_active_id_v1';

  static List<InstructionInjection>? _cache;
  static String? _activeIdCache;

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
      _activeIdCache = id;
      await prefs.setString(_activeIdKey, id);
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
  }

  static Future<void> clear() async {
    _cache = const <InstructionInjection>[];
    _activeIdCache = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_itemsKey);
    await prefs.remove(_activeIdKey);
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
    if (_activeIdCache != null) return _activeIdCache;
    final prefs = await SharedPreferences.getInstance();
    _activeIdCache = prefs.getString(_activeIdKey);
    return _activeIdCache;
  }

  static Future<void> setActiveId(String? id) async {
    _activeIdCache = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove(_activeIdKey);
    } else {
      await prefs.setString(_activeIdKey, id);
    }
  }

  static Future<InstructionInjection?> getActive() async {
    final id = await getActiveId();
    if (id == null || id.isEmpty) return null;
    final all = await getAll();
    try {
      return all.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }
}
