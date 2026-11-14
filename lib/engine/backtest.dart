import 'dart:math' as math;

import 'session.dart';
import 'strategies.dart';
import 'trading.dart';

class Metrics {
  Metrics({
    required this.trades,
    required this.days,
    required this.tradingDays,
    required this.winRate,
    required this.net,
    required this.gross,
    required this.charges,
    required this.avgWin,
    required this.avgLoss,
    required this.profitFactor,
    required this.expectancy,
    required this.maxDrawdown,
    required this.worstTrade,
    required this.bestTrade,
    required this.dailyMean,
    required this.dailyCi95,
    required this.sharpe,
  });

  final int trades, days, tradingDays;
  final double winRate, net, gross, charges, avgWin, avgLoss, expectancy, maxDrawdown, worstTrade, bestTrade;
  final double? profitFactor, dailyMean, sharpe;
  final (double, double)? dailyCi95;

  /// Same definitions as the Python bot's backtest.metrics (drawdown over the trade sequence; losses include
  /// break-even trades) plus an annualised Sharpe ratio of the daily P&L.
  factory Metrics.of(List<Trade> trades, List<double> daily, {int seed = 11}) {
    final nets = [for (final t in trades) t.net];
    final wins = nets.where((x) => x > 0).toList(), losses = nets.where((x) => x <= 0).toList();
    var cum = 0.0, peak = 0.0, dd = 0.0;
    for (final x in nets) {
      cum += x;
      peak = math.max(peak, cum);
      dd = math.max(dd, peak - cum);
    }
    double sum(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);
    final gl = -sum(losses);
    final dm = daily.isEmpty ? null : sum(daily) / daily.length;
    (double, double)? ci;
    double? sharpe;
    if (daily.length >= 10) {
      final rng = math.Random(seed);
      final boots = List<double>.generate(5000, (_) {
        var s = 0.0;
        for (var k = 0; k < daily.length; k++) {
          s += daily[rng.nextInt(daily.length)];
        }
        return s / daily.length;
      })
        ..sort();
      ci = (boots[(0.025 * 4999).round()], boots[(0.975 * 4999).round()]);
      final mean = dm!;
      final varS = sum(daily.map((x) => (x - mean) * (x - mean))) / (daily.length - 1);
      sharpe = varS > 0 ? mean / math.sqrt(varS) * math.sqrt(252) : null;
    }
    return Metrics(
      trades: trades.length,
      days: daily.length,
      tradingDays: trades.map((t) => t.date).toSet().length,
      winRate: nets.isEmpty ? 0 : 100.0 * wins.length / nets.length,
      net: sum(nets),
      gross: sum(trades.map((t) => t.gross)),
      charges: sum(trades.map((t) => t.charges)),
      avgWin: wins.isEmpty ? 0 : sum(wins) / wins.length,
      avgLoss: losses.isEmpty ? 0 : sum(losses) / losses.length,
      profitFactor: gl > 0 ? sum(wins) / gl : null,
      expectancy: nets.isEmpty ? 0 : sum(nets) / nets.length,
      maxDrawdown: dd,
      worstTrade: nets.isEmpty ? 0 : nets.reduce(math.min),
      bestTrade: nets.isEmpty ? 0 : nets.reduce(math.max),
      dailyMean: dm,
      dailyCi95: ci,
      sharpe: sharpe,
    );
  }
}

List<double> dailySeries(List<Trade> trades, List<String> dates) {
  final by = <String, double>{};
  for (final t in trades) {
    by[t.date] = (by[t.date] ?? 0) + t.net;
  }
  return [for (final d in dates) by[d] ?? 0.0];
}

List<Trade> runDays(Strategy s, List<SessionDay> days, Fills fills) => [for (final d in days) ...s.runDay(d, fills)];

class BacktestResult {
  BacktestResult({
    required this.strategy,
    required this.fills,
    required this.dates,
    required this.trades,
    required this.daily,
    required this.metrics,
    required this.noiseNets,
    required this.noiseDaily,
  });

  final Strategy strategy;
  final Fills fills;
  final List<String> dates;
  final List<Trade> trades;
  final List<double> daily;
  final Metrics metrics;
  final List<double> noiseNets;
  final List<List<double>> noiseDaily;

  double? get noiseMean => noiseNets.isEmpty ? null : noiseNets.reduce((a, b) => a + b) / noiseNets.length;

  /// Standard error of [noiseMean]: a single noise run varies a lot, so a handful of runs only pins the mean down roughly.
  double? get noiseStdError {
    if (noiseNets.length < 2) return null;
    final m = noiseMean!;
    final v = noiseNets.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (noiseNets.length - 1);
    return math.sqrt(v / noiseNets.length);
  }
  double? get edgeOverNoise => noiseMean == null ? null : metrics.net - noiseMean!;

  Map<String, (int, double)> byReason() {
    final m = <String, (int, double)>{};
    for (final t in trades) {
      final (n, s) = m[t.reason] ?? (0, 0.0);
      m[t.reason] = (n + 1, s + t.net);
    }
    return m;
  }
}

/// Runs [s] on the real days and on [noiseSeeds] zero-drift noise versions. [onProgress] is awaited between runs so a
/// web UI can repaint.
Future<BacktestResult> runBacktest(SessionFactory f, Strategy s, Fills fills,
    {int noiseSeeds = 8, Future<void> Function(int done, int total)? onProgress}) async {
  final real = f.real();
  final dates = [for (final d in real) d.iso];
  final trades = runDays(s, real, fills);
  final daily = dailySeries(trades, dates);
  final nets = <double>[];
  final curves = <List<double>>[];
  for (var seed = 1; seed <= noiseSeeds; seed++) {
    await onProgress?.call(seed - 1, noiseSeeds);
    final nt = runDays(s, f.noise(seed), fills);
    nets.add(nt.fold(0.0, (a, t) => a + t.net));
    curves.add(dailySeries(nt, dates));
  }
  await onProgress?.call(noiseSeeds, noiseSeeds);
  return BacktestResult(
    strategy: s,
    fills: fills,
    dates: dates,
    trades: trades,
    daily: daily,
    metrics: Metrics.of(trades, daily),
    noiseNets: nets,
    noiseDaily: curves,
  );
}

/// Buy 1 lot of Nifty futures at the first session's open and hold to the last close (index used as the futures price,
/// no rollover cost; about Rs 150 of charges per lot).
class BuyHoldResult {
  BuyHoldResult(this.start, this.end, this.daily, this.net, this.maxDrawdown, this.pct, this.troughDate, this.troughPnl);

  final double start, end, net, maxDrawdown, pct, troughPnl;
  final List<double> daily;
  final String troughDate;

  factory BuyHoldResult.of(List<SessionDay> days, {int lots = 1, int lotSize = 65}) {
    final q = lots * lotSize;
    final start = days.first.today.open.first;
    final path = <double>[0.0, for (final d in days) (d.today.close.last - start) * q];
    var peak = 0.0, dd = 0.0, trough = 0.0, troughI = 0;
    for (var i = 0; i < path.length; i++) {
      peak = math.max(peak, path[i]);
      if (peak - path[i] > dd) dd = peak - path[i];
      if (path[i] < trough) {
        trough = path[i];
        troughI = i;
      }
    }
    final end = days.last.today.close.last;
    return BuyHoldResult(start, end, [for (var i = 1; i < path.length; i++) path[i] - path[i - 1]], path.last - 150.0 * lots,
        dd, 100.0 * (end / start - 1.0), troughI == 0 ? days.first.iso : days[troughI - 1].iso, trough);
  }
}
