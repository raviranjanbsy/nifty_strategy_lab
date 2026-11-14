import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine/session.dart';
import '../engine/strategies.dart';
import 'charts.dart';
import 'format.dart';
import 'widgets.dart';

/// A trade from either the live lab run or the Python reference run.
class _ReplayTrade {
  _ReplayTrade(this.side, this.strike, this.entryMin, this.exitMin, this.entry, this.exit, this.reason, this.net,
      {this.short = false, this.stop, this.target});

  final String side, reason;
  final int strike, entryMin, exitMin;
  final double entry, exit, net;
  final bool short;
  final double? stop, target;

  bool get isCall => side == 'CE';
}

const _refSources = ['playbook', 'ema_cross', 'orb', 'supertrend', 'short_straddle_920'];

class ReplayPage extends StatelessWidget {
  const ReplayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final days = app.realDays;
    final idx = days.indexWhere((d) => d.iso == app.replayDate);
    final day = days[idx < 0 ? days.length - 1 : idx];
    final lab = app.result;
    final source = app.replaySource;

    final trades = <_ReplayTrade>[];
    (double, double, int)? band;
    SessionFactory sessions = app.baseSessions;
    if (source == 'lab') {
      if (lab != null) {
        sessions = app.resultSessions ?? app.baseSessions;
        for (final t in lab.trades.where((t) => t.date == day.iso)) {
          trades.add(_ReplayTrade(t.side, t.strike, t.entryMin, t.exitMin, t.entry, t.exit, t.reason, t.net,
              short: t.short, stop: t.stop, target: t.target));
        }
        final s = lab.strategy;
        if (s is OrbStrategy) {
          final r = s.range(day);
          if (r != null) band = (r.$1, r.$2, s.rangeMinutes ~/ 5);
        }
      }
    } else {
      for (final t in app.reference.tradesOf(source).where((t) => t.date == day.iso)) {
        final short = source == 'short_straddle_920';
        double? stop, target;
        if (source == 'orb') {
          stop = 0.7 * t.entry;
          target = 1.6 * t.entry;
        } else if (short) {
          stop = 1.3 * t.entry;
        }
        trades.add(_ReplayTrade(t.side, t.strike, t.entryMin, t.exitMin, t.entry, t.exit, t.reason, t.net,
            short: short, stop: stop, target: target));
      }
      if (source == 'orb') {
        final r = const OrbStrategy().range(day);
        if (r != null) band = (r.$1, r.$2, 3);
      }
    }
    final sessDay = sessions.real().firstWhere((d) => d.iso == day.iso, orElse: () => day);

    int barOf(int closeMin) => day.closeMin.indexOf(closeMin);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? const Color(0xFF5BD68A) : const Color(0xFF1A7F37);
    final red = dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E);
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final markers = <ChartMarker>[];
    for (final t in trades) {
      final i = barOf(t.entryMin), j = barOf(t.exitMin);
      final bullish = t.short ? false : t.isCall;
      if (i >= 0) {
        markers.add(ChartMarker(i, day.today.close[i], t.short ? grey : (t.isCall ? green : red),
            t.short ? 'sell ${t.side}' : 'buy ${t.side}', up: bullish || t.short));
      }
      if (j >= 0) markers.add(ChartMarker(j, day.today.close[j], grey, 'exit', up: false));
    }
    final total = trades.fold(0.0, (a, t) => a + t.net);

    return PageBody(children: [
      Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton.outlined(
              tooltip: 'Previous day',
              onPressed: idx > 0 ? () => app.setReplay(date: days[idx - 1].iso) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: DropdownButton<String>(
                isExpanded: true,
                value: day.iso,
                items: [
                  for (final d in days.reversed)
                    DropdownMenuItem(
                        value: d.iso,
                        child: Text('${d.iso}  ${_weekday(d.date)}${d.isExpiryDay ? '  (expiry)' : ''}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => app.setReplay(date: v),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Next day',
              onPressed: idx < days.length - 1 ? () => app.setReplay(date: days[idx + 1].iso) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: DropdownButton<String>(
            isExpanded: true,
            value: source,
            items: [
              DropdownMenuItem(
                  value: 'lab',
                  child: Text(lab == null ? 'Strategy lab (not run yet)' : 'Strategy lab: ${lab.strategy.title}', overflow: TextOverflow.ellipsis)),
              for (final s in _refSources)
                DropdownMenuItem(value: s, child: Text('Python run: ${strategyName(s)}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => app.setReplay(source: v),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Nifty 50, ${day.iso}',
        subtitle: band != null
            ? 'Shaded: opening range ${band.$1.toStringAsFixed(1)} - ${band.$2.toStringAsFixed(1)}. Triangles: entries and exits.'
            : 'Triangles: entries and exits.',
        trailing: trades.isEmpty
            ? null
            : Text('${trades.length} trade(s)  ${inr(total, sign: true)}',
                style: TextStyle(color: pnlColor(context, total), fontWeight: FontWeight.w600)),
        child: CandleChart(
          candles: Candles(day.today.open, day.today.high, day.today.low, day.today.close, day.today.minute),
          band: band,
          markers: markers,
          height: 340,
        ),
      ),
      if (trades.isEmpty)
        NoticeBanner(
            text: source == 'lab' && lab == null
                ? 'Run a backtest in the Strategy lab first, or pick one of the Python runs above.'
                : 'No trade on this day for this strategy.'),
      for (final t in trades) _OptionCard(day: sessDay, t: t, green: green, red: red, grey: grey),
    ]);
  }

  static String _weekday(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.day, required this.t, required this.green, required this.red, required this.grey});

  final SessionDay day;
  final _ReplayTrade t;
  final Color green, red, grey;

  @override
  Widget build(BuildContext context) {
    final o = day.option(t.isCall, t.strike);
    final i = day.closeMin.indexOf(t.entryMin), j = day.closeMin.indexOf(t.exitMin);
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      title: '${t.short ? 'Sold' : 'Bought'} ${t.strike} ${t.side}  ${hm(t.entryMin)} -> ${hm(t.exitMin)}',
      subtitle: 'Modelled premium (Black-Scholes, IV from India VIX). Entry ${t.entry.toStringAsFixed(2)}, '
          'exit ${t.exit.toStringAsFixed(2)} (${reasonLabel(t.reason)}), net ${inr(t.net, sign: true)} after costs.',
      trailing: Text(inr(t.net, sign: true), style: TextStyle(color: pnlColor(context, t.net), fontWeight: FontWeight.w700)),
      child: CandleChart(
        height: 240,
        candles: Candles(o.open, o.high, o.low, o.close, day.today.minute),
        lines: [
          HLine(t.entry, cs.primary, 'entry'),
          if (t.stop != null) HLine(t.stop!, red, 'stop'),
          if (t.target != null) HLine(t.target!, green, 'target'),
        ],
        markers: [
          if (i >= 0) ChartMarker(i, o.close[i], cs.primary, t.short ? 'sell' : 'buy', up: !t.short),
          if (j >= 0) ChartMarker(j, o.close[j], grey, 'exit', up: t.short),
        ],
      ),
    );
  }
}
