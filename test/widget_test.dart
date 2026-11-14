import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nifty_strategy_lab/app_state.dart';
import 'package:nifty_strategy_lab/engine/market.dart';
import 'package:nifty_strategy_lab/engine/reference.dart';
import 'package:nifty_strategy_lab/main.dart';
import 'package:nifty_strategy_lab/ui/format.dart';

AppState _state() => AppState(
      MarketData.fromJson(File('assets/data/market.json').readAsStringSync()),
      ReferenceData.fromJson(File('assets/data/reference.json').readAsStringSync()),
    );

Future<AppState> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final state = _state();
  await tester.runAsync(state.run);
  await tester.pumpWidget(StrategyLabApp(loader: () async => state));
  await tester.pump();
  await tester.pump();
  return state;
}

void main() {
  test('Indian rupee formatting', () {
    expect(inr(137257.15), '₹1,37,257');
    expect(inr(-2005.27, sign: true), '-₹2,005');
    expect(inr(5923.7, sign: true), '+₹5,924');
    expect(inr(0.2, sign: true), '₹0');
    expect(inr(12.345, decimals: 2), '₹12.35');
    expect(inrCompact(-137257), '-₹1.4L');
    expect(inrCompact(45200), '₹45k');
  });

  testWidgets('every tab renders on a desktop-sized window', (tester) async {
    final state = await _pump(tester, const Size(1400, 900));
    expect(find.text('Nifty 50 strategy comparison'), findsOneWidget);
    expect(state.result, isNotNull);
    for (var tab = 0; tab < 5; tab++) {
      state.goTo(tab);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'tab $tab');
    }
    state.goTo(1);
    await tester.pump();
    expect(find.text('Edge over noise'), findsOneWidget);
    expect(find.textContaining('reproduce the Python bot'), findsOneWidget);
  });

  testWidgets('phone-sized window uses the bottom navigation bar', (tester) async {
    final state = await _pump(tester, const Size(400, 860));
    expect(find.byType(NavigationBar), findsOneWidget);
    for (var tab = 0; tab < 5; tab++) {
      state.goTo(tab);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'tab $tab');
    }
  });

  testWidgets('a lab trade opens the replay on its day', (tester) async {
    final state = await _pump(tester, const Size(1400, 900));
    final t = state.result!.trades.first;
    state.openReplay(t.date);
    await tester.pump();
    expect(state.tab, 2);
    expect(find.text('Nifty 50, ${t.date}'), findsOneWidget);
    expect(find.textContaining('Bought ${t.strike} ${t.side}'), findsOneWidget);
  });
}
