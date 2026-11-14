import 'dart:math' as math;

import 'market.dart';
import 'session.dart';

/// Zerodha-style per-order costs (approximations; verify with Zerodha's brokerage calculator).
class Charges {
  const Charges({
    this.brokeragePerOrder = 20.0,
    this.brokeragePctCap = 0.0003,
    this.sttSellPct = 0.0015,
    this.exchangePct = 0.000355,
    this.sebiPct = 0.000001,
    this.stampBuyPct = 0.00003,
    this.gstPct = 0.18,
  });

  final double brokeragePerOrder, brokeragePctCap, sttSellPct, exchangePct, sebiPct, stampBuyPct, gstPct;

  double order(bool sell, int qty, double price) {
    final turnover = qty * price;
    final brokerage = math.min(brokeragePerOrder, brokeragePctCap * turnover);
    final exchange = exchangePct * turnover;
    final sebi = sebiPct * turnover;
    final gst = gstPct * (brokerage + exchange + sebi);
    final stt = sell ? sttSellPct * turnover : 0.0;
    final stamp = sell ? 0.0 : stampBuyPct * turnover;
    return brokerage + exchange + sebi + gst + stt + stamp;
  }
}

/// Bid/ask and slippage assumptions. Buys pay the ask plus slippage, sells receive the bid minus slippage.
class Fills {
  const Fills({this.halfSpread = 0.5, this.slippage = 0.5, this.lots = 1, this.lotSize = 65, this.charges = const Charges()});

  final double halfSpread, slippage;
  final int lots, lotSize;
  final Charges charges;

  int get qty => lots * lotSize;
}

double round2(double x) => double.parse(x.toStringAsFixed(2));

class Trade {
  Trade({
    required this.date,
    required this.strategy,
    required this.side,
    required this.strike,
    required this.entryBar,
    required this.exitBar,
    required this.entryMin,
    required this.exitMin,
    required this.entry,
    required this.exit,
    required this.reason,
    required this.gross,
    required this.charges,
    required this.net,
    this.short = false,
    this.stop,
    this.target,
  });

  final String date, strategy, side, reason;
  final int strike, entryBar, exitBar, entryMin, exitMin;
  final double entry, exit, gross, charges, net;
  final bool short;
  final double? stop, target;

  bool get isCall => side == 'CE';
  int get bars => exitBar - entryBar;
  String get entryTime => hhmm(entryMin);
  String get exitTime => hhmm(exitMin);
}

Trade makeTrade(SessionDay day, String name, String side, int strike, int i, int j, double entry, double exit,
    String reason, Fills f, {bool short = false, double? stop, double? target}) {
  final q = f.qty;
  final gross = short ? (entry - exit) * q : (exit - entry) * q;
  final ch = f.charges.order(short, q, entry) + f.charges.order(!short, q, exit);
  return Trade(
    date: day.iso,
    strategy: name,
    side: side,
    strike: strike,
    entryBar: i,
    exitBar: j,
    entryMin: day.closeMin[i],
    exitMin: day.closeMin[j],
    entry: round2(entry),
    exit: round2(exit),
    reason: reason,
    gross: round2(gross),
    charges: round2(ch),
    net: round2(gross - ch),
    short: short,
    stop: stop,
    target: target,
  );
}

class Exit {
  Exit(this.bar, this.price, this.reason, this.entry, this.stop, this.target);

  final int bar;
  final double price, entry;
  final String reason;
  final double? stop, target;
}

/// Buy at the ask (+slippage) at the close of bar [i], manage from bar i+1. Inside a candle the stop is checked
/// before the target (the adverse order); a gapped stop fills at the open; the target is a resting sell limit, so the
/// bid must reach it. Otherwise flat at the 15:15 bar.
Exit manageLong(OptionBars o, int i, int flatJ, Fills f,
    {double Function(double entry)? sl, double Function(double entry)? tgt, String? Function(int j)? closeRule}) {
  final entry = o.close[i] + f.halfSpread + f.slippage;
  final stop = sl?.call(entry);
  final target = tgt?.call(entry);
  for (var j = i + 1; j <= flatJ; j++) {
    if (stop != null && o.low[j] <= stop) {
      return Exit(j, math.min(o.open[j], stop) - f.halfSpread - f.slippage, 'STOP_LOSS', entry, stop, target);
    }
    if (target != null && o.high[j] >= target && o.high[j] - f.halfSpread >= target) {
      return Exit(j, target, 'TARGET', entry, stop, target);
    }
    final r = closeRule?.call(j);
    if (r != null) return Exit(j, o.close[j] - f.halfSpread - f.slippage, r, entry, stop, target);
  }
  return Exit(flatJ, o.close[flatJ] - f.halfSpread - f.slippage, 'FLAT_TIME', entry, stop, target);
}
