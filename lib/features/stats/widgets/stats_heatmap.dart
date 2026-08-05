import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../models/stats_models.dart';

class StatsHeatmap extends StatelessWidget {
  const StatsHeatmap({super.key, required this.days});

  final List<StatsHeatmapDay> days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.isEmpty) return const SizedBox(height: 220);
    final maxValue = sorted.fold<int>(0, (max, day) => math.max(max, day.count));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240,
          child: CustomPaint(
            key: const ValueKey('stats-bezier-heatmap'),
            painter: _BezierHeatmapPainter(
              days: sorted,
              maxValue: maxValue,
              colorScheme: Theme.of(context).colorScheme,
              isDark: Theme.of(context).brightness == Brightness.dark,
              localeName: Localizations.localeOf(context).toLanguageTag(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(l10n.statsPageHeatmapLess, style: _legendStyle(context)),
            const SizedBox(width: 8),
            _LegendDot(color: Theme.of(context).colorScheme.primary.withValues(alpha: .22)),
            _LegendDot(color: Theme.of(context).colorScheme.primary.withValues(alpha: .52)),
            _LegendDot(color: Theme.of(context).colorScheme.primary.withValues(alpha: .9)),
            const SizedBox(width: 5),
            Text(l10n.statsPageHeatmapMore, style: _legendStyle(context)),
          ],
        ),
      ],
    );
  }

  TextStyle _legendStyle(BuildContext context) => TextStyle(
    fontSize: 11,
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .56),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
  );
}

class _BezierHeatmapPainter extends CustomPainter {
  _BezierHeatmapPainter({required this.days, required this.maxValue, required this.colorScheme, required this.isDark, required this.localeName});
  final List<StatsHeatmapDay> days;
  final int maxValue;
  final ColorScheme colorScheme;
  final bool isDark;
  final String localeName;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0, top = 14.0, right = 10.0, bottom = 32.0;
    final chart = Rect.fromLTWH(left, top, math.max(1, size.width - left - right), size.height - top - bottom);
    final base = chart.bottom;
    final peak = math.max(1, maxValue);
    final values = [for (final day in days) day.count.toDouble()];
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? chart.center.dx : chart.left + chart.width * i / (values.length - 1);
      final y = base - chart.height * values[i] / peak;
      points.add(Offset(x, y));
    }

    final gridPaint = Paint()..color = colorScheme.onSurface.withValues(alpha: isDark ? .12 : .10)..strokeWidth = 1;
    final labelStyle = TextStyle(fontSize: 10, color: colorScheme.onSurface.withValues(alpha: .55));
    for (var i = 0; i <= 4; i++) {
      final y = base - chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _text(canvas, _formatValue(peak * i / 4), Offset(0, y - 7), labelStyle, width: left - 6, align: TextAlign.right);
    }

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1], current = points[i];
      final dx = (current.dx - previous.dx) / 2;
      line.cubicTo(previous.dx + dx, previous.dy, current.dx - dx, current.dy, current.dx, current.dy);
    }
    final area = Path.from(line)..lineTo(points.last.dx, base)..lineTo(points.first.dx, base)..close();
    canvas.drawPath(area, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [colorScheme.primary.withValues(alpha: isDark ? .34 : .22), colorScheme.primary.withValues(alpha: .025)]).createShader(chart));

    final dotPaint = Paint()..color = colorScheme.primary.withValues(alpha: isDark ? .38 : .24);
    for (var x = chart.left; x <= chart.right; x += 9) {
      for (var y = chart.top; y <= base; y += 9) {
        if (area.contains(Offset(x, y))) canvas.drawCircle(Offset(x, y), 1.25, dotPaint);
      }
    }
    canvas.drawPath(line, Paint()..color = colorScheme.primary..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    for (final point in points) canvas.drawCircle(point, 3, Paint()..color = colorScheme.primary);

    final formatter = DateFormat.MMMd(localeName);
    final labelIndexes = _labelIndexes(points.length);
    for (final index in labelIndexes) {
      final date = days[index].date;
      _text(canvas, formatter.format(date), Offset(points[index].dx - 24, base + 9), labelStyle, width: 48, align: TextAlign.center);
    }
  }

  List<int> _labelIndexes(int count) {
    if (count <= 1) return [0];
    final step = math.max(1, (count - 1) ~/ 4);
    final indexes = <int>{0, count - 1};
    for (var i = step; i < count - 1; i += step) indexes.add(i);
    return indexes.toList()..sort();
  }

  String _formatValue(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    return value.round().toString();
  }

  void _text(Canvas canvas, String text, Offset offset, TextStyle style, {required double width, required TextAlign align}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textAlign: align)..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BezierHeatmapPainter old) => old.days != days || old.maxValue != maxValue || old.colorScheme != colorScheme || old.isDark != isDark || old.localeName != localeName;
}