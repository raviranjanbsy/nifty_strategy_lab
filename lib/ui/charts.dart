import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';

const seriesColors = [
  Color(0xFF1F6FEB),
  Color(0xFF2FBF71),
  Color(0xFFE36209),
  Color(0xFF8250DF),
  Color(0xFFD6443D),
  Color(0xFF6E7781),
  Color(0xFFBF8700),
];

class LineSeries {
  const LineSeries(this.label, this.values, this.color, {this.width = 1.8, this.faint = false, this.showInLegend = true});

  final String label;
  final List<double> values;
  final Color color;
  final double width;
  final bool faint;
  final bool showInLegend;
}

/// Cumulative sum starting at 0 (an equity curve from daily P&L).
List<double> cumulative(List<double> daily) {
  var s = 0.0;
  return [0.0, for (final x in daily) s += x];
}

/// Equity-style line chart with a zero line, rupee axis and date labels. [xLabels] has one label per point.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.series, required this.xLabels, this.height = 300});

  final List<LineSeries> series;
  final List<String> xLabels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final legend = [for (final s in series) if (s.showInLegend) s];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(series, xLabels, Theme.of(context))),
      ),
      if (legend.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 6, children: [
          for (final s in legend)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 4, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Flexible(child: Text(s.label, style: Theme.of(context).textTheme.bodySmall)),
            ]),
        ]),
      ],
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.series, this.xLabels, this.theme);

  final List<LineSeries> series;
  final List<String> xLabels;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final cs = theme.colorScheme;
    final labelStyle = TextStyle(color: cs.onSurfaceVariant, fontSize: 11);
    var lo = 0.0, hi = 0.0;
    var n = 0;
    for (final s in series) {
      for (final v in s.values) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      n = math.max(n, s.values.length);
    }
    if (hi - lo < 1) hi = lo + 1;
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    const left = 60.0, right = 10.0, top = 8.0, bottom = 24.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    double x(int i) => left + w * (n <= 1 ? 0 : i / (n - 1));
    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - right, y(v)), grid);
      _text(canvas, inrCompact(v), Offset(left - 6, y(v)), labelStyle, alignRight: true);
    }
    final zero = Paint()
      ..color = cs.onSurfaceVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    _dashed(canvas, Offset(left, y(0)), Offset(size.width - right, y(0)), zero);

    if (xLabels.isNotEmpty) {
      final ticks = math.min(6, xLabels.length);
      for (var k = 0; k < ticks; k++) {
        final i = ticks == 1 ? 0 : ((xLabels.length - 1) * k / (ticks - 1)).round();
        _text(canvas, xLabels[i], Offset(x(i), size.height - bottom + 6), labelStyle, center: true);
      }
    }

    for (final s in [...series.where((s) => s.faint), ...series.where((s) => !s.faint)]) {
      if (s.values.length < 2) continue;
      final p = Path()..moveTo(x(0), y(s.values[0]));
      for (var i = 1; i < s.values.length; i++) {
        p.lineTo(x(i), y(s.values[i]));
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = s.faint ? s.color.withValues(alpha: 0.35) : s.color
            ..strokeWidth = s.width
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.series != series || old.theme != theme;
}

class Candles {
  const Candles(this.open, this.high, this.low, this.close, this.minutes);

  final List<double> open, high, low, close;
  final List<int> minutes; // bar start
}

class ChartMarker {
  const ChartMarker(this.index, this.price, this.color, this.label, {this.up = true});

  final int index;
  final double price;
  final Color color;
  final String label;
  final bool up;
}

class HLine {
  const HLine(this.price, this.color, this.label);

  final double price;
  final Color color;
  final String label;
}

/// Candlestick chart for 5-minute bars with an optional shaded band (opening range), price lines and markers.
class CandleChart extends StatelessWidget {
  const CandleChart({super.key, required this.candles, this.band, this.lines = const [], this.markers = const [], this.height = 320});

  final Candles candles;
  final (double, double, int)? band; // high, low, number of bars it covers
  final List<HLine> lines;
  final List<ChartMarker> markers;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _CandlePainter(this, Theme.of(context))),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.c, this.theme);

  final CandleChart c;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final k = c.candles;
    final n = k.close.length;
    if (n == 0) return;
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final upC = dark ? const Color(0xFF5BD68A) : const Color(0xFF1A7F37);
    final dnC = dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E);
    final labelStyle = TextStyle(color: cs.onSurfaceVariant, fontSize: 11);
    var lo = k.low.reduce(math.min), hi = k.high.reduce(math.max);
    for (final l in c.lines) {
      lo = math.min(lo, l.price);
      hi = math.max(hi, l.price);
    }
    final pad = math.max((hi - lo) * 0.08, 0.5);
    lo -= pad;
    hi += pad;
    const left = 64.0, right = 10.0, top = 8.0, bottom = 24.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    final slot = w / n;
    double x(int i) => left + slot * (i + 0.5);
    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final v = lo + (hi - lo) * g / 4;
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - right, y(v)), grid);
      _text(canvas, v.toStringAsFixed(v.abs() >= 1000 ? 0 : 1), Offset(left - 6, y(v)), labelStyle, alignRight: true);
    }
    for (var i = 0; i < n; i++) {
      if (k.minutes[i] % 60 == 15) _text(canvas, hm(k.minutes[i]), Offset(x(i), size.height - bottom + 6), labelStyle, center: true);
    }

    if (c.band != null) {
      final (bh, bl, bars) = c.band!;
      final shade = Paint()..color = cs.primary.withValues(alpha: 0.08);
      canvas.drawRect(Rect.fromLTRB(left, y(bh), size.width - right, y(bl)), shade);
      canvas.drawRect(Rect.fromLTRB(left, y(bh), left + slot * bars, y(bl)), Paint()..color = cs.primary.withValues(alpha: 0.12));
      final edge = Paint()
        ..color = cs.primary.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      _dashed(canvas, Offset(left, y(bh)), Offset(size.width - right, y(bh)), edge);
      _dashed(canvas, Offset(left, y(bl)), Offset(size.width - right, y(bl)), edge);
    }

    final bodyW = math.max(1.0, slot * 0.62);
    for (var i = 0; i < n; i++) {
      final up = k.close[i] >= k.open[i];
      final p = Paint()
        ..color = up ? upC : dnC
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x(i), y(k.high[i])), Offset(x(i), y(k.low[i])), p);
      final top_ = y(math.max(k.open[i], k.close[i])), bot = y(math.min(k.open[i], k.close[i]));
      canvas.drawRect(Rect.fromLTRB(x(i) - bodyW / 2, top_, x(i) + bodyW / 2, math.max(bot, top_ + 1)), p);
    }

    for (final l in c.lines) {
      final p = Paint()
        ..color = l.color
        ..strokeWidth = 1.2;
      _dashed(canvas, Offset(left, y(l.price)), Offset(size.width - right, y(l.price)), p);
      _text(canvas, '${l.label} ${l.price.toStringAsFixed(2)}', Offset(size.width - right - 4, y(l.price) - 8),
          TextStyle(color: l.color, fontSize: 11, fontWeight: FontWeight.w600), alignRight: true);
    }

    for (final m in c.markers) {
      if (m.index < 0 || m.index >= n) continue;
      final cx = x(m.index), cy = y(m.price);
      final path = Path();
      const s = 7.0;
      if (m.up) {
        path
          ..moveTo(cx, cy - s)
          ..lineTo(cx - s, cy + s)
          ..lineTo(cx + s, cy + s)
          ..close();
      } else {
        path
          ..moveTo(cx, cy + s)
          ..lineTo(cx - s, cy - s)
          ..lineTo(cx + s, cy - s)
          ..close();
      }
      canvas.drawPath(path, Paint()..color = m.color);
      canvas.drawPath(
          path,
          Paint()
            ..color = cs.surface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      _text(canvas, m.label, Offset(cx, m.up ? cy + s + 2 : cy - s - 15), TextStyle(color: m.color, fontSize: 11, fontWeight: FontWeight.w700),
          center: true);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) => old.c != c || old.theme != theme;
}

void _text(Canvas canvas, String s, Offset at, TextStyle style, {bool alignRight = false, bool center = false}) {
  final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
  var dx = at.dx;
  if (alignRight) dx -= tp.width;
  if (center) dx -= tp.width / 2;
  final dy = alignRight && !center ? at.dy - tp.height / 2 : at.dy;
  tp.paint(canvas, Offset(dx, dy));
}

void _dashed(Canvas canvas, Offset a, Offset b, Paint p, {double dash = 5, double gap = 4}) {
  final len = (b - a).distance;
  if (len == 0) return;
  final dir = (b - a) / len;
  for (var d = 0.0; d < len; d += dash + gap) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), p);
  }
}
