from pathlib import Path

path = Path('lib/features/model/widgets/model_select_sheet.dart')
source = path.read_text(encoding='utf-8')


def once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, got {count}')
    source = source.replace(old, new, 1)


if 'class _ProviderGroupHeaderRow extends _ListRow' not in source:
    once(
        """    final l10n = AppLocalizations.of(context)!;
    final query = _search.text.trim();
    // Build flattened rows and index maps for precise positioning
""",
        """    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final providerGroupById = {
      for (final group in settings.providerGroups) group.id: group,
    };
    final query = _search.text.trim();

    String groupKeyFor(String providerKey) {
      final groupId = settings.groupIdForProvider(providerKey);
      if (groupId != null && providerGroupById.containsKey(groupId)) {
        return groupId;
      }
      return SettingsProvider.providerUngroupedGroupKey;
    }

    String groupTitleFor(String groupKey) {
      if (groupKey == SettingsProvider.providerUngroupedGroupKey) {
        return l10n.providerGroupsOther;
      }
      return providerGroupById[groupKey]?.name ?? l10n.providerGroupsOther;
    }

    // Build flattened rows and index maps for precise positioning
""",
        'mobile build content header',
    )

    once(
        'final pinned = context.watch<SettingsProvider>().pinnedModels;',
        'final pinned = settings.pinnedModels;',
        'mobile pinned settings reuse',
    )

    mobile_start = source.index(
        '    for (final pk in _orderedKeys) {',
        source.index('Widget _buildContent'),
    )
    mobile_end = source.index('\n\n    if (_rows.isEmpty)', mobile_start)
    mobile_block = '''    final groupProviderCounts = <String, int>{};
    for (final providerKey in _orderedKeys) {
      if (!_groups.containsKey(providerKey)) continue;
      final groupKey = groupKeyFor(providerKey);
      groupProviderCounts[groupKey] = (groupProviderCounts[groupKey] ?? 0) + 1;
    }

    String? lastGroupKey;
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
      final groupKey = groupKeyFor(pk);
      if (widget.limitProviderKey == null && groupKey != lastGroupKey) {
        final collapsed = query.isEmpty && settings.isGroupCollapsed(groupKey);
        _headerIndexMap[groupKey] = _rows.length;
        _rows.add(
          _ProviderGroupHeaderRow(
            groupKey: groupKey,
            title: groupTitleFor(groupKey),
            count: groupProviderCounts[groupKey] ?? 0,
            collapsed: collapsed,
            canToggleCollapse: query.isEmpty,
          ),
        );
        lastGroupKey = groupKey;
        if (collapsed) continue;
      } else if (widget.limitProviderKey == null &&
          query.isEmpty &&
          settings.isGroupCollapsed(groupKey)) {
        continue;
      }
      _headerIndexMap[pk] = _rows.length;
      _rows.add(_HeaderRow(g.name, providerKey: pk));
      for (final m in items) {
        _modelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
        _rows.add(_ModelRow(m));
      }
    }'''
    source = source[:mobile_start] + mobile_block + source[mobile_end:]

    once(
        """                if (row is _HeaderRow) {
                  return _sectionHeader(
""",
        """                if (row is _ProviderGroupHeaderRow) {
                  return _providerGroupHeader(context, row);
                } else if (row is _HeaderRow) {
                  return _sectionHeader(
""",
        'mobile row renderer',
    )

    once(
        """    if (row is _HeaderRow) return row.providerKey;
    if (row is _ModelRow && !row.showProviderLabel) return row.item.providerKey;
""",
        """    if (row is _HeaderRow) return row.providerKey;
    if (row is _ModelRow) return row.item.providerKey;
""",
        'active provider row mapping',
    )

    once(
        """      extent += row is _HeaderRow
          ? _estimatedHeaderExtent
          : _estimatedModelExtent;
""",
        """      extent += row is _HeaderRow || row is _ProviderGroupHeaderRow
          ? _estimatedHeaderExtent
          : _estimatedModelExtent;
""",
        'remaining extent estimate',
    )

    current_fallback_old = """      targetIndex ??= _headerIndexMap[pk];
"""
    current_fallback_new = """      final rawGroupKey = settings.groupIdForProvider(pk);
      final groupKey = rawGroupKey != null && settings.groupById(rawGroupKey) != null
          ? rawGroupKey
          : SettingsProvider.providerUngroupedGroupKey;
      targetIndex ??= _headerIndexMap[pk] ?? _headerIndexMap[groupKey];
"""
    count = source.count(current_fallback_old)
    if count != 2:
        raise SystemExit(f'current fallback: expected 2 matches, got {count}')
    source = source.replace(current_fallback_old, current_fallback_new)

    mobile_header_widget = '''  Widget _providerGroupHeader(
    BuildContext context,
    _ProviderGroupHeaderRow row,
  ) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.onSurface.withValues(alpha: 0.78);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: row.canToggleCollapse
          ? () => unawaited(
                context
                    .read<SettingsProvider>()
                    .toggleGroupCollapsed(row.groupKey),
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: row.collapsed ? 0.0 : 0.25,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                Lucide.ChevronRight,
                size: 17,
                color: base.withValues(alpha: row.canToggleCollapse ? 0.9 : 0.45),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.emphasis,
                  color: base,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${row.count}',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 11,
                  fontWeight: AppFontWeights.emphasis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
    once(
        '  Widget _sectionHeader(\n',
        mobile_header_widget + '  Widget _sectionHeader(\n',
        'mobile group header widget',
    )

    once(
        """class _HeaderRow extends _ListRow {
  final String title;
  final String? providerKey;
  final bool isFavorites;
  _HeaderRow(this.title, {this.providerKey, this.isFavorites = false});
}
""",
        """class _ProviderGroupHeaderRow extends _ListRow {
  final String groupKey;
  final String title;
  final int count;
  final bool collapsed;
  final bool canToggleCollapse;

  _ProviderGroupHeaderRow({
    required this.groupKey,
    required this.title,
    required this.count,
    required this.collapsed,
    required this.canToggleCollapse,
  });
}

class _HeaderRow extends _ListRow {
  final String title;
  final String? providerKey;
  final bool isFavorites;
  _HeaderRow(this.title, {this.providerKey, this.isFavorites = false});
}
""",
        'group row class',
    )

    once(
        """    final query = _searchCtrl.text.trim();
    _rows.clear();
""",
        """    final query = _searchCtrl.text.trim();
    final providerGroupById = {
      for (final group in settings.providerGroups) group.id: group,
    };

    String groupKeyFor(String providerKey) {
      final groupId = settings.groupIdForProvider(providerKey);
      if (groupId != null && providerGroupById.containsKey(groupId)) {
        return groupId;
      }
      return SettingsProvider.providerUngroupedGroupKey;
    }

    String groupTitleFor(String groupKey) {
      if (groupKey == SettingsProvider.providerUngroupedGroupKey) {
        return l10n.providerGroupsOther;
      }
      return providerGroupById[groupKey]?.name ?? l10n.providerGroupsOther;
    }

    _rows.clear();
""",
        'desktop rebuild header',
    )

    desktop_start = source.index(
        '    for (final pk in _orderedKeys) {',
        source.index('void _rebuildRows()'),
    )
    desktop_end = source.index('\n  }\n\n  @override', desktop_start)
    desktop_block = '''    final groupProviderCounts = <String, int>{};
    for (final providerKey in _orderedKeys) {
      if (!_groups.containsKey(providerKey)) continue;
      final groupKey = groupKeyFor(providerKey);
      groupProviderCounts[groupKey] = (groupProviderCounts[groupKey] ?? 0) + 1;
    }

    String? lastGroupKey;
    for (final pk in _orderedKeys) {
      final g = _groups[pk];
      if (g == null) continue;
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
      final groupKey = groupKeyFor(pk);
      if (widget.limitProviderKey == null && groupKey != lastGroupKey) {
        final collapsed = query.isEmpty && settings.isGroupCollapsed(groupKey);
        _headerIndexMap[groupKey] = _rows.length;
        _rows.add(
          _ProviderGroupHeaderRow(
            groupKey: groupKey,
            title: groupTitleFor(groupKey),
            count: groupProviderCounts[groupKey] ?? 0,
            collapsed: collapsed,
            canToggleCollapse: query.isEmpty,
          ),
        );
        lastGroupKey = groupKey;
        if (collapsed) continue;
      } else if (widget.limitProviderKey == null &&
          query.isEmpty &&
          settings.isGroupCollapsed(groupKey)) {
        continue;
      }
      // When limiting to a single provider, hide the provider header (and its settings button)
      if (widget.limitProviderKey == null) {
        _headerIndexMap[pk] = _rows.length;
        _rows.add(_HeaderRow(g.name, providerKey: pk));
      }
      for (final m in items) {
        _modelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
        _rows.add(_ModelRow(m));
      }
    }'''
    source = source[:desktop_start] + desktop_block + source[desktop_end:]

    once(
        """        if (row is _HeaderRow) {
          if (row.isFavorites) {
""",
        """        if (row is _ProviderGroupHeaderRow) {
          return _providerGroupHeader(context, row);
        } else if (row is _HeaderRow) {
          if (row.isFavorites) {
""",
        'desktop row renderer',
    )

    desktop_header_widget = '''  Widget _providerGroupHeader(
    BuildContext context,
    _ProviderGroupHeaderRow row,
  ) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.onSurface.withValues(alpha: 0.76);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: row.canToggleCollapse
          ? () => unawaited(
                context
                    .read<SettingsProvider>()
                    .toggleGroupCollapsed(row.groupKey),
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 4),
        child: Row(
          children: [
            AnimatedRotation(
              turns: row.collapsed ? 0.0 : 0.25,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                Lucide.ChevronRight,
                size: 14,
                color: base.withValues(alpha: row.canToggleCollapse ? 0.9 : 0.45),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.emphasis,
                  color: base,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${row.count}',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 10.5,
                  fontWeight: AppFontWeights.emphasis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
    once(
        '  Widget _favoritesHeader(BuildContext context, String title) {\n',
        desktop_header_widget + '  Widget _favoritesHeader(BuildContext context, String title) {\n',
        'desktop group header widget',
    )

path.write_text(source, encoding='utf-8')
print('model selector source patched')
