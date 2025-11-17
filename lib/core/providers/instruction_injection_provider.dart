import 'package:flutter/foundation.dart';

import '../models/instruction_injection.dart';
import '../services/instruction_injection_store.dart';

class InstructionInjectionProvider with ChangeNotifier {
  List<InstructionInjection> _items = const <InstructionInjection>[];
  bool _initialized = false;
  List<String> _activeIds = const <String>[];

  List<InstructionInjection> get items => List<InstructionInjection>.unmodifiable(_items);
  List<String> get activeIds => List<String>.unmodifiable(_activeIds);
  bool isActive(String id) => _activeIds.contains(id);
  List<InstructionInjection> get actives =>
      _items.where((e) => _activeIds.contains(e.id)).toList(growable: false);
  String? get activeId => _activeIds.isEmpty ? null : _activeIds.first;
  InstructionInjection? get active => actives.isEmpty ? null : actives.first;

  Future<void> initialize() async {
    if (_initialized) return;
    await loadAll();
    _initialized = true;
  }

  Future<void> loadAll() async {
    try {
      _items = await InstructionInjectionStore.getAll();
      _activeIds = await InstructionInjectionStore.getActiveIds();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load instruction injections: $e');
      _items = const <InstructionInjection>[];
      _activeIds = const <String>[];
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
    _activeIds = const <String>[];
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

  Future<void> setActiveId(String? id) async {
    if (id == null || id.isEmpty) {
      await setActiveIds(const <String>[]);
      return;
    }
    await setActiveIds(<String>[id]);
  }

  Future<void> setActiveIds(List<String> ids) async {
    _activeIds = ids.toSet().toList(growable: false);
    notifyListeners();
    await InstructionInjectionStore.setActiveIds(_activeIds);
  }

  Future<void> toggleActiveId(String id) async {
    final set = _activeIds.toSet();
    if (set.contains(id)) {
      set.remove(id);
    } else {
      set.add(id);
    }
    await setActiveIds(set.toList(growable: false));
  }

  Future<void> setActive(InstructionInjection? item) => setActiveId(item?.id);
}
