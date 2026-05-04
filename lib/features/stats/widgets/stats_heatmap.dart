import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../models/stats_models.dart';

class StatsHeatmap extends StatelessWidget {
  const StatsHeatmap({super.key, required this.days});

  final List<StatsHeatmapDay> days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final activeCounts =
        days.where((day) => day.count > 0).map((day) => day.count).toList()
          ..sort();
    final q1 = _quantile(activeCounts, 0.25);
    final q2 = _quantile(activeCounts, 0.50);
    final q3 = _quantile(activeCounts, 0.75);

    final weeks = <List<StatsHeatmapDay>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.skip(i).take(7).toList());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final week in weeks) ...[
                Column(
                  children: [
                    for (final day in week)
                      Padding(
                        padding: const EdgeInsets.all(1.5),
                        child: _HeatCell(
                          level: _level(day.count, q1: q1, q2: q2, q3: q3),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(l10n.statsPageHeatmapLess, style: _legendStyle(context)),
            const SizedBox(width: 6),
            for (var level = 0; level <= 4; level++) ...[
              _HeatCell(level: level, size: 10),
              const SizedBox(width: 3),
            ],
            const SizedBox(width: 3),
            Text(l10n.statsPageHeatmapMore, style: _legendStyle(context)),
          ],
        ),
      ],
    );
  }

  TextStyle _legendStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.56));
  }

  int _quantile(List<int> sorted, double p) {
    if (sorted.isEmpty) return 1;
    final index = (sorted.length * p).floor().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  int _level(int count, {required int q1, required int q2, required int q3}) {
    if (count <= 0) return 0;
    if (count <= q1) return 1;
    if (count <= q2) return 2;
    if (count <= q3) return 3;
    return 4;
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.level, this.size = 11});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alpha = switch (level) {
      0 => 0.10,
      1 => 0.25,
      2 => 0.45,
      3 => 0.68,
      _ => 0.92,
    };
    final color = level == 0
        ? cs.surfaceContainerHighest.withValues(alpha: 0.50)
        : cs.primary.withValues(alpha: alpha);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
