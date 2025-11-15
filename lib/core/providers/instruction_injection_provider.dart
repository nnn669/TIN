import 'package:flutter/foundation.dart';

import '../models/instruction_injection.dart';
import '../services/instruction_injection_store.dart';

class InstructionInjectionProvider with ChangeNotifier {
  List<InstructionInjection> _items = const <InstructionInjection>[];
  bool _initialized = false;
  String? _activeId;

  List<InstructionInjection> get items => List<InstructionInjection>.unmodifiable(_items);
  String? get activeId => _activeId;
  InstructionInjection? get active =>
      (_activeId == null) ? null : _items.where((e) => e.id == _activeId).cast<InstructionInjection?>().firstWhere((e) => e != null, orElse: () => null);

  Future<void> initialize() async {
    if (_initialized) return;
    await loadAll();
    _initialized = true;
  }

  Future<void> loadAll() async {
    try {
      _items = await InstructionInjectionStore.getAll();
      _activeId = await InstructionInjectionStore.getActiveId();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load instruction injections: $e');
      _items = const <InstructionInjection>[];
      _activeId = null;
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
    _activeId = null;
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
    _activeId = id;
    notifyListeners();
    await InstructionInjectionStore.setActiveId(id);
  }

  Future<void> setActive(InstructionInjection? item) => setActiveId(item?.id);
}
