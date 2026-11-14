import 'package:flutter/widgets.dart';

import 'engine/backtest.dart';
import 'engine/market.dart';
import 'engine/reference.dart';
import 'engine/session.dart';
import 'engine/strategies.dart';
import 'engine/trading.dart';

enum LabStrategy { orb, supertrend, straddle }

class AppState extends ChangeNotifier {
  AppState(this.market, this.reference) : baseSessions = SessionFactory(market) {
    _factory = baseSessions;
    buyHold = BuyHoldResult.of(baseSessions.real());
    replayDate = realDays.last.iso;
  }

  final MarketData market;
  final ReferenceData reference;

  /// Default model (IV = VIX), as used by the Python reference run.
  final SessionFactory baseSessions;
  late SessionFactory _factory;
  late final BuyHoldResult buyHold;

  // ---- navigation
  int tab = 0;

  void goTo(int t) {
    tab = t;
    notifyListeners();
  }

  // ---- lab settings
  LabStrategy labStrategy = LabStrategy.orb;
  OrbStrategy orb = const OrbStrategy();
  SupertrendStrategy supertrend = const SupertrendStrategy();
  StraddleStrategy straddle = const StraddleStrategy();
  double spread = 1.0; // full bid/ask spread in Rs
  double slippage = 0.5;
  int lots = 1;
  double ivScale = 1.0;
  int noiseSeeds = 8;

  Strategy get strategy => switch (labStrategy) {
        LabStrategy.orb => orb,
        LabStrategy.supertrend => supertrend,
        LabStrategy.straddle => straddle,
      };

  Fills get fills => Fills(halfSpread: spread / 2, slippage: slippage, lots: lots);

  List<SessionDay> get realDays => _factory.real();
  SessionFactory get sessions => _factory;

  bool get isDefault =>
      spread == 1.0 &&
      slippage == 0.5 &&
      lots == 1 &&
      ivScale == 1.0 &&
      switch (labStrategy) {
        LabStrategy.orb => _sameOrb(orb, const OrbStrategy()),
        LabStrategy.supertrend => _sameSt(supertrend, const SupertrendStrategy()),
        LabStrategy.straddle => _sameStraddle(straddle, const StraddleStrategy()),
      };

  /// Change lab settings; marks the last result as out of date.
  void edit(void Function() change) {
    final oldIv = ivScale;
    change();
    if (ivScale != oldIv) _factory = ivScale == 1.0 ? baseSessions : SessionFactory(market, params: ModelParams(ivScale: ivScale));
    stale = true;
    notifyListeners();
  }

  void resetLab() => edit(() {
        orb = const OrbStrategy();
        supertrend = const SupertrendStrategy();
        straddle = const StraddleStrategy();
        spread = 1.0;
        slippage = 0.5;
        lots = 1;
        ivScale = 1.0;
        noiseSeeds = 8;
      });

  // ---- results
  BacktestResult? result;
  bool running = false;
  bool stale = true;
  double progress = 0;
  int _runId = 0;

  /// Sessions the last result was computed on (its IV setting), for drawing its option charts.
  SessionFactory? resultSessions;

  Future<void> run() async {
    final id = ++_runId;
    final sessions = _factory;
    running = true;
    progress = 0;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final r = await runBacktest(sessions, strategy, fills, noiseSeeds: noiseSeeds, onProgress: (done, total) async {
      progress = total == 0 ? 1 : done / total;
      notifyListeners();
      await Future<void>.delayed(Duration.zero);
    });
    if (id != _runId) return;
    result = r;
    resultSessions = sessions;
    running = false;
    stale = false;
    notifyListeners();
  }

  // ---- replay
  late String replayDate;

  /// 'lab' = the last lab result, otherwise a reference strategy id from the Python run.
  String replaySource = 'lab';

  void openReplay(String date, {String source = 'lab'}) {
    replayDate = date;
    replaySource = source;
    tab = 2;
    notifyListeners();
  }

  void setReplay({String? date, String? source}) {
    if (date != null) replayDate = date;
    if (source != null) replaySource = source;
    notifyListeners();
  }
}

bool _sameOrb(OrbStrategy a, OrbStrategy b) =>
    a.rangeMinutes == b.rangeMinutes &&
    a.stopPct == b.stopPct &&
    a.targetPct == b.targetPct &&
    a.lastEntryMin == b.lastEntryMin &&
    a.strikeOffset == b.strikeOffset &&
    a.sides == b.sides &&
    a.skipExpiryDay == b.skipExpiryDay;

bool _sameSt(SupertrendStrategy a, SupertrendStrategy b) =>
    a.period == b.period && a.multiplier == b.multiplier && a.fromMin == b.fromMin && a.toMin == b.toMin && a.strikeOffset == b.strikeOffset;

bool _sameStraddle(StraddleStrategy a, StraddleStrategy b) =>
    a.entryMin == b.entryMin && a.stopPct == b.stopPct && a.skipExpiryDay == b.skipExpiryDay;

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
