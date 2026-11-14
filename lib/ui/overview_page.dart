import 'package:flutter/material.dart';

import '../app_state.dart';
import 'charts.dart';
import 'format.dart';
import 'widgets.dart';

const _order = ['playbook', 'ema_cross', 'orb', 'supertrend', 'short_straddle_920', 'random'];

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ref = app.reference;
    final t = Theme.of(context).textTheme;
    final dates = ref.dates;
    final ids = [for (final id in _order) if (ref.strategies.containsKey(id)) id];
    final chartIds = ids.where((id) => id != 'random').toList();
    final bh = app.buyHold;

    return PageBody(children: [
      Text('Nifty 50 strategy comparison', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('${dates.length} sessions of real Nifty 5-minute candles, ${dates.first} to ${dates.last}. '
          '1 lot (65), every strategy on the same data, option model, fills and Zerodha-style charges.'),
      const SizedBox(height: 16),
      const NoticeBanner(
        icon: Icons.warning_amber_rounded,
        text: 'Educational backtest, not investment advice. Index candles are real; option premiums are MODELLED '
            '(Black-Scholes with India VIX as the volatility), because expired option prices are not freely available. '
            'One short period cannot prove that any strategy works.',
      ),
      SectionCard(
        title: 'Equity curves',
        subtitle: 'Cumulative net P&L in rupees after all costs, 1 lot',
        child: LineChart(
          height: 320,
          xLabels: ['start', for (final d in dates) d.substring(5)],
          series: [
            for (var n = 0; n < chartIds.length; n++)
              LineSeries(strategyName(chartIds[n]), cumulative(ref.strategies[chartIds[n]]!.daily), seriesColors[n % seriesColors.length],
                  width: chartIds[n] == 'playbook' ? 2.8 : 1.8),
            LineSeries(strategyName('buy_hold'), cumulative(bh.daily), seriesColors[5]),
          ],
        ),
      ),
      SectionCard(
        title: 'Results',
        subtitle: 'Edge over noise = real result minus the average on zero-drift noise days (same volatility, no trend). '
            'Tap a row to replay its trades.',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('Strategy')),
              DataColumn(label: Text('Net'), numeric: true),
              DataColumn(label: Text('Trades'), numeric: true),
              DataColumn(label: Text('Win %'), numeric: true),
              DataColumn(label: Text('Profit factor'), numeric: true),
              DataColumn(label: Text('Max drawdown'), numeric: true),
              DataColumn(label: Text('Noise mean'), numeric: true),
              DataColumn(label: Text('Edge over noise'), numeric: true),
            ],
            rows: [
              for (final id in ids)
                DataRow(
                  onSelectChanged: id == 'random' ? null : (_) => app.openReplay(_firstTradeDate(app, id) ?? dates.last, source: id),
                  cells: [
                    DataCell(Text(strategyName(id), style: TextStyle(fontWeight: id == 'playbook' ? FontWeight.w700 : null))),
                    DataCell(Text(inr(ref.strategies[id]!.net, sign: true), style: TextStyle(color: pnlColor(context, ref.strategies[id]!.net)))),
                    DataCell(Text('${ref.strategies[id]!.trades ?? '-'}')),
                    DataCell(Text(pct(ref.strategies[id]!.winRate))),
                    DataCell(Text(num2(ref.strategies[id]!.profitFactor))),
                    DataCell(Text(inr(ref.strategies[id]!.maxDrawdown))),
                    DataCell(Text(inr(ref.strategies[id]!.noiseMean, sign: true))),
                    DataCell(Text(inr(ref.strategies[id]!.edge, sign: true), style: TextStyle(color: pnlColor(context, ref.strategies[id]!.edge)))),
                  ],
                ),
              DataRow(cells: [
                DataCell(Text(strategyName('buy_hold'))),
                DataCell(Text('${inr(bh.net, sign: true)} (${bh.pct >= 0 ? '+' : ''}${bh.pct.toStringAsFixed(2)}%)',
                    style: TextStyle(color: pnlColor(context, bh.net)))),
                const DataCell(Text('1')),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
                DataCell(Text(inr(bh.maxDrawdown), style: TextStyle(color: pnlColor(context, -1), fontWeight: FontWeight.w600))),
                const DataCell(Text('-')),
                const DataCell(Text('-')),
              ]),
            ],
          ),
        ),
      ),
      SectionCard(
        title: 'How to read this',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Bullet('Option BUYERS should lose money on noise days (costs and time decay). A buying strategy is only interesting '
              'if its real result is clearly better than its noise result: that gap is the edge over noise.'),
          const Bullet('Option SELLERS (the short straddle) earn the volatility premium even on noise days when implied volatility '
              'is above realised volatility, so judge them by the absolute result and the worst days, and remember the model '
              'has no volatility skew, no IV spikes and no event gaps beyond the sample.'),
          Bullet('Buy & hold futures is a bet on direction, not a trading method: it went ${inr(bh.troughPnl)} under water '
              '(around ${bh.troughDate}) before finishing at ${inr(bh.net, sign: true)}. Futures losses are settled daily, '
              'so a drawdown that large means margin calls.'),
          const Bullet('The playbook, bare EMA crossover and random baseline come from the Python bot (its full signal engine). '
              'Opening-range breakout, Supertrend and the short straddle are re-run live in the Strategy lab tab, where you can '
              'change their rules and costs.'),
        ]),
      ),
    ]);
  }

  String? _firstTradeDate(AppState app, String id) {
    final tr = app.reference.tradesOf(id);
    return tr.isEmpty ? null : tr.first.date;
  }
}
