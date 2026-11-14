import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nifty_strategy_lab/engine/backtest.dart';
import 'package:nifty_strategy_lab/engine/market.dart';
import 'package:nifty_strategy_lab/engine/pricing.dart';
import 'package:nifty_strategy_lab/engine/reference.dart';
import 'package:nifty_strategy_lab/engine/session.dart';
import 'package:nifty_strategy_lab/engine/strategies.dart';
import 'package:nifty_strategy_lab/engine/trading.dart';

final market = MarketData.fromJson(File('assets/data/market.json').readAsStringSync());
final reference = ReferenceData.fromJson(File('assets/data/reference.json').readAsStringSync());

void main() {
  group('pricing matches the Python bot', () {
    test('Black-Scholes', () {
      expect(bsPrice(24500.3, 24500, 0.004, 0.132, true), closeTo(84.31187395773668, 1e-9));
      expect(bsPrice(24500.3, 24500, 0.004, 0.132, false), closeTo(78.91668446213771, 1e-9));
      expect(bsPrice(24100.0, 24350, 0.0007, 0.11, false), closeTo(249.11501071183739, 1e-9));
    });

    test('trading-time clock', () {
      expect(tradingYears(DateTime.utc(2026, 11, 11), 600, DateTime.utc(2026, 11, 17)), closeTo(0.018666666666666668, 1e-15));
      expect(tradingYears(DateTime.utc(2026, 11, 13), 920, DateTime.utc(2026, 11, 17)), closeTo(0.008021164021164021, 1e-15));
    });

    test('tick and banker\'s rounding', () {
      expect(tick(12.325), 12.3);
      expect(tick(0.01), 0.05);
      expect(roundHalfEven(2.5), 2);
      expect(roundHalfEven(3.5), 4);
      expect(atmStrike(24525, 50), 24500); // Python round(490.5) == 490
      expect(selectStrike(24510, true, 50, 1), 24450);
      expect(selectStrike(24510, false, 50, 1), 24550);
    });

    test('weekly expiry moves back over a holiday', () {
      final days = {DateTime.utc(2026, 11, 9), DateTime.utc(2026, 11, 10), DateTime.utc(2026, 11, 12), DateTime.utc(2026, 11, 13)};
      expect(weeklyExpiry(DateTime.utc(2026, 11, 9), days), DateTime.utc(2026, 11, 10));
      final holidayTue = {...days, DateTime.utc(2026, 11, 16), DateTime.utc(2026, 11, 18)}; // Tuesday the 17th closed
      expect(weeklyExpiry(DateTime.utc(2026, 11, 12), holidayTue), DateTime.utc(2026, 11, 16));
    });

    test('charges', () {
      const c = Charges();
      // buy 65 @ 100: brokerage 1.95, exchange 2.3075, sebi 0.0065, gst on those, stamp 0.195
      expect(c.order(false, 65, 100), closeTo(1.95 + 2.3075 + 0.0065 + 0.18 * (1.95 + 2.3075 + 0.0065) + 0.195, 1e-9));
      expect(c.order(true, 65, 1000) - c.order(false, 65, 1000), closeTo(0.0015 * 65000 - 0.00003 * 65000, 1e-9));
    });
  });

  group('noise control', () {
    test('same transform as Python for the same shuffle', () {
      final fx = jsonDecode(File('test/noise_fixture.json').readAsStringSync()) as Map<String, dynamic>;
      final day = market.days.firstWhere((d) => d.iso == fx['date']);
      final n = reorderDay(day, (fx['order'] as List).cast<int>(), (fx['flip'] as List).cast<bool>());
      for (final (key, mine) in [('open', n.open), ('high', n.high), ('low', n.low), ('close', n.close)]) {
        final py = (fx[key] as List).cast<num>();
        for (var i = 0; i < py.length; i++) {
          expect(mine[i], closeTo(py[i].toDouble(), 1e-9), reason: '$key[$i]');
        }
      }
    });

    test('strategies on Python\'s own noise days reproduce Python\'s noise trades', () {
      final runs = (jsonDecode(File('test/noise_runs_fixture.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final f = SessionFactory(market);
      for (final run in runs) {
        final sh = (run['shuffles'] as List).cast<Map<String, dynamic>>();
        final days = f.transformed((n, d) => reorderDay(d, (sh[n]['order'] as List).cast<int>(), (sh[n]['flip'] as List).cast<bool>()));
        for (final s in const <Strategy>[OrbStrategy(), SupertrendStrategy(), StraddleStrategy()]) {
          final mine = runDays(s, days, const Fills());
          final ref = (run['trades'][s.id] as List).cast<Map<String, dynamic>>();
          final where = 'seed ${run['seed']} ${s.id}';
          expect(mine.length, ref.length, reason: where);
          for (var k = 0; k < ref.length; k++) {
            expect('${mine[k].date} ${mine[k].side} ${mine[k].strike} ${mine[k].reason}',
                '${ref[k]['date']} ${ref[k]['side']} ${ref[k]['strike']} ${ref[k]['reason']}', reason: '$where #$k');
            expect(mine[k].net, closeTo((ref[k]['net'] as num).toDouble(), 1.0), reason: '$where #$k');
          }
        }
      }
    });

    test('keeps every bar size, destroys the order', () {
      final day = market.days[5];
      final n = noiseDay(day, math.Random(3));
      expect(n.length, day.length);
      List<double> sizes(DayBars d) => [for (var i = 0; i < d.length; i++) (math.log(d.close[i] / d.open[i])).abs()]..sort();
      final a = sizes(day), b = sizes(n);
      for (var i = 0; i < a.length; i++) {
        expect(b[i], closeTo(a[i], 1e-12));
      }
      for (var i = 0; i < n.length; i++) {
        expect(n.high[i] >= math.max(n.open[i], n.close[i]) - 1e-9 && n.low[i] <= math.min(n.open[i], n.close[i]) + 1e-9, isTrue);
      }
    });
  });

  group('Dart engine reproduces the Python trades on real data', () {
    final f = SessionFactory(market);
    const fills = Fills();

    void same(Strategy s, String refName) {
      final mine = runDays(s, f.real(), fills);
      final ref = reference.tradesOf(refName);
      expect(mine.length, ref.length, reason: '$refName trade count');
      for (var n = 0; n < ref.length; n++) {
        final a = mine[n], b = ref[n];
        final where = '$refName #$n ${b.date} ${b.side}';
        expect(a.date, b.date, reason: where);
        expect(a.side, b.side, reason: where);
        expect(a.strike, b.strike, reason: where);
        expect(a.entryMin, b.entryMin, reason: where);
        expect(a.exitMin, b.exitMin, reason: where);
        expect(a.reason, b.reason, reason: where);
        expect(a.entry, closeTo(b.entry, 0.011), reason: where);
        expect(a.exit, closeTo(b.exit, 0.011), reason: where);
        expect(a.net, closeTo(b.net, 1.0), reason: where);
      }
      final netA = mine.fold(0.0, (x, t) => x + t.net), netB = ref.fold(0.0, (x, t) => x + t.net);
      expect(netA, closeTo(netB, 2.0), reason: '$refName total net');
      expect(netA, closeTo(reference.strategies[refName]!.net, 10.0));
    }

    test('59 sessions after the warm-up day, same dates', () {
      expect([for (final d in f.real()) d.iso], reference.dates);
    });
    test('opening-range breakout', () => same(const OrbStrategy(), 'orb'));
    test('Supertrend', () => same(const SupertrendStrategy(), 'supertrend'));
    test('short straddle', () => same(const StraddleStrategy(), 'short_straddle_920'));

    test('buy & hold futures', () {
      final bh = BuyHoldResult.of(f.real());
      expect(bh.net, closeTo(reference.buyHoldNet, 0.01));
      expect(bh.maxDrawdown, closeTo(reference.buyHoldMaxDd, 0.01));
      expect(bh.pct, closeTo(reference.buyHoldPct, 0.006));
    });
  });

  group('backtest runner', () {
    test('noise runs and metrics', () async {
      final f = SessionFactory(market);
      final r = await runBacktest(f, const OrbStrategy(), const Fills(), noiseSeeds: 2);
      expect(r.noiseNets.length, 2);
      expect(r.noiseStdError, greaterThan(0));
      expect(r.metrics.trades, r.trades.length);
      expect(r.daily.fold(0.0, (a, b) => a + b), closeTo(r.metrics.net, 0.01));
      final ci = r.metrics.dailyCi95!;
      expect(ci.$1 < r.metrics.dailyMean! && r.metrics.dailyMean! < ci.$2, isTrue);
    });

    test('variants behave sensibly', () {
      final f = SessionFactory(market);
      const fills = Fills();
      final calls = runDays(const OrbStrategy(sides: Sides.callsOnly), f.real(), fills);
      expect(calls.every((t) => t.side == 'CE'), isTrue);
      final noExpiry = runDays(const OrbStrategy(skipExpiryDay: true), f.real(), fills);
      final expiryDates = {for (final d in f.real()) if (d.isExpiryDay) d.iso};
      expect(expiryDates, isNotEmpty);
      expect(noExpiry.any((t) => expiryDates.contains(t.date)), isFalse);
      final twoLots = runDays(const OrbStrategy(), f.real(), const Fills(lots: 2));
      final oneLot = runDays(const OrbStrategy(), f.real(), fills);
      expect(twoLots.first.gross, closeTo(2 * oneLot.first.gross, 0.02));
      final cheaper = runDays(const OrbStrategy(), SessionFactory(market, params: const ModelParams(ivScale: 0.85)).real(), fills);
      expect(cheaper.first.entry < oneLot.first.entry, isTrue);
    });
  });
}
