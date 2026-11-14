import 'pricing.dart';
import 'session.dart';
import 'trading.dart';

enum Sides { both, callsOnly, putsOnly }

abstract class Strategy {
  const Strategy();

  String get id;
  String get title;
  String get summary;

  List<Trade> runDay(SessionDay day, Fills fills);
}

/// Opening-range breakout: the first 5-minute close outside the opening range buys an option in that direction;
/// premium-based stop and target, else flat at 15:15. One trade a day.
class OrbStrategy extends Strategy {
  const OrbStrategy({
    this.rangeMinutes = 15,
    this.stopPct = 30,
    this.targetPct = 60,
    this.lastEntryMin = 13 * 60,
    this.strikeOffset = 0,
    this.sides = Sides.both,
    this.skipExpiryDay = false,
  });

  final int rangeMinutes;
  final double stopPct, targetPct;
  final int lastEntryMin;
  final int strikeOffset; // in-the-money steps (negative = out of the money)
  final Sides sides;
  final bool skipExpiryDay;

  @override
  String get id => 'orb';
  @override
  String get title => 'Opening-range breakout';
  @override
  String get summary => '$rangeMinutes-min range, stop ${stopPct.toStringAsFixed(0)}% / target ${targetPct.toStringAsFixed(0)}%, '
      'entries until ${_hm(lastEntryMin)}';

  OrbStrategy copyWith({int? rangeMinutes, double? stopPct, double? targetPct, int? lastEntryMin, int? strikeOffset,
          Sides? sides, bool? skipExpiryDay}) =>
      OrbStrategy(
        rangeMinutes: rangeMinutes ?? this.rangeMinutes,
        stopPct: stopPct ?? this.stopPct,
        targetPct: targetPct ?? this.targetPct,
        lastEntryMin: lastEntryMin ?? this.lastEntryMin,
        strikeOffset: strikeOffset ?? this.strikeOffset,
        sides: sides ?? this.sides,
        skipExpiryDay: skipExpiryDay ?? this.skipExpiryDay,
      );

  /// Opening range (high, low) of [day], or null if the day is too short.
  (double, double)? range(SessionDay day) {
    final n = rangeMinutes ~/ barMinutes;
    if (day.today.length <= n) return null;
    var hi = day.today.high[0], lo = day.today.low[0];
    for (var i = 1; i < n; i++) {
      if (day.today.high[i] > hi) hi = day.today.high[i];
      if (day.today.low[i] < lo) lo = day.today.low[i];
    }
    return (hi, lo);
  }

  @override
  List<Trade> runDay(SessionDay day, Fills fills) {
    if (skipExpiryDay && day.isExpiryDay) return const [];
    final r = range(day);
    if (r == null) return const [];
    final (orh, orl) = r;
    final cl = day.today.close;
    final stopF = (100 - stopPct) / 100, tgtF = (100 + targetPct) / 100;
    for (var i = rangeMinutes ~/ barMinutes; i < day.flatJ; i++) {
      if (day.closeMin[i] > lastEntryMin) break;
      final up = cl[i] > orh, down = cl[i] < orl;
      if (!up && !down) continue;
      if ((up && sides == Sides.putsOnly) || (down && sides == Sides.callsOnly)) continue;
      final k = selectStrike(cl[i], up, day.strikeStep, strikeOffset);
      final o = day.option(up, k);
      final e = manageLong(o, i, day.flatJ, fills, sl: (x) => stopF * x, tgt: (x) => tgtF * x);
      return [makeTrade(day, id, up ? 'CE' : 'PE', k, i, e.bar, e.entry, e.price, e.reason, fills, stop: e.stop, target: e.target)];
    }
    return const [];
  }
}

/// Supertrend flip-and-reverse on 5-minute Nifty: a flip up buys a call, a flip down a put; exit on the opposite flip.
class SupertrendStrategy extends Strategy {
  const SupertrendStrategy({
    this.period = 10,
    this.multiplier = 3.0,
    this.fromMin = 9 * 60 + 30,
    this.toMin = 14 * 60 + 45,
    this.strikeOffset = 0,
  });

