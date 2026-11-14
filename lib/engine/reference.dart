import 'dart:convert';

/// One trade produced by the Python bot's comparison run (nifty_bot/compare.py).
class RefTrade {
  RefTrade(this.date, this.strategy, this.side, this.strike, this.entryT, this.exitT, this.entry, this.exit, this.reason,
      this.gross, this.charges, this.net);

  final String date, strategy, side, entryT, exitT, reason;
  final int strike;
  final double entry, exit, gross, charges, net;

  bool get isCall => side == 'CE';

  /// 'HH:MM:SS' -> minutes after midnight.
  static int minutes(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int get entryMin => minutes(entryT);
  int get exitMin => minutes(exitT);
}

class RefStrategy {
  RefStrategy(this.id, this.desc, this.real, this.noiseMean, this.edge, this.daily);

  final String id, desc;
  final Map<String, dynamic> real;
  final double? noiseMean, edge;
  final List<double> daily;

  double get net => (real['net'] as num?)?.toDouble() ?? 0;
  num? get trades => real['trades'] as num?;
  double? get winRate => (real['win_rate'] as num?)?.toDouble();
  double? get profitFactor => (real['profit_factor'] as num?)?.toDouble();
  double? get maxDrawdown => (real['max_drawdown'] as num?)?.toDouble();
}

class ReferenceData {
  ReferenceData(this.dates, this.strategies, this.buyHoldDaily, this.buyHoldNet, this.buyHoldPct, this.buyHoldMaxDd, this.trades);

  final List<String> dates;
  final Map<String, RefStrategy> strategies;
  final List<double> buyHoldDaily;
  final double buyHoldNet, buyHoldPct, buyHoldMaxDd;
  final List<RefTrade> trades;

  List<RefTrade> tradesOf(String strategy) => [for (final t in trades) if (t.strategy == strategy) t];

  factory ReferenceData.fromJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    List<double> dl(Object? v) => [for (final x in (v as List? ?? const [])) (x as num).toDouble()];
    double? d(Object? v) => (v as num?)?.toDouble();
    final strategies = <String, RefStrategy>{};
    (j['strategies'] as Map<String, dynamic>).forEach((k, v) {
      final m = v as Map<String, dynamic>;
      strategies[k] = RefStrategy(k, (m['desc'] ?? k) as String, (m['real'] ?? const {}) as Map<String, dynamic>,
          d(m['noise_mean']), d(m['edge_over_noise']), dl(m['daily']));
    });
    final bh = j['buy_hold'] as Map<String, dynamic>;
    final trades = [
      for (final t in (j['trades'] as List).cast<Map<String, dynamic>>())
        RefTrade(t['date'] as String, t['strategy'] as String, t['side'] as String, (t['strike'] as num).toInt(),
            t['entry_t'] as String, t['exit_t'] as String, d(t['entry'])!, d(t['exit'])!, t['reason'] as String,
            d(t['gross'])!, d(t['charges'])!, d(t['net'])!),
    ];
    return ReferenceData([for (final x in j['dates'] as List) x as String], strategies, dl(bh['daily']), d(bh['net'])!,
        d(bh['pct'])!, d(bh['max_drawdown'])!, trades);
  }
}
