import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'model_detail_sheet.dart';
import '../../provider/pages/provider_detail_page.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/provider_grouping_logic.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/model_tag_wrap.dart';
import '../../provider/widgets/provider_avatar.dart';
import '../../provider/widgets/provider_balance_badge.dart';
import '../../../core/services/model_override_resolver.dart';
import '../../../theme/app_font_weights.dart';

class ModelSelection {
  final String providerKey;
  final String modelId;
  ModelSelection(this.providerKey, this.modelId);
}

// Prevent re-entrant model selector dialogs
bool _modelSelectorOpen = false;

// Data class for compute function
class _ModelProcessingData {
  final Map<String, dynamic> providerConfigs;
  final Set<String> pinnedModels;
  final String currentModelKey;
  final List<String> providersOrder;
  final String? limitProviderKey;
  final bool disableResolverPlatformLogging;

  _ModelProcessingData({
    required this.providerConfigs,
    required this.pinnedModels,
    required this.currentModelKey,
    required this.providersOrder,
    this.limitProviderKey,
    required this.disableResolverPlatformLogging,
  });
}

class _ModelProcessingResult {
  final Map<String, _ProviderGroup> groups;
  final List<_ModelItem> favItems;
  final List<String> orderedKeys;

  _ModelProcessingResult({
    required this.groups,
    required this.favItems,
    required this.orderedKeys,
  });
}

// Lightweight brand asset resolver usable in isolates
String? _assetForNameStatic(String n) {
  return BrandAssets.assetForName(n);
}

List<String> _buildDisplayProvidersOrder(
  SettingsProvider settings,
  Iterable<String> providerKeys,
) {
  final knownKeys = providerKeys.where((e) => e.trim().isNotEmpty);
  final providerGroupMap = <String, String>{};
  for (final key in knownKeys) {
    final groupId = settings.groupIdForProvider(key);
    if (groupId != null) providerGroupMap[key] = groupId;
  }
  return buildProviderKeysInGroupedDisplayOrder(
    providersOrder: settings.providersOrder,
    groups: settings.providerGroups,
    ungroupedIndex: settings.providerUngroupedDisplayIndex,
    providerGroupMap: providerGroupMap,
    knownProviderKeys: providerKeys,
  );
}

