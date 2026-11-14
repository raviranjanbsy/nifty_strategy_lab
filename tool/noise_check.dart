// Prints the mean and spread of each strategy's net P&L over many zero-drift noise runs:
//   dart run tool/noise_check.dart [runs] [first_seed]
import 'dart:io';
import 'dart:math' as math;

import 'package:nifty_strategy_lab/engine/backtest.dart';
import 'package:nifty_strategy_lab/engine/market.dart';
import 'package:nifty_strategy_lab/engine/session.dart';
import 'package:nifty_strategy_lab/engine/strategies.dart';
import 'package:nifty_strategy_lab/engine/trading.dart';

void main(List<String> args) {
  final runs = args.isEmpty ? 32 : int.parse(args[0]);
  final first = args.length < 2 ? 1 : int.parse(args[1]);
  final f = SessionFactory(MarketData.fromJson(File('assets/data/market.json').readAsStringSync()));
  for (final s in const <Strategy>[OrbStrategy(), SupertrendStrategy(), StraddleStrategy()]) {
    final nets = [
      for (var seed = first; seed < first + runs; seed++) runDays(s, f.noise(seed), const Fills()).fold(0.0, (a, t) => a + t.net),
    ];
    final mean = nets.reduce((a, b) => a + b) / runs;
    final sd = math.sqrt(nets.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (runs - 1));
    var lag = 0.0;
    for (var i = 1; i < runs; i++) {
      lag += (nets[i] - mean) * (nets[i - 1] - mean);
    }
    lag /= (runs - 1) * sd * sd;
    stdout.writeln('${s.id.padRight(20)} mean ${mean.toStringAsFixed(0).padLeft(8)}  sd ${sd.toStringAsFixed(0).padLeft(7)}  '
        'se ${(sd / math.sqrt(runs)).toStringAsFixed(0).padLeft(5)}  lag-1 corr ${lag.toStringAsFixed(2)}');
  }
}
