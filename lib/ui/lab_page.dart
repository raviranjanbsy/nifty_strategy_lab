import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine/backtest.dart';
import '../engine/strategies.dart';
import 'charts.dart';
import 'format.dart';
import 'widgets.dart';

class LabPage extends StatelessWidget {
  const LabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1100;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 360, child: ListView(padding: const EdgeInsets.all(16), children: const [_ConfigPanel()])),
          const VerticalDivider(width: 1),
          const Expanded(child: _Results()),
        ]);
      }
      final app = AppScope.of(context);
      return PageBody(children: [
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.tune),
            title: Text('Settings: ${app.strategy.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(app.strategy.summary),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: const [_ConfigPanel()],
          ),
        ),
        const _ResultsColumn(),
      ]);
    });
  }
}

// ------------------------------------------------------------------------------------------------- configuration
class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Strategy lab', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Change the rules and costs, then run. Everything is computed in your browser.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      SegmentedButton<LabStrategy>(
        segments: const [
          ButtonSegment(value: LabStrategy.orb, label: Text('ORB')),
          ButtonSegment(value: LabStrategy.supertrend, label: Text('Supertrend')),
          ButtonSegment(value: LabStrategy.straddle, label: Text('Straddle')),
        ],
        selected: {app.labStrategy},
        onSelectionChanged: (s) => app.edit(() => app.labStrategy = s.first),
      ),
      const SizedBox(height: 16),
      switch (app.labStrategy) {
        LabStrategy.orb => const _OrbControls(),
        LabStrategy.supertrend => const _SupertrendControls(),
        LabStrategy.straddle => const _StraddleControls(),
      },
      const Divider(height: 32),
      Text('Costs and model', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      LabeledSlider(
          label: 'Bid/ask spread',
          value: app.spread,
          min: 0,
          max: 4,
          divisions: 8,
          format: (v) => '₹${v.toStringAsFixed(1)}',
          onChanged: (v) => app.edit(() => app.spread = v)),
      LabeledSlider(
          label: 'Slippage per order',
          value: app.slippage,
          min: 0,
          max: 3,
          divisions: 12,
          format: (v) => '₹${v.toStringAsFixed(2)}',
          onChanged: (v) => app.edit(() => app.slippage = v)),
      LabeledSlider(
          label: 'Lots (65 qty each)',
          value: app.lots.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => app.edit(() => app.lots = v.round())),
      LabeledSlider(
          label: 'Option IV = India VIX x',
          value: app.ivScale,
          min: 0.7,
          max: 1.3,
          divisions: 12,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => app.edit(() => app.ivScale = double.parse(v.toStringAsFixed(2)))),
      LabeledSlider(
          label: 'Noise control runs',
          value: app.noiseSeeds.toDouble(),
          min: 0,
          max: 16,
          divisions: 8,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => app.edit(() => app.noiseSeeds = v.round())),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: app.running ? null : app.run,
            icon: app.running
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(app.running ? 'Running ${(app.progress * 100).round()}%' : 'Run backtest'),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: app.running ? null : app.resetLab, child: const Text('Defaults')),
      ]),
      const SizedBox(height: 8),
      if (app.isDefault)
        Text('Default settings reproduce the Python bot\'s results trade for trade (checked by automated tests).',
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

List<DropdownMenuItem<int>> _timeItems(int from, int to, int step) =>
    [for (var m = from; m <= to; m += step) DropdownMenuItem(value: m, child: Text(hm(m)))];

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Expanded(child: Text(label)), child]),
      );
}

String _strikeLabel(int s) => s == 0 ? 'ATM' : (s > 0 ? '$s ITM' : '${-s} OTM');

Widget _strikeDropdown(int value, ValueChanged<int> onChanged) => DropdownButton<int>(
      value: value,
      items: [for (var s = 2; s >= -2; s--) DropdownMenuItem(value: s, child: Text(_strikeLabel(s)))],
      onChanged: (v) => onChanged(v!),
    );

