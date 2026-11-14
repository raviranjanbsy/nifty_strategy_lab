import 'package:flutter/material.dart';

import '../engine/trading.dart';
import 'format.dart';
import 'widgets.dart';

/// Position-size and break-even calculator for one option-buying trade.
class RiskPage extends StatefulWidget {
  const RiskPage({super.key});

  @override
  State<RiskPage> createState() => _RiskPageState();
}

class _RiskPageState extends State<RiskPage> {
  double capital = 100000;
  double premium = 120;
  double stopPct = 30;
  double targetPct = 60;
  double lots = 1;
  double spread = 1.0;
  double slippage = 0.5;
  static const lotSize = 65;
  static const charges = Charges();

  @override
  Widget build(BuildContext context) {
    final qty = (lots * lotSize).round();
    final buyPx = premium + spread / 2 + slippage;
    final stopPx = premium * (1 - stopPct / 100);
    final stopFill = stopPx - spread / 2 - slippage;
    final tgtPx = premium * (1 + targetPct / 100);
    final cost = buyPx * qty;
    final lossAtStop = (buyPx - stopFill) * qty + charges.order(false, qty, buyPx) + charges.order(true, qty, stopFill);
    final gainAtTarget = (tgtPx - buyPx) * qty - charges.order(false, qty, buyPx) - charges.order(true, qty, tgtPx);
    final breakEven = gainAtTarget <= 0 ? null : 100 * lossAtStop / (lossAtStop + gainAtTarget);
    final riskPct = 100 * lossAtStop / capital;
    final streakTo20 = lossAtStop <= 0 ? null : (0.2 * capital / lossAtStop).floor();
    final niftyPtsStop = (premium - stopPx) / 0.5;
    final niftyPtsTarget = (tgtPx - premium) / 0.5;
    final t = Theme.of(context).textTheme;

    final inputs = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledSlider(
          label: 'Trading capital',
          value: capital,
          min: 25000,
          max: 1000000,
          divisions: 39,
          format: (v) => inr(v),
          onChanged: (v) => setState(() => capital = (v / 25000).round() * 25000)),
      LabeledSlider(
          label: 'Option premium',
          value: premium,
          min: 20,
          max: 400,
          divisions: 76,
          format: (v) => '₹${v.toStringAsFixed(0)}',
          onChanged: (v) => setState(() => premium = v.roundToDouble())),
      LabeledSlider(
          label: 'Lots (65 qty each)', value: lots, min: 1, max: 10, divisions: 9, format: (v) => v.toStringAsFixed(0), onChanged: (v) => setState(() => lots = v)),
      LabeledSlider(
          label: 'Stop-loss (premium drop)',
          value: stopPct,
          min: 5,
          max: 60,
          divisions: 11,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => setState(() => stopPct = v.roundToDouble())),
      LabeledSlider(
          label: 'Target (premium gain)',
          value: targetPct,
          min: 10,
          max: 200,
          divisions: 19,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => setState(() => targetPct = v.roundToDouble())),
      LabeledSlider(
          label: 'Bid/ask spread', value: spread, min: 0, max: 4, divisions: 8, format: (v) => '₹${v.toStringAsFixed(1)}', onChanged: (v) => setState(() => spread = v)),
      LabeledSlider(
          label: 'Slippage per order',
          value: slippage,
          min: 0,
          max: 3,
          divisions: 12,
          format: (v) => '₹${v.toStringAsFixed(2)}',
          onChanged: (v) => setState(() => slippage = v)),
    ]);

    final outputs = Wrap(spacing: 10, runSpacing: 10, children: [
      MetricTile(label: 'Money needed', value: inr(cost), hint: 'Premium paid at the ask plus slippage, x quantity'),
      MetricTile(label: 'Loss at stop', value: inr(-lossAtStop), color: pnlColor(context, -1), hint: 'Including spread, slippage and charges'),
      MetricTile(label: 'Gain at target', value: inr(gainAtTarget, sign: true), color: pnlColor(context, gainAtTarget)),
      MetricTile(label: 'Risk per trade', value: pct(riskPct), color: riskPct > 2 ? pnlColor(context, -1) : null, hint: 'Loss at stop as % of capital. Many traders keep this at 1-2%'),
      MetricTile(label: 'Break-even win rate', value: pct(breakEven), hint: 'You must win more often than this to make money with these exits'),
      MetricTile(label: 'Losing streak to -20%', value: streakTo20 == null ? '-' : '$streakTo20 trades', hint: 'Losses in a row that would cost 20% of capital'),
      MetricTile(label: 'Nifty move to stop', value: '~${niftyPtsStop.toStringAsFixed(0)} pts', hint: 'At-the-money option, delta about 0.5, ignoring time decay'),
      MetricTile(label: 'Nifty move to target', value: '~${niftyPtsTarget.toStringAsFixed(0)} pts', hint: 'At-the-money option, delta about 0.5, ignoring time decay'),
    ]);

    return PageBody(maxWidth: 1000, children: [
      Text('Risk calculator', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Size one option-buying trade before you place it.'),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 800) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: SectionCard(title: 'Trade', child: inputs)),
            const SizedBox(width: 16),
            Expanded(child: SectionCard(title: 'Result', child: outputs)),
          ]);
        }
        return Column(children: [SectionCard(title: 'Trade', child: inputs), SectionCard(title: 'Result', child: outputs)]);
      }),
      if (riskPct > 2)
        NoticeBanner(
            icon: Icons.warning_amber_rounded,
            text: 'This trade risks ${pct(riskPct)} of your capital. A normal losing streak of 8-10 trades would cost '
                '${pct(riskPct * 9, 0)}. Consider a smaller size or more capital.'),
    ]);
  }
}
