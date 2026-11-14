import 'dart:math' as math;

import 'market.dart';
import 'pricing.dart';

class ModelParams {
  const ModelParams({this.ivScale = 1.0, this.vixFloor = 8.0});

  /// Option IV = India VIX x [ivScale].
  final double ivScale;
  final double vixFloor;

  @override
  bool operator ==(Object other) => other is ModelParams && other.ivScale == ivScale && other.vixFloor == vixFloor;

  @override
  int get hashCode => Object.hash(ivScale, vixFloor);
}

/// Modelled option candles for one contract on one day.
class OptionBars {
  OptionBars(this.open, this.high, this.low, this.close);

  final List<double> open, high, low, close;
}

/// One trading day ready for strategies: today's spot candles, the modelled option chain (built on demand) and
/// indicators computed with the previous day as warm-up. Mirrors build_session / make_days in the Python bot.
class SessionDay {
  SessionDay(this.today, this.prev, this.expiry, ModelParams params, {this.strikeStep = 50})
      : closeMin = [for (final m in today.minute) m + barMinutes] {
    iv = _impliedVol(today.vix, params);
    tEnd = [for (final c in closeMin) tradingYears(today.date, c, expiry)];
    var f = 0;
    for (var j = 0; j < closeMin.length; j++) {
      if (closeMin[j] <= flatMin) f = j;
    }
    flatJ = f;
  }

  final DayBars today;
  final DayBars prev;
  final DateTime expiry;
  final int strikeStep;
  final List<int> closeMin;
  late final List<double> iv;
  late final List<double> tEnd;
  late final int flatJ;
  final Map<String, OptionBars> _options = {};
  final Map<String, List<double>> _supertrend = {};

  DateTime get date => today.date;
  String get iso => today.iso;
  bool get isExpiryDay => date == expiry;

  static List<double> _impliedVol(List<double?> vix, ModelParams p) {
    final v = List<double?>.from(vix);
    for (var i = 1; i < v.length; i++) {
      v[i] ??= v[i - 1];
    }
    for (var i = v.length - 2; i >= 0; i--) {
      v[i] ??= v[i + 1];
    }
    return [for (final x in v) math.max(x ?? 13.0, p.vixFloor) / 100.0 * p.ivScale];
  }

  /// Call: its high is at spot's high. Put: the mirror, its high is at spot's low.
  OptionBars option(bool call, int strike) {
    final key = '${call ? 'CE' : 'PE'}$strike';
    return _options.putIfAbsent(key, () {
      final k = strike.toDouble();
      final n = today.length;
      final o = List<double>.filled(n, 0), h = List<double>.filled(n, 0);
      final l = List<double>.filled(n, 0), c = List<double>.filled(n, 0);
      for (var j = 0; j < n; j++) {
        final t = tEnd[j], v = iv[j];
        final po = tick(bsPrice(today.open[j], k, t, v, call));
        final ph = tick(bsPrice(call ? today.high[j] : today.low[j], k, t, v, call));
        final pl = tick(bsPrice(call ? today.low[j] : today.high[j], k, t, v, call));
        final pc = tick(bsPrice(today.close[j], k, t, v, call));
        o[j] = po;
        c[j] = pc;
        h[j] = math.max(math.max(po, ph), math.max(pl, pc));
        l[j] = math.min(math.min(po, ph), math.min(pl, pc));
      }
      return OptionBars(o, h, l, c);
    });
  }

  /// Supertrend direction (+1 / -1) for today's bars, computed over the previous and current day.
  List<double> supertrendDir(int period, double mult) {
    return _supertrend.putIfAbsent('$period/$mult', () {
      final h = [...prev.high, ...today.high];
      final l = [...prev.low, ...today.low];
      final c = [...prev.close, ...today.close];
      final d = supertrend(h, l, c, period, mult);
      return d.sublist(prev.length);
    });
  }
}

/// pandas ewm(alpha=a, adjust=False).mean(), including pandas' floating-point evaluation order.
List<double> ewmAdjustFalse(List<double> x, double alpha) {
  final com = (1 - alpha) / alpha;
  final a = 1.0 / (1.0 + com);
  final oldWtFactor = 1.0 - a;
  final out = List<double>.filled(x.length, 0);
  if (x.isEmpty) return out;
  var weighted = x[0];
  out[0] = weighted;
  for (var i = 1; i < x.length; i++) {
    final cur = x[i];
    final oldWt = oldWtFactor;
    if (weighted != cur) {
      weighted = oldWt * weighted + a * cur;
      weighted /= (oldWt + a);
    }
    out[i] = weighted;
  }
  return out;
}

