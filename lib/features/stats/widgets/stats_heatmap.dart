import 'dart:math' as math;
import 'dart:ui' as ui;

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

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 250,
          child: CustomPaint(
            key: const ValueKey('stats-bezier-heatmap'),
            painter: _BezierHeatmapPainter(
              days: sorted,
              colorScheme: colorScheme,
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
            _LegendDot(color: colorScheme.primary.withValues(alpha: .22)),
            _LegendDot(color: colorScheme.primary.withValues(alpha: .52)),
            _LegendDot(color: colorScheme.primary.withValues(alpha: .9)),
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
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class _BezierHeatmapPainter extends CustomPainter {
  const _BezierHeatmapPainter({
    required this.days,
    required this.colorScheme,
    required this.isDark,
    required this.localeName,
  });

  final List<StatsHeatmapDay> days;
  final ColorScheme colorScheme;
  final bool isDark;
  final String localeName;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 54.0;
    const top = 20.0;
    const right = 8.0;
    const bottom = 37.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(1, size.width - left - right),
      math.max(1, size.height - top - bottom),
    );
    final baseline = chart.bottom;
    final maxTokens = days.fold<int>(
      0,
      (maximum, day) => math.max(maximum, day.tokens),
    );
    final axisMax = _niceAxisMax(maxTokens);
    final points = _points(chart, axisMax);
    final axisColor = colorScheme.onSurface.withValues(
      alpha: isDark ? .56 : .48,
    );
    final gridColor = colorScheme.onSurface.withValues(
      alpha: isDark ? .15 : .10,
    );
    final labelStyle = TextStyle(
      fontSize: 10,
      color: colorScheme.onSurface.withValues(alpha: .58),
    );

    _drawText(
      canvas,
      'Token',
      const Offset(0, -2),
      TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface.withValues(alpha: .9),
      ),
      width: 80,
      align: TextAlign.left,
    );
    _drawGrid(canvas, chart, axisMax, gridColor, labelStyle);
    _drawAxis(canvas, chart, axisColor);

    final curve = _curve(points);
    final area = Path.from(curve)
      ..lineTo(points.last.dx, baseline)
      ..lineTo(points.first.dx, baseline)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? .36 : .24),
            colorScheme.primary.withValues(alpha: isDark ? .06 : .025),
          ],
        ).createShader(chart),
    );

    _drawDots(canvas, area, chart, isDark);
    canvas.drawPath(
      curve,
      Paint()
        ..color = colorScheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final point in points) {
      canvas.drawCircle(point, 2.8, Paint()..color = colorScheme.primary);
    }
    _drawDateLabels(canvas, chart, baseline, labelStyle);
  }

  List<Offset> _points(Rect chart, double axisMax) {
    if (days.length == 1) {
      return [
        Offset(
          chart.center.dx,
          chart.bottom - chart.height * days.single.tokens / axisMax,
        ),
      ];
    }
    return [
      for (var index = 0; index < days.length; index++)
        Offset(
          chart.left + chart.width * index / (days.length - 1),
          chart.bottom - chart.height * days[index].tokens / axisMax,
        ),
    ];
  }

  Path _curve(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final dx = (current.dx - previous.dx) / 2;
      path.cubicTo(
        previous.dx + dx,
        previous.dy,
        current.dx - dx,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    return path;
  }

  void _drawGrid(
    Canvas canvas,
    Rect chart,
    double axisMax,
    Color gridColor,
    TextStyle labelStyle,
  ) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final y = chart.bottom - chart.height * tick / 4;
      _drawDashedLine(
        canvas,
        Offset(chart.left, y),
        Offset(chart.right, y),
        gridPaint,
      );
      _drawText(
        canvas,
        _formatTokenValue(axisMax * tick / 4),
        Offset(0, y - 7),
        labelStyle,
        width: 48,
        align: TextAlign.right,
      );
    }

    for (final index in _dateLabelIndexes(days.length)) {
      final x = days.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (days.length - 1);
      _drawDashedLine(
        canvas,
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        gridPaint,
      );
    }
  }

  void _drawAxis(Canvas canvas, Rect chart, Color axisColor) {
    final paint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(chart.left, chart.top), chart.bottomLeft, paint);
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, paint);
  }

  void _drawDots(Canvas canvas, Path area, Rect chart, bool dark) {
    final dotPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: dark ? .42 : .27);
    for (var x = chart.left + 4; x <= chart.right; x += 4.5) {
      for (var y = chart.top + 4; y <= chart.bottom; y += 4.5) {
        final point = Offset(x, y);
        if (area.contains(point)) canvas.drawCircle(point, 1.25, dotPaint);
      }
    }
  }

  void _drawDateLabels(
    Canvas canvas,
    Rect chart,
    double baseline,
    TextStyle style,
  ) {
    final formatter = DateFormat.MMMd(localeName);
    for (final index in _dateLabelIndexes(days.length)) {
      final x = days.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (days.length - 1);
      _drawText(
        canvas,
        formatter.format(days[index].date),
        Offset(x - 28, baseline + 10),
        style,
        width: 56,
        align: TextAlign.center,
      );
    }
  }

  List<int> _dateLabelIndexes(int count) {
    if (count <= 1) return [0];
    const labelCount = 6;
    return [
      for (var index = 0; index < labelCount; index++)
        ((count - 1) * index / (labelCount - 1)).round(),
    ];
  }

  double _niceAxisMax(int maximum) {
    if (maximum <= 0) return 1;
    final magnitude = math
        .pow(10, (math.log(maximum) / math.ln10).floor())
        .toDouble();
    final normalized = maximum / magnitude;
    final step = normalized <= 1
        ? 1.0
        : normalized <= 2
        ? 2.0
        : normalized <= 5
        ? 5.0
        : 10.0;
    return step * magnitude;
  }

  String _formatTokenValue(double value) {
    if (value >= 1000000) {
      final millions = value / 1000000;
      return '${millions.toStringAsFixed(millions >= 10 || millions == millions.roundToDouble() ? 0 : 1)}M';
    }
    if (value >= 1000) {
      final thousands = value / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 || thousands == thousands.roundToDouble() ? 0 : 1)}K';
    }
    return value.round().toString();
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final distance = (end - start).distance;
    if (distance == 0) return;
    final direction = (end - start) / distance;
    var drawn = 0.0;
    while (drawn < distance) {
      final next = math.min(drawn + dash, distance);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * next,
        paint,
      );
      drawn = next + gap;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double width,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BezierHeatmapPainter oldDelegate) {
    return oldDelegate.days != days ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.isDark != isDark ||
        oldDelegate.localeName != localeName;
  }
}