class _OrbControls extends StatelessWidget {
  const _OrbControls();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.orb;
    void set(OrbStrategy n) => app.edit(() => app.orb = n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Labeled(
          'Opening range',
          DropdownButton<int>(
            value: s.rangeMinutes,
            items: [for (final m in [5, 10, 15, 30, 45, 60]) DropdownMenuItem(value: m, child: Text('$m min'))],
            onChanged: (v) => set(s.copyWith(rangeMinutes: v)),
          )),
      LabeledSlider(
          label: 'Stop-loss (premium drop)',
          value: s.stopPct,
          min: 10,
          max: 60,
          divisions: 10,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => set(s.copyWith(stopPct: v.roundToDouble()))),
      LabeledSlider(
          label: 'Target (premium gain)',
          value: s.targetPct,
          min: 20,
          max: 200,
          divisions: 18,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => set(s.copyWith(targetPct: v.roundToDouble()))),
      _Labeled(
          'Last entry (candle close)',
          DropdownButton<int>(
            value: s.lastEntryMin,
            items: _timeItems(9 * 60 + 45, 14 * 60 + 30, 15),
            onChanged: (v) => set(s.copyWith(lastEntryMin: v)),
          )),
      _Labeled('Strike', _strikeDropdown(s.strikeOffset, (v) => set(s.copyWith(strikeOffset: v)))),
      _Labeled(
          'Direction',
          DropdownButton<Sides>(
            value: s.sides,
            items: const [
              DropdownMenuItem(value: Sides.both, child: Text('Calls and puts')),
              DropdownMenuItem(value: Sides.callsOnly, child: Text('Calls only')),
              DropdownMenuItem(value: Sides.putsOnly, child: Text('Puts only')),
            ],
            onChanged: (v) => set(s.copyWith(sides: v)),
          )),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Skip weekly expiry day (Tuesday)'),
        value: s.skipExpiryDay,
        onChanged: (v) => set(s.copyWith(skipExpiryDay: v)),
      ),
    ]);
  }
}

class _SupertrendControls extends StatelessWidget {
  const _SupertrendControls();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.supertrend;
    void set(SupertrendStrategy n) => app.edit(() => app.supertrend = n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledSlider(
          label: 'ATR period',
          value: s.period.toDouble(),
          min: 5,
          max: 30,
          divisions: 25,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => set(s.copyWith(period: v.round()))),
      LabeledSlider(
          label: 'Multiplier',
          value: s.multiplier,
          min: 1,
          max: 5,
          divisions: 16,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => set(s.copyWith(multiplier: double.parse(v.toStringAsFixed(2))))),
      _Labeled('First entry', DropdownButton<int>(value: s.fromMin, items: _timeItems(9 * 60 + 20, 12 * 60, 5), onChanged: (v) => set(s.copyWith(fromMin: v)))),
      _Labeled('Last entry', DropdownButton<int>(value: s.toMin, items: _timeItems(10 * 60, 15 * 60, 15), onChanged: (v) => set(s.copyWith(toMin: v)))),
      _Labeled('Strike', _strikeDropdown(s.strikeOffset, (v) => set(s.copyWith(strikeOffset: v)))),
    ]);
  }
}

class _StraddleControls extends StatelessWidget {
  const _StraddleControls();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.straddle;
    void set(StraddleStrategy n) => app.edit(() => app.straddle = n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoticeBanner(
          icon: Icons.warning_amber_rounded,
          text: 'Option SELLING: needs roughly ₹1.5-2.5 lakh margin per lot and can lose far more than the premium on a gap.'),
      _Labeled('Entry (candle close)', DropdownButton<int>(value: s.entryMin, items: _timeItems(9 * 60 + 20, 12 * 60, 5), onChanged: (v) => set(s.copyWith(entryMin: v)))),
      LabeledSlider(
          label: 'Stop per leg (premium rise)',
          value: s.stopPct,
          min: 10,
          max: 100,
          divisions: 18,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => set(s.copyWith(stopPct: v.roundToDouble()))),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Skip weekly expiry day (Tuesday)'),
        value: s.skipExpiryDay,
        onChanged: (v) => set(s.copyWith(skipExpiryDay: v)),
      ),
    ]);
  }
}

// ------------------------------------------------------------------------------------------------- results
class _Results extends StatelessWidget {
  const _Results();

  @override
  Widget build(BuildContext context) => const PageBody(maxWidth: 1000, children: [_ResultsColumn()]);
}