/// Classic Supertrend direction with Wilder ATR (same as the Python bot's compare.supertrend).
List<double> supertrend(List<double> h, List<double> l, List<double> c, int period, double mult) {
  final n = c.length;
  final tr = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    if (i == 0) {
      tr[i] = h[0] - l[0];
    } else {
      tr[i] = math.max(h[i] - l[i], math.max((h[i] - c[i - 1]).abs(), (l[i] - c[i - 1]).abs()));
    }
  }
  final atr = ewmAdjustFalse(tr, 1.0 / period);
  final up = List<double>.filled(n, 0), dn = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final hl2 = (h[i] + l[i]) / 2.0;
    up[i] = hl2 - mult * atr[i];
    dn[i] = hl2 + mult * atr[i];
  }
  final fu = List<double>.from(up), fd = List<double>.from(dn), d = List<double>.filled(n, 1.0);
  for (var i = 1; i < n; i++) {
    fu[i] = c[i - 1] > fu[i - 1] ? math.max(up[i], fu[i - 1]) : up[i];
    fd[i] = c[i - 1] < fd[i - 1] ? math.min(dn[i], fd[i - 1]) : dn[i];
    d[i] = c[i] > fd[i - 1] ? 1.0 : (c[i] < fu[i - 1] ? -1.0 : d[i - 1]);
  }
  return d;
}

/// Zero-drift control: bars shuffled AND each bar randomly mirrored (an up bar becomes the same-sized down bar).
/// Volatility and bar shapes are kept; trend, momentum and the day's drift are destroyed.
DayBars noiseDay(DayBars day, math.Random rng) {
  final order = List<int>.generate(day.length, (i) => i)..shuffle(rng);
  final flip = List<bool>.generate(day.length, (_) => rng.nextDouble() < 0.5);
  return reorderDay(day, order, flip);
}

/// Bar j of the result is source bar order[j], mirrored when flip[j].
DayBars reorderDay(DayBars day, List<int> order, List<bool> flip) {
  final n = day.length;
  final gap = List<double>.filled(n, 1), hh = List<double>.filled(n, 1);
  final ll = List<double>.filled(n, 1), cc = List<double>.filled(n, 1);
  for (var i = 0; i < n; i++) {
    final prevC = i == 0 ? day.open[0] : day.close[i - 1];
    gap[i] = day.open[i] / prevC;
    hh[i] = day.high[i] / day.open[i];
    ll[i] = day.low[i] / day.open[i];
    cc[i] = day.close[i] / day.open[i];
  }
  final o = <double>[], h = <double>[], l = <double>[], c = <double>[];
  var px = day.open[0];
  for (var j = 0; j < n; j++) {
    final i = order[j];
    var g = gap[i], hi = hh[i], lo = ll[i], cl = cc[i];
    if (flip[j]) {
      final g2 = 1.0 / g, hi2 = 1.0 / lo, lo2 = 1.0 / hi, cl2 = 1.0 / cl;
      g = g2;
      hi = hi2;
      lo = lo2;
      cl = cl2;
    }
    final op = px * (j == 0 ? 1.0 : g);
    o.add(op);
    h.add(op * math.max(math.max(hi, 1.0), cl));
    l.add(op * math.min(math.min(lo, 1.0), cl));
    c.add(op * cl);
    px = c.last;
  }
  return DayBars(day.date, day.minute, o, h, l, c, day.vix);
}

/// Builds (and caches) the trading days: the real ones and, per seed, zero-drift noise versions.
class SessionFactory {
  SessionFactory(this.data, {this.params = const ModelParams()});

  final MarketData data;
  final ModelParams params;
  List<SessionDay>? _real;
  final Map<int, List<SessionDay>> _noise = {};

  List<SessionDay> real() => _real ??= _build(null);

  List<SessionDay> noise(int seed) => _noise.putIfAbsent(seed, () => _build(seed));

  List<SessionDay> _build(int? seed) {
    final rng = seed == null ? null : math.Random(seed);
    return transformed((_, d) => rng == null ? d : noiseDay(d, rng));
  }

  /// Trading days with today's bars replaced by [transform] (n = index in the result). The previous day stays real.
  List<SessionDay> transformed(DayBars Function(int n, DayBars day) transform) {
    final days = data.days;
    final tdays = {for (final d in days) d.date};
    return [
      for (var n = 1; n < days.length; n++)
        SessionDay(transform(n - 1, days[n]), days[n - 1], weeklyExpiry(days[n].date, tdays), params),
    ];
  }
}