// Static function for compute - must be top-level
_ModelProcessingResult _processModelsInBackground(_ModelProcessingData data) {
  if (data.disableResolverPlatformLogging) {
    ModelOverrideResolver.setPlatformLoggingEnabled(false);
    ModelOverrideResolver.setUnknownValueLoggingEnabled(false);
  }
  final providers = data.limitProviderKey == null
      ? data.providerConfigs
      : {
          if (data.providerConfigs.containsKey(data.limitProviderKey))
            data.limitProviderKey!:
                data.providerConfigs[data.limitProviderKey]!,
        };

  // Build data map: providerKey -> (displayName, models)
  final Map<String, _ProviderGroup> groups = {};

  providers.forEach((key, cfg) {
    // Skip disabled providers entirely so they can't be selected
    if (!(cfg['enabled'] as bool)) return;
    final models = cfg['models'] as List<dynamic>? ?? [];
    if (models.isEmpty) return;

    final name = (cfg['name'] as String?) ?? '';
    final overrides =
        (cfg['overrides'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
        const <String, dynamic>{};
    final list = <_ModelItem>[
      for (final id in models)
        () {
          final String mid = id.toString();
          final rawOv = overrides[mid];
          final Map<String, dynamic>? ov = rawOv is Map
              ? {for (final e in rawOv.entries) e.key.toString(): e.value}
              : null;
          // Use upstream/api model id for inference when available so that
          // brand assets and default capabilities stay accurate even when the
          // logical key is a custom alias.
          String baseId = mid;
          if (ov != null) {
            final raw = (ov['apiModelId'] ?? ov['api_model_id'])
                ?.toString()
                .trim();
            if (raw != null && raw.isNotEmpty) baseId = raw;
          }
          ModelInfo base = ModelRegistry.infer(
            ModelInfo(id: baseId, displayName: baseId),
          );
          if (ov != null) {
            base = ModelOverrideResolver.applyModelOverride(
              base,
              ov,
              applyDisplayName: true,
            );
          }
          return _ModelItem(
            providerKey: key,
            providerName: name.isNotEmpty ? name : key,
            id: mid,
            info: base,
            pinned: data.pinnedModels.contains('$key::$mid'),
            selected: data.currentModelKey == '$key::$mid',
            asset: _assetForNameStatic(baseId),
          );
        }(),
    ];
    groups[key] = _ProviderGroup(
      name: name.isNotEmpty ? name : key,
      items: list,
    );
  });

  // Build favorites group (duplicate items)
  final favItems = <_ModelItem>[];
  for (final k in data.pinnedModels) {
    final parts = k.split('::');
    if (parts.length < 2) continue;
    final pk = parts[0];
    final mid = parts.sublist(1).join('::');
    final g = groups[pk];
    if (g == null) continue;
    final found = g.items.firstWhere(
      (e) => e.id == mid,
      orElse: () => _ModelItem(
        providerKey: pk,
        providerName: g.name,
        id: mid,
        info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
        pinned: true,
        selected: data.currentModelKey == '$pk::$mid',
      ),
    );
    favItems.add(found.copyWith(pinned: true));
  }

  // Provider sections ordered by ProvidersPage order
  final orderedKeys = <String>[];
  for (final k in data.providersOrder) {
    if (groups.containsKey(k)) orderedKeys.add(k);
  }
  for (final k in groups.keys) {
    if (!orderedKeys.contains(k)) orderedKeys.add(k);
  }

  return _ModelProcessingResult(
    groups: groups,
    favItems: favItems,
    orderedKeys: orderedKeys,
  );
}

Future<ModelSelection?> showModelSelector(
  BuildContext context, {
  String? limitProviderKey,
  String? initialProviderKey,
  String? initialModelId,
}) async {
  if (_modelSelectorOpen) return null;
  _modelSelectorOpen = true;
  try {
    final cs = Theme.of(context).colorScheme;
    return await showModalBottomSheet<ModelSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ModelSelectSheet(
        limitProviderKey: limitProviderKey,
        initialProviderKey: initialProviderKey,
        initialModelId: initialModelId,
      ),
    );
  } finally {
    _modelSelectorOpen = false;
  }
}

Future<void> showModelSelectSheet(
  BuildContext context, {
  bool updateAssistant = true,
}) async {
  final assistantProvider = context.read<AssistantProvider>();
  final settings = context.read<SettingsProvider>();
  final sel = await showModelSelector(context);
  if (sel != null) {
    if (updateAssistant) {
      // Update assistant's model instead of global default
      final assistant = assistantProvider.currentAssistant;
      if (assistant != null) {
        await assistantProvider.updateAssistant(
          assistant.copyWith(
            chatModelProvider: sel.providerKey,
            chatModelId: sel.modelId,
          ),
        );
      }
    } else {
      // Only update global default when explicitly requested (e.g., from settings)
      await settings.setCurrentModel(sel.providerKey, sel.modelId);
    }
  }
}

class _ModelSelectSheet extends StatefulWidget {
  const _ModelSelectSheet({
    this.limitProviderKey,
    this.initialProviderKey,
    this.initialModelId,
  });
  final String? limitProviderKey;
  final String? initialProviderKey;
  final String? initialModelId;
  @override
  State<_ModelSelectSheet> createState() => _ModelSelectSheetState();
}

class _ModelSelectSheetState extends State<_ModelSelectSheet> {
  final TextEditingController _search = TextEditingController();
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();
  final ScrollController _providerTabsController = ScrollController();
  final GlobalKey _providerTabsViewportKey = GlobalKey(
    debugLabel: 'model-selector-provider-tabs-viewport',
  );
  final Map<String, GlobalKey> _providerTabKeys = <String, GlobalKey>{};
  static const double _initialSize = 0.8;
  static const double _maxSize = 0.8;
  static const double _stickyProviderHeaderHeight = 30;
  static const double _estimatedHeaderExtent = 39;
  static const double _estimatedModelExtent = 79;
  static const double _listBottomPadding = 12;
  String _lastQuery = '';
  String? _activeProviderKey;
  int _stickySwitchDirection = 1;
  bool _activeProviderUpdateScheduled = false;
  double _listViewportHeight = 0;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  final List<_ListRow> _rows = <_ListRow>[];
  final Map<String, int> _headerIndexMap =
      <String, int>{}; // providerKey or '__fav__' -> index
  final Map<String, int> _modelIndexMap =
      <String, int>{}; // 'pk::modelId' in provider sections -> index
  final Map<String, int> _favModelIndexMap =
      <String, int>{}; // 'pk::modelId' in favorites -> index

  bool _isLoading = true;
  Map<String, _ProviderGroup> _groups = {};
  List<String> _orderedKeys = [];
  bool _autoScrolled = false;

  dynamic _sanitizeJsonValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _sanitizeJsonValue(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _sanitizeJsonValue(item)];
    }
    return value.toString();
  }

  Map<String, dynamic> _sanitizeOverrides(Map<String, dynamic> overrides) {
    return {
      for (final entry in overrides.entries)
        entry.key.toString(): _sanitizeJsonValue(entry.value),
    };
  }

  Map<String, dynamic> _buildProviderConfigsPayload(SettingsProvider settings) {
    final keys = <String>{
      ...settings.providersOrder.where((e) => e.trim().isNotEmpty),
      ...settings.providerConfigs.keys.where((e) => e.trim().isNotEmpty),
    };
    if (widget.limitProviderKey != null &&
        widget.limitProviderKey!.trim().isNotEmpty) {
      keys.add(widget.limitProviderKey!);
    }
    final out = <String, dynamic>{};
    for (final key in keys) {
      final cfg = settings.getProviderConfig(key, defaultName: key);
      out[key] = {
        'enabled': cfg.enabled,
        'name': cfg.name,
        'models': cfg.models,
        'overrides': _sanitizeOverrides(cfg.modelOverrides),
      };
    }
    return out;
  }

  String _currentModelKey(
    SettingsProvider settings,
    AssistantProvider assistantProvider,
  ) {
    final hasInitial =
        widget.initialProviderKey != null && widget.initialModelId != null;
    final provider = hasInitial
        ? widget.initialProviderKey
        : assistantProvider.currentAssistant?.chatModelProvider ??
              settings.currentModelProvider;
    final modelId = hasInitial
        ? widget.initialModelId
        : assistantProvider.currentAssistant?.chatModelId ??
              settings.currentModelId;
    return (provider != null && modelId != null) ? '$provider::$modelId' : '';
  }

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(
      _scheduleActiveProviderUpdate,
    );
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _loadModelsAsync();
      }
    });
  }

  Future<void> _loadModelsAsync() async {
    try {
      final settings = context.read<SettingsProvider>();
      final assistantProvider = context.read<AssistantProvider>();
      final providerConfigs = _buildProviderConfigsPayload(settings);
      final currentKey = _currentModelKey(settings, assistantProvider);
      final processingData = _ModelProcessingData(
        providerConfigs: providerConfigs,
        pinnedModels: settings.pinnedModels,
        currentModelKey: currentKey,
        providersOrder: _buildDisplayProvidersOrder(
          settings,
          providerConfigs.keys,
        ),
        limitProviderKey: widget.limitProviderKey,
        disableResolverPlatformLogging: true,
      );
      final result = await compute(_processModelsInBackground, processingData);
      if (mounted) {
        setState(() {
          _groups = result.groups;
          _orderedKeys = result.orderedKeys;
          _isLoading = false;
          _activeProviderKey = null;
        });
        _scheduleAutoScrollToCurrent();
      }
    } catch (e) {
      if (mounted) {
        _loadModelsSynchronously();
      }
    }
  }

  Future<void> _expandSheetIfNeeded(
    double target, {
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    try {
      final current = _sheetCtrl.size;
      if (current < target) {
        await _sheetCtrl.animateTo(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {}
  }

  void _loadModelsSynchronously() {
    final settings = context.read<SettingsProvider>();
    final assistantProvider = context.read<AssistantProvider>();
    final providerConfigs = _buildProviderConfigsPayload(settings);
    final currentKey = _currentModelKey(settings, assistantProvider);
    final processingData = _ModelProcessingData(
      providerConfigs: providerConfigs,
      pinnedModels: settings.pinnedModels,
      currentModelKey: currentKey,
      providersOrder: _buildDisplayProvidersOrder(
        settings,
        providerConfigs.keys,
      ),
      limitProviderKey: widget.limitProviderKey,
      disableResolverPlatformLogging: false,
    );
    final result = _processModelsInBackground(processingData);
    setState(() {
      _groups = result.groups;
      _orderedKeys = result.orderedKeys;
      _isLoading = false;
      _activeProviderKey = null;
    });
    _scheduleAutoScrollToCurrent();
  }

  void _scheduleAutoScrollToCurrent() {
    if (_autoScrolled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _autoScrolled) return;
      await _jumpToCurrentSelection();
    });
  }

  Future<void> _jumpToCurrentSelection() async {
    final currentQuery = _search.text.trim();
    if (currentQuery.isNotEmpty) {
      await _scrollToFirstSearchGroup(initial: true);
      return;
    }
    await _expandSheetIfNeeded(
      _initialSize.clamp(0.0, _maxSize),
      duration: const Duration(milliseconds: 200),
    );
    if (!_itemScrollController.isAttached) {
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && !_autoScrolled) {
          _jumpToCurrentSelection();
        }
      });
      return;
    }
    final targetIndex = _currentSelectionTargetIndex();
    if (targetIndex != null) {
      final alignment = _currentSelectionScrollAlignment(targetIndex);
      try {
        await _itemScrollController.scrollTo(
          index: targetIndex,
          alignment: alignment,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
        _autoScrolled = true;
      } catch (_) {
        Future.delayed(const Duration(milliseconds: 80), () async {
          if (!mounted || _autoScrolled) return;
          try {
            await _itemScrollController.scrollTo(
              index: targetIndex,
              alignment: alignment,
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
            );
            _autoScrolled = true;
          } catch (_) {}
        });
      }
    }
  }

  int? _currentSelectionTargetIndex() {
    if (_search.text.trim().isNotEmpty) return null;
    final settings = context.read<SettingsProvider>();
    final currentKey = _currentModelKey(
      settings,
      context.read<AssistantProvider>(),
    );
    if (currentKey.isEmpty) return null;
    if (widget.limitProviderKey == null &&
        settings.pinnedModels.contains(currentKey)) {
      final favIndex = _favModelIndexMap[currentKey];
      if (favIndex != null) return favIndex;
    }
    final separator = currentKey.indexOf('::');
    final pk = separator == -1
        ? currentKey
        : currentKey.substring(0, separator);
    return _modelIndexMap[currentKey] ?? _headerIndexMap[pk];
  }

  double _currentSelectionScrollAlignment(int targetIndex) {
    if (_listViewportHeight <= 0) {
      return 0;
    }
    final topAlignment = widget.limitProviderKey == null
        ? (_stickyProviderHeaderHeight / _listViewportHeight).clamp(0.0, 0.3)
        : 0.0;
    if (_rows.length <= 1) return topAlignment;
    final remainingExtent = _estimatedRemainingExtentFrom(targetIndex);
    final topAlignedRequiredExtent = _listViewportHeight * (1 - topAlignment);
    if (remainingExtent >= topAlignedRequiredExtent) return topAlignment;
    final tailAlignment = 1.0 - (remainingExtent / _listViewportHeight);
    return tailAlignment.clamp(topAlignment, 0.72);
  }

  double _estimatedRemainingExtentFrom(int targetIndex) {
    var extent = _listBottomPadding;
    for (var i = targetIndex; i < _rows.length; i++) {
      final row = _rows[i];
      extent += row is _HeaderRow
          ? _estimatedHeaderExtent
          : _estimatedModelExtent;
    }
    return extent;
  }

  Future<void> _scrollToFirstSearchGroup({bool initial = false}) async {
    await _expandSheetIfNeeded(
      _initialSize.clamp(0.0, _maxSize),
      duration: const Duration(milliseconds: 200),
    );
    if (!_itemScrollController.isAttached) {
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted) {
          _scrollToFirstSearchGroup(initial: initial);
        }
      });
      return;
    }
    int? targetIndex;
    targetIndex = _headerIndexMap['__fav__'];
    if (targetIndex == null) {
      for (final pk in _orderedKeys) {
        final idx = _headerIndexMap[pk];
        if (idx != null) {
          targetIndex = idx;
          break;
        }
      }
    }
    if (targetIndex == null) return;
    try {
      await _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      if (initial) _autoScrolled = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(
      _scheduleActiveProviderUpdate,
    );
    _search.dispose();
    _sheetCtrl.dispose();
    _providerTabsController.dispose();
    super.dispose();
  }

  bool _matchesSearch(String query, _ModelItem item, String providerName) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return item.id.toLowerCase().contains(q) ||
        item.info.displayName.toLowerCase().contains(q);
  }

  bool _providerMatchesSearch(String query, String providerName) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    final lowerProviderName = providerName.toLowerCase();
    return lowerProviderName.contains(lowerQuery);
  }

  GlobalKey _providerTabKeyFor(String providerKey) {
    return _providerTabKeys.putIfAbsent(
      providerKey,
      () => GlobalKey(debugLabel: 'model-selector-provider-tab-$providerKey'),
    );
  }

  String? _providerKeyForRow(int index) {
    if (index < 0 || index >= _rows.length) return null;
    final row = _rows[index];
    if (row is _HeaderRow) return row.providerKey;
    if (row is _ModelRow && !row.showProviderLabel) return row.item.providerKey;
    return null;
  }

  String? _activeProviderKeyFromVisibleRows() {
    final positions =
        _itemPositionsListener.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (positions.isEmpty || _rows.isEmpty) return null;
    final topIndex = positions.first.index;
    final directKey = _providerKeyForRow(topIndex);
    if (directKey != null) return directKey;
    for (var i = topIndex - 1; i >= 0; i--) {
      final key = _providerKeyForRow(i);
      if (key != null) return key;
    }
    return null;
  }

  void _scheduleActiveProviderUpdate() {
    if (!mounted || _activeProviderUpdateScheduled) return;
    _activeProviderUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeProviderUpdateScheduled = false;
      if (mounted) _syncActiveProviderFromVisibleRows();
    });
  }

  void _syncActiveProviderFromVisibleRows() {
    if (widget.limitProviderKey != null || _rows.isEmpty) return;
    final nextKey = _activeProviderKeyFromVisibleRows();
    if (nextKey == _activeProviderKey) return;
    final previousKey = _activeProviderKey;
    final previousIndex = previousKey == null
        ? -1
        : _orderedKeys.indexOf(previousKey);
    final nextIndex = nextKey == null ? -1 : _orderedKeys.indexOf(nextKey);
    setState(() {
      if (previousIndex != -1 && nextIndex != -1) {
        _stickySwitchDirection = nextIndex >= previousIndex ? 1 : -1;
      }
      _activeProviderKey = nextKey;
    });
    if (nextKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollProviderTabIntoView(nextKey);
      });
    }
  }

  void _scrollProviderTabIntoView(String providerKey) {
    final tabContext = _providerTabKeys[providerKey]?.currentContext;
    final viewportContext = _providerTabsViewportKey.currentContext;
    if (!mounted ||
        tabContext == null ||
        viewportContext == null ||
        !_providerTabsController.hasClients) {
      return;
    }
    final tabBox = tabContext.findRenderObject();
    final viewportBox = viewportContext.findRenderObject();
    if (tabBox is! RenderBox || viewportBox is! RenderBox) return;
    final tabLeft = tabBox.localToGlobal(Offset.zero).dx;
    final tabRight = tabLeft + tabBox.size.width;
    final viewportLeft = viewportBox.localToGlobal(Offset.zero).dx;
    final viewportRight = viewportLeft + viewportBox.size.width;
    var targetOffset = _providerTabsController.offset;
    if (tabLeft < viewportLeft) {
      targetOffset += tabLeft - viewportLeft;
    } else if (tabRight > viewportRight) {
      targetOffset += tabRight - viewportRight;
    } else {
      return;
    }
    targetOffset = targetOffset.clamp(
      _providerTabsController.position.minScrollExtent,
      _providerTabsController.position.maxScrollExtent,
    );
    unawaited(
      _providerTabsController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          controller: _sheetCtrl,
          expand: false,
          initialChildSize: _initialSize,
          maxChildSize: _maxSize,
          minChildSize: 0.4,
          builder: (c, controller) {
            return Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _search,
                          enabled: !_isLoading,
                          onChanged: (_) {
                            final q = _search.text.trim();
                            final enteringSearch =
                                _lastQuery.isEmpty && q.isNotEmpty;
                            setState(() {});
                            if (enteringSearch) {
                              WidgetsBinding.instance.addPostFrameCallback((
                                _,
                              ) async {
                                if (!mounted) return;
                                await _scrollToFirstSearchGroup();
                              });
                            }
                            _lastQuery = q;
                          },
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                          ),
                          cursorColor: cs.primary,
                          decoration: InputDecoration(
                            hintText: l10n.modelSelectSheetSearchHint,
                            prefixIcon: Icon(
                              Lucide.Search,
                              size: 18,
                              color: cs.onSurface.withValues(
                                alpha: _isLoading ? 0.35 : 0.6,
                              ),
                            ),
                            suffixIcon:
                                (widget.limitProviderKey == null &&
                                    context
                                        .watch<SettingsProvider>()
                                        .pinnedModels
                                        .isNotEmpty)
                                ? ExcludeSemantics(
                                    child: IconButton(
                                      icon: Icon(
                                        Lucide.Bookmark,
                                        size: 18,
                                        color: cs.onSurface.withValues(
                                          alpha: _isLoading ? 0.35 : 0.7,
                                        ),
                                      ),
                                      onPressed: _isLoading
                                          ? null
                                          : _jumpToFavorites,
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      hoverColor: Colors.transparent,
                                      tooltip:
                                          l10n.modelSelectSheetFavoritesSection,
                                    ),
                                  )
                                : null,
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            filled: true,
                            fillColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.white.withValues(alpha: 0.64),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: cs.primary.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: cs.surface,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildContent(context),
                  ),
                ),
                Container(color: cs.surface, child: _buildBottomTabs(context)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _search.text.trim();
    _rows.clear();
    _headerIndexMap.clear();
    _modelIndexMap.clear();
    _favModelIndexMap.clear();

    final Set<String> favMatchedKeys = <String>{};

    if (widget.limitProviderKey == null) {
      final pinned = context.watch<SettingsProvider>().pinnedModels;
      if (pinned.isNotEmpty) {
        final favs = <_ModelItem>[];
        for (final k in pinned) {
          final parts = k.split('::');
          if (parts.length < 2) continue;
          final pk = parts[0];
          final mid = parts.sublist(1).join('::');
          final g = _groups[pk];
          if (g == null) continue;
          final found = g.items.firstWhere(
            (e) => e.id == mid,
            orElse: () => _ModelItem(
              providerKey: pk,
              providerName: g.name,
              id: mid,
              info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
              pinned: true,
              selected: false,
            ),
          );
          if (_matchesSearch(query, found, found.providerName)) {
            favs.add(found.copyWith(pinned: true));
            favMatchedKeys.add('$pk::$mid');
          }
        }
        if (favs.isNotEmpty) {
          _headerIndexMap['__fav__'] = _rows.length;
          _rows.add(
            _HeaderRow(
              l10n.modelSelectSheetFavoritesSection,
              isFavorites: true,
            ),
          );
          for (final m in favs) {
            _favModelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
            _rows.add(_ModelRow(m, showProviderLabel: true));
          }
        }
      }
    }

    for (final pk in _orderedKeys) {
      final g = _groups[pk]!;
      List<_ModelItem> items;
      if (query.isEmpty) {
        items = g.items;
      } else {
        final providerMatches = _providerMatchesSearch(query, g.name);
        items = providerMatches
            ? g.items
            : g.items.where((e) => _matchesSearch(query, e, g.name)).toList();
        if (favMatchedKeys.isNotEmpty) {
          items = items
              .where(
                (e) => !favMatchedKeys.contains('${e.providerKey}::${e.id}'),
              )
              .toList();
        }
      }
      if (items.isEmpty) continue;
      _headerIndexMap[pk] = _rows.length;
      _rows.add(_HeaderRow(g.name, providerKey: pk));
      for (final m in items) {
        _modelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
        _rows.add(_ModelRow(m));
      }
    }

    if (_rows.isEmpty) return const SizedBox.shrink();

    _scheduleActiveProviderUpdate();

    return LayoutBuilder(
      builder: (context, constraints) {
        _listViewportHeight = constraints.maxHeight;
        return Stack(
          children: [
            ScrollablePositionedList.builder(
              itemCount: _rows.length,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              padding: const EdgeInsets.only(bottom: 12),
              itemBuilder: (context, index) {
                final row = _rows[index];
                if (row is _HeaderRow) {
                  return _sectionHeader(
                    context,
                    row.title,
                    providerKey: row.providerKey,
                  );
                } else if (row is _ModelRow) {
                  return _modelTile(
                    context,
                    row.item,
                    showProviderLabel: row.showProviderLabel,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            if (widget.limitProviderKey == null)
              Positioned(
                top: -1,
                left: 0,
                right: 0,
                child: ColoredBox(
                  key: const ValueKey('model-selector-top-seam-cover'),
                  color: Theme.of(context).colorScheme.surface,
                  child: const SizedBox(height: 1),
                ),
              ),
            if (_activeProviderKey != null) _stickyProviderHeader(context),
          ],
        );
      },
    );
  }

  Widget _buildBottomTabs(BuildContext context) {
    final List<Widget> providerTabs = <Widget>[];
    if (widget.limitProviderKey == null && !_isLoading) {
      String? selectedProviderKey;
      _groups.forEach((pk, group) {
        if (selectedProviderKey == null && group.items.any((m) => m.selected)) {
          selectedProviderKey = pk;
        }
      });
      _providerTabKeys.removeWhere((key, _) => !_orderedKeys.contains(key));
      for (final k in _orderedKeys) {
        final g = _groups[k];
        if (g != null) {
          providerTabs.add(
            _providerTab(
              context,
              k,
              g.name,
              selected: k == selectedProviderKey,
            ),
          );
        }
      }
    }

    if (providerTabs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 10),
      child: SingleChildScrollView(
        key: _providerTabsViewportKey,
        controller: _providerTabsController,
        scrollDirection: Axis.horizontal,
        child: Row(children: providerTabs),
      ),
    );
  }

  Widget _stickyProviderHeader(BuildContext context) {
    if (widget.limitProviderKey != null) return const SizedBox.shrink();
    final providerKey = _activeProviderKey;
    if (providerKey == null) return const SizedBox.shrink();
    final group = _groups[providerKey];
    if (group == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: -1,
      left: 0,
      right: 0,
      child: DecoratedBox(
        key: const ValueKey('model-selector-sticky-provider'),
        decoration: BoxDecoration(color: cs.surface),
        child: SizedBox(
          height: _stickyProviderHeaderHeight + 1,
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                final isIncoming =
                    child.key == ValueKey('sticky-provider-$providerKey');
                final dy = (isIncoming ? 0.65 : -0.65) * _stickySwitchDirection;
                final offsetAnimation = Tween<Offset>(
                  begin: Offset(0, dy),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              child: Padding(
                key: ValueKey('sticky-provider-$providerKey'),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: AppFontWeights.emphasis,
                          color: cs.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                    ),
                    ProviderBalanceBadge(
                      providerKey: providerKey,
                      displayName: group.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    String? providerKey,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (providerKey != null)
            ProviderBalanceBadge(
              providerKey: providerKey,
              displayName: title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.emphasis,
              ),
              color: cs.primary,
            ),
        ],
      ),
    );
  }

  Widget _modelTile(
    BuildContext context,
    _ModelItem m, {
    bool showProviderLabel = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = m.selected
        ? (isDark
              ? cs.primary.withValues(alpha: 0.12)
              : cs.primary.withValues(alpha: 0.08))
        : cs.surface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: RepaintBoundary(
        child: IosCardPress(
          baseColor: bg,
          borderRadius: BorderRadius.circular(14),
          pressedBlendStrength: 0.10,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () =>
              Navigator.of(context).pop(ModelSelection(m.providerKey, m.id)),
          onLongPress: () async {
            await showModelDetailSheet(
              context,
              providerKey: m.providerKey,
              modelId: m.id,
            );
            if (mounted) {
              _isLoading = true;
              setState(() {});
              await _loadModelsAsync();
            }
          },
          child: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                _BrandAvatar(name: m.id, assetOverride: m.asset, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!showProviderLabel)
                        Text(
                          m.info.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        )
                      else
                        Text.rich(
                          TextSpan(
                            text: m.info.displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.semibold,
                            ),
                            children: [
                              TextSpan(
                                text: ' | ${m.providerName}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      ModelTagWrap(model: m.info),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) {
                    final pinnedNow = context.select<SettingsProvider, bool>(
                      (s) => s.isModelPinned(m.providerKey, m.id),
                    );
                    final icon = pinnedNow
                        ? Icons.favorite
                        : Icons.favorite_border;
                    return Tooltip(
                      message: l10n.modelSelectSheetFavoriteTooltip,
                      child: IosIconButton(
                        icon: icon,
                        size: 20,
                        color: cs.primary,
                        onTap: () =>
                            settings.togglePinModel(m.providerKey, m.id),
                        padding: const EdgeInsets.all(6),
                        minSize: 36,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerTab(
    BuildContext context,
    String key,
    String name, {
    bool selected = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: _providerTabKeyFor(key),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _ProviderChip(
        key: ValueKey('model-selector-provider-tab-$key'),
        avatar: ProviderAvatar(providerKey: key, displayName: name, size: 18),
        label: name,
        selected: selected,
        borderColor: cs.outlineVariant.withValues(alpha: 0.25),
        onTap: () async {
          await _jumpToProvider(key);
        },
        onLongPress: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ProviderDetailPage(keyName: key, displayName: name),
            ),
          );
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _jumpToProvider(String pk) async {
    await _expandSheetIfNeeded(_maxSize);
    final idx = _headerIndexMap[pk];
    if (idx != null) {
      if (!_itemScrollController.isAttached) {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) {
            _jumpToProvider(pk);
          }
        });
        return;
      }
      try {
        await _itemScrollController.scrollTo(
          index: idx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
  }

  Future<void> _jumpToFavorites() async {
    if (widget.limitProviderKey != null) return;
    await _expandSheetIfNeeded(_maxSize);
    if (_search.text.isNotEmpty) {
      setState(() => _search.clear());
      await Future.delayed(const Duration(milliseconds: 150));
    }
    final idx = _headerIndexMap['__fav__'];
    if (idx != null) {
      if (!_itemScrollController.isAttached) {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) _jumpToFavorites();
        });
        return;
      }
      try {
        await _itemScrollController.scrollTo(
          index: idx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
  }
}

class _ProviderChip extends StatefulWidget {
  const _ProviderChip({
    super.key,
    required this.avatar,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.borderColor,
    this.selected = false,
  });
  final Widget avatar;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
  final bool selected;

  @override
  State<_ProviderChip> createState() => _ProviderChipState();
}

class _ProviderChipState extends State<_ProviderChip> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSelected = widget.selected;
    final Color baseBg = isSelected
        ? (isDark
              ? cs.primary.withValues(alpha: 0.08)
              : cs.primary.withValues(alpha: 0.05))
        : cs.surface;
    final Color overlay = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final Color bg = _pressed ? Color.alphaBlend(overlay, baseBg) : baseBg;
    final Color borderColor =
        widget.borderColor ?? cs.outlineVariant.withValues(alpha: 0.25);
    final Color labelColor = cs.onSurface;
    return Semantics(
      label: widget.label,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.avatar,
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.medium,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderGroup {
  final String name;
  final List<_ModelItem> items;
  _ProviderGroup({required this.name, required this.items});
}

class _ModelItem {
  final String providerKey;
  final String providerName;
  final String id;
  final ModelInfo info;
  final bool pinned;
  final bool selected;
  final String? asset;
  _ModelItem({
    required this.providerKey,
    required this.providerName,
    required this.id,
    required this.info,
    this.pinned = false,
    this.selected = false,
    this.asset,
  });
  _ModelItem copyWith({bool? pinned, bool? selected}) => _ModelItem(
    providerKey: providerKey,
    providerName: providerName,
    id: id,
    info: info,
    pinned: pinned ?? this.pinned,
    selected: selected ?? this.selected,
    asset: asset,
  );
}

abstract class _ListRow {}

class _HeaderRow extends _ListRow {
  final String title;
  final String? providerKey;
  final bool isFavorites;
  _HeaderRow(this.title, {this.providerKey, this.isFavorites = false});
}

class _ModelRow extends _ListRow {
  final _ModelItem item;
  final bool showProviderLabel;
  _ModelRow(this.item, {this.showProviderLabel = false});
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20, this.assetOverride});
  final String name;
  final double size;
  final String? assetOverride;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = assetOverride ?? BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint = (dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}
