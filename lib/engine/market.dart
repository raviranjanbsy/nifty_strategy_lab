import 'dart:convert';

/// One session of real (or noise-transformed) Nifty 5-minute candles with the India VIX at each bar.
class DayBars {
  DayBars(this.date, this.minute, this.open, this.high, this.low, this.close, this.vix);

  final DateTime date;
  final List<int> minute; // bar start, minutes after midnight (IST)
  final List<double> open, high, low, close;
  final List<double?> vix;

  int get length => close.length;
  String get iso => isoDate(date);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String hhmm(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

DateTime parseIsoDate(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

class MarketData {
  MarketData(this.days, this.source);

  /// Full sessions only, oldest first. The first one is the warm-up day for indicators.
  final List<DayBars> days;
  final String source;

  factory MarketData.fromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final days = <DayBars>[];
    for (final d in j['days'] as List) {
      final bars = (d['bars'] as List).cast<List>();
      double f(Object? x) => (x as num).toDouble();
      days.add(DayBars(
        parseIsoDate(d['date'] as String),
        [for (final b in bars) (b[0] as num).toInt()],
        [for (final b in bars) f(b[1])],
        [for (final b in bars) f(b[2])],
        [for (final b in bars) f(b[3])],
        [for (final b in bars) f(b[4])],
        [for (final b in bars) b[5] == null ? null : f(b[5])],
      ));
    }
    days.sort((a, b) => a.date.compareTo(b.date));
    return MarketData(days, (j['source'] ?? '') as String);
  }
}