  final int period;
  final double multiplier;
  final int fromMin, toMin, strikeOffset;

  @override
  String get id => 'supertrend';
  @override
  String get title => 'Supertrend flip';
  @override
  String get summary => 'Supertrend($period, ${multiplier.toStringAsFixed(1)}), entries ${_hm(fromMin)}-${_hm(toMin)}';

  SupertrendStrategy copyWith({int? period, double? multiplier, int? fromMin, int? toMin, int? strikeOffset}) =>
      SupertrendStrategy(
        period: period ?? this.period,
        multiplier: multiplier ?? this.multiplier,
        fromMin: fromMin ?? this.fromMin,
        toMin: toMin ?? this.toMin,
        strikeOffset: strikeOffset ?? this.strikeOffset,
      );

  @override
  List<Trade> runDay(SessionDay day, Fills fills) {
    final d = day.supertrendDir(period, multiplier);
    final cl = day.today.close;
    final out = <Trade>[];
    var i = 1;
    while (i < day.flatJ) {
      final t = day.closeMin[i];
      if (d[i] != d[i - 1] && t >= fromMin && t <= toMin) {
        final up = d[i] > 0;
        final want = d[i];
        final k = selectStrike(cl[i], up, day.strikeStep, strikeOffset);
        final e = manageLong(day.option(up, k), i, day.flatJ, fills, closeRule: (j) => d[j] != want ? 'ST_FLIP' : null);
        out.add(makeTrade(day, id, up ? 'CE' : 'PE', k, i, e.bar, e.entry, e.price, e.reason, fills));
        i = e.reason == 'ST_FLIP' ? e.bar : e.bar + 1; // a flip exit can open the reverse trade on the same bar
        continue;
      }
      i++;
    }
    return out;
  }
}

/// Short straddle (option SELLING): sell the ATM call and put at the entry bar's close; each leg has its own stop.
class StraddleStrategy extends Strategy {
  const StraddleStrategy({this.entryMin = 9 * 60 + 20, this.stopPct = 30, this.skipExpiryDay = false});

  final int entryMin; // close time of the entry bar
  final double stopPct;
  final bool skipExpiryDay;

  @override
  String get id => 'short_straddle_920';
  @override
  String get title => 'Short straddle (selling)';
  @override
  String get summary => 'sell ATM CE+PE at ${_hm(entryMin)}, ${stopPct.toStringAsFixed(0)}% stop per leg';

  StraddleStrategy copyWith({int? entryMin, double? stopPct, bool? skipExpiryDay}) => StraddleStrategy(
        entryMin: entryMin ?? this.entryMin,
        stopPct: stopPct ?? this.stopPct,
        skipExpiryDay: skipExpiryDay ?? this.skipExpiryDay,
      );

  @override
  List<Trade> runDay(SessionDay day, Fills fills) {
    if (skipExpiryDay && day.isExpiryDay) return const [];
    final e = day.closeMin.indexWhere((t) => t >= entryMin);
    if (e < 0 || e >= day.flatJ) return const [];
    final k = atmStrike(day.today.close[e], day.strikeStep);
    final out = <Trade>[];
    for (final call in [true, false]) {
      final o = day.option(call, k);
      final entry = o.close[e] - fills.halfSpread - fills.slippage;
      final stop = entry * (1.0 + stopPct / 100);
      var j = day.flatJ, px = o.close[day.flatJ] + fills.halfSpread + fills.slippage, reason = 'FLAT_TIME';
      for (var jj = e + 1; jj <= day.flatJ; jj++) {
        if (o.high[jj] >= stop) {
          j = jj;
          px = (o.open[jj] > stop ? o.open[jj] : stop) + fills.halfSpread + fills.slippage;
          reason = 'STOP_LOSS';
          break;
        }
      }
      out.add(makeTrade(day, id, call ? 'CE' : 'PE', k, e, j, entry, px, reason, fills, short: true, stop: stop));
    }
    return out;
  }
}

String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
