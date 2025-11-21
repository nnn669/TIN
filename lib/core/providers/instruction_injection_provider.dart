import 'package:flutter/foundation.dart';

import '../models/instruction_injection.dart';
import '../services/instruction_injection_store.dart';

class InstructionInjectionProvider with ChangeNotifier {
  List<InstructionInjection> _items = const <InstructionInjection>[];
  bool _initialized = false;
  Map<String, List<String>> _activeIdsByAssistant = const <String, List<String>>{};

  List<InstructionInjection> get items => List<InstructionInjection>.unmodifiable(_items);
  List<String> get activeIds => activeIdsFor(null);

  List<String> activeIdsFor(String? assistantId) {
    final key = InstructionInjectionStore.assistantKey(assistantId);
    if (_activeIdsByAssistant.containsKey(key)) {
      return List<String>.unmodifiable(_activeIdsByAssistant[key]!);
    }
    final fallback = _activeIdsByAssistant[InstructionInjectionStore.assistantKey(null)] ?? const <String>[];
    return List<String>.unmodifiable(fallback);
  }

  bool isActive(String id, {String? assistantId}) => activeIdsFor(assistantId).contains(id);

  List<InstructionInjection> get actives => activesFor(null);

  List<InstructionInjection> activesFor(String? assistantId) {
    final ids = activeIdsFor(assistantId).toSet();
    return _items.where((e) => ids.contains(e.id)).toList(growable: false);
  }

  String? get activeId => activeIdFor(null);
  String? activeIdFor(String? assistantId) {
    final ids = activeIdsFor(assistantId);
    return ids.isEmpty ? null : ids.first;
  }

  InstructionInjection? get active => activeFor(null);
  InstructionInjection? activeFor(String? assistantId) {
    final list = activesFor(assistantId);
    if (list.isEmpty) return null;
    return list.first;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await loadAll();
    _initialized = true;
  }

  Future<void> loadAll() async {
    try {
      _items = await InstructionInjectionStore.getAll();
      _activeIdsByAssistant = await InstructionInjectionStore.getActiveIdsByAssistant();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load instruction injections: $e');
      _items = const <InstructionInjection>[];
      _activeIdsByAssistant = const <String, List<String>>{};
      notifyListeners();
    }
  }

  Future<void> add(InstructionInjection item) async {
    await InstructionInjectionStore.add(item);
    await loadAll();
  }

  Future<void> update(InstructionInjection item) async {
    await InstructionInjectionStore.update(item);
    await loadAll();
  }

  Future<void> delete(String id) async {
    await InstructionInjectionStore.delete(id);
    await loadAll();
  }

  Future<void> clear() async {
    await InstructionInjectionStore.clear();
    _items = const <InstructionInjection>[];
    _activeIdsByAssistant = const <String, List<String>>{};
    notifyListeners();
  }

  Future<void> reorder({required int oldIndex, required int newIndex}) async {
    if (_items.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    final list = List<InstructionInjection>.from(_items);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _items = list;
    notifyListeners();
    await InstructionInjectionStore.save(_items);
  }

  Future<void> setActiveId(String? id, {String? assistantId}) async {
    if (id == null || id.isEmpty) {
      await setActiveIds(const <String>[], assistantId: assistantId);
      return;
    }
    await setActiveIds(<String>[id], assistantId: assistantId);
  }

  Future<void> setActiveIds(List<String> ids, {String? assistantId}) async {
    final key = InstructionInjectionStore.assistantKey(assistantId);
    final nextMap = Map<String, List<String>>.from(_activeIdsByAssistant);
    nextMap[key] = ids.toSet().toList(growable: false);
    _activeIdsByAssistant = nextMap;
    notifyListeners();
    await InstructionInjectionStore.setActiveIds(ids, assistantId: assistantId);
  }

  Future<void> toggleActiveId(String id, {String? assistantId}) async {
    final set = activeIdsFor(assistantId).toSet();
    if (set.contains(id)) {
      set.remove(id);
    } else {
      set.add(id);
    }
    await setActiveIds(set.toList(growable: false), assistantId: assistantId);
  }

  Future<void> setActive(InstructionInjection? item, {String? assistantId}) =>
      setActiveId(item?.id, assistantId: assistantId);
}