class _ResultsColumn extends StatelessWidget {
  const _ResultsColumn();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final r = app.result;
    if (r == null) {
      return SectionCard(
        title: 'No results yet',
        child: Row(children: [
          if (app.running) const Padding(padding: EdgeInsets.only(right: 12), child: CircularProgressIndicator()),
          Expanded(child: Text(app.running ? 'Running the backtest...' : 'Press "Run backtest".')),
        ]),
      );
    }
    final m = r.metrics;
    final edge = r.edgeOverNoise;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (app.stale && !app.running)
        const NoticeBanner(icon: Icons.refresh, text: 'Settings changed since this run. Press "Run backtest" to update.'),
      Text('${r.strategy.title}: ${r.strategy.summary}', style: Theme.of(context).textTheme.titleMedium),
      Text('${r.fills.lots} lot(s), spread ₹${(r.fills.halfSpread * 2).toStringAsFixed(1)}, slippage ₹${r.fills.slippage.toStringAsFixed(2)}, '
          '${r.dates.length} sessions ${r.dates.first} to ${r.dates.last}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        MetricTile(label: 'Net P&L', value: inr(m.net, sign: true), color: pnlColor(context, m.net), hint: 'After spread, slippage and charges'),
        MetricTile(
            label: 'Edge over noise',
            value: edge == null ? 'off' : '${inr(edge, sign: true)}${r.noiseStdError == null ? '' : ' ±${inrCompact(r.noiseStdError!)}'}',
            color: pnlColor(context, edge),
            width: 220,
            hint: 'Real result minus the average of ${r.noiseNets.length} zero-drift noise runs (noise mean ${inr(r.noiseMean, sign: true)}). '
                '± is the standard error of that average: use more noise runs for a tighter estimate.'),
        MetricTile(label: 'Trades', value: '${m.trades}', hint: '${m.tradingDays} of ${m.days} days traded'),
        MetricTile(label: 'Win rate', value: pct(m.winRate)),
        MetricTile(label: 'Profit factor', value: num2(m.profitFactor), hint: 'Gross wins / gross losses; above 1 is profitable'),
        MetricTile(label: 'Max drawdown', value: inr(m.maxDrawdown), hint: 'Largest fall from a peak, trade by trade'),
        MetricTile(label: 'Avg win / loss', value: '${inr(m.avgWin)} / ${inr(m.avgLoss)}', width: 220),
        MetricTile(label: 'Worst trade', value: inr(m.worstTrade, sign: true), color: pnlColor(context, m.worstTrade)),
        MetricTile(label: 'Sharpe (annualised)', value: num2(m.sharpe), hint: 'Daily mean / daily std x sqrt(252). Very high values usually mean the model flatters the strategy'),
        MetricTile(
            label: 'Daily mean 95% CI',
            value: m.dailyCi95 == null ? '-' : '${inrCompact(m.dailyCi95!.$1)} to ${inrCompact(m.dailyCi95!.$2)}',
            hint: 'Bootstrap interval of the mean daily P&L. If it includes 0, the sample cannot tell the strategy from luck',
            width: 220),
      ]),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Equity curve vs noise',
        subtitle: 'Bold: real market. Grey: the same strategy on zero-drift noise days (shuffled, randomly mirrored bars).',
        child: LineChart(
          height: 300,
          xLabels: ['start', for (final d in r.dates) d.substring(5)],
          series: [
            for (var n = 0; n < r.noiseDaily.length; n++)
              LineSeries('noise', cumulative(r.noiseDaily[n]), Colors.grey, width: 1.2, faint: true, showInLegend: n == 0),
            LineSeries('real market', cumulative(r.daily), Theme.of(context).colorScheme.primary, width: 2.8),
          ],
        ),
      ),
      SectionCard(title: 'How trades ended', child: _ReasonTable(r)),
      SectionCard(title: 'Trades', subtitle: 'Tap a trade to see it on the chart', child: _TradeTable(r)),
    ]);
  }
}

class _ReasonTable extends StatelessWidget {
  const _ReasonTable(this.r);

  final BacktestResult r;

  @override
  Widget build(BuildContext context) {
    final rows = r.byReason().entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    return DataTable(columns: const [
      DataColumn(label: Text('Exit')),
      DataColumn(label: Text('Trades'), numeric: true),
      DataColumn(label: Text('Total'), numeric: true),
      DataColumn(label: Text('Average'), numeric: true),
    ], rows: [
      for (final e in rows)
        DataRow(cells: [
          DataCell(Text(reasonLabel(e.key))),
          DataCell(Text('${e.value.$1}')),
          DataCell(Text(inr(e.value.$2, sign: true), style: TextStyle(color: pnlColor(context, e.value.$2)))),
          DataCell(Text(inr(e.value.$2 / e.value.$1, sign: true))),
        ]),
    ]);
  }
}

class _TradeTable extends StatelessWidget {
  const _TradeTable(this.r);

  final BacktestResult r;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (r.trades.isEmpty) return const Text('No trades with these settings.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 18,
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Option')),
          DataColumn(label: Text('In')),
          DataColumn(label: Text('Out')),
          DataColumn(label: Text('Entry'), numeric: true),
          DataColumn(label: Text('Exit'), numeric: true),
          DataColumn(label: Text('How')),
          DataColumn(label: Text('Net'), numeric: true),
        ],
        rows: [
          for (final t in r.trades)
            DataRow(
              onSelectChanged: (_) => app.openReplay(t.date),
              cells: [
                DataCell(Text(t.date)),
                DataCell(Text('${t.short ? 'Sell ' : ''}${t.strike} ${t.side}')),
                DataCell(Text(t.entryTime)),
                DataCell(Text(t.exitTime)),
                DataCell(Text(t.entry.toStringAsFixed(2))),
                DataCell(Text(t.exit.toStringAsFixed(2))),
                DataCell(Text(reasonLabel(t.reason))),
                DataCell(Text(inr(t.net, sign: true), style: TextStyle(color: pnlColor(context, t.net)))),
              ],
            ),
        ],
      ),
    );
  }
}
