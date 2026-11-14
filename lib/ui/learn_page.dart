import 'package:flutter/material.dart';

import 'widgets.dart';

class _Topic {
  const _Topic(this.icon, this.title, this.paragraphs, [this.bullets = const []]);

  final IconData icon;
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

const _topics = [
  _Topic(Icons.science_outlined, 'How this lab works', [
    'Nifty 50 index candles (5-minute) and India VIX are real market data. Option premiums are modelled with Black-Scholes, '
        'using the bar\'s India VIX as the implied volatility and the nearest weekly Tuesday expiry, on a trading-time clock: '
        'time decay is paid during market hours and each night counts as a quarter of a session.',
    'Every strategy pays the bid/ask spread and slippage on each order plus Zerodha-style charges (brokerage, STT, exchange, '
        'SEBI, GST, stamp duty). Inside a candle the stop is checked before the target, a stop that gaps fills at the open, and a '
        'target only fills if the bid reaches it. All trades are intraday and closed by 15:15.',
  ], [
    'Edge over noise: each strategy also runs on "noise" days built from the same bars, shuffled and randomly mirrored. '
        'That keeps the volatility but removes trend and momentum. A buying strategy that is no better on the real market than '
        'on noise has no demonstrated edge.',
    'The default settings reproduce the Python trading bot\'s backtest trade for trade; automated tests check this on every build.',
  ]),
  _Topic(Icons.open_in_full, 'Opening-range breakout (ORB)', [
    'Mark the high and low of the first 15 minutes (09:15-09:30). The first 5-minute candle that CLOSES above the range buys the '
        'at-the-money call; one that closes below buys the put. Stop if the premium falls 30%, target at +60%, otherwise sell at '
        '15:15. One trade a day, no re-entry, entries until 13:00.',
    'With a 2:1 reward-to-risk ratio you need to win roughly one trade in three (about 35-36% after costs) to break even, so '
        'a few percent of win rate decides the result.',
  ], [
    'Why it can work: the opening range absorbs overnight news; a clean break often starts the day\'s trend.',
    'Why it is hard: false breakouts, time decay when price stalls, and the target needs a move close to a full day\'s range.',
    'Try in the lab: a 30-minute range, a trailing-free tighter target, calls or puts only, skipping expiry Tuesday.',
  ]),
  _Topic(Icons.timeline, 'Supertrend flip', [
    'Supertrend is a trailing band at a multiple of the Average True Range around the price. When the 5-minute close crosses '
        'the band the direction flips: buy the call on a flip up, the put on a flip down, and exit (and reverse) on the next flip.',
  ], [
    'It catches every trend but whipsaws in sideways markets, paying the spread and time decay on each false flip.',
  ]),
  _Topic(Icons.compare_arrows, 'Short straddle (option selling)', [
    'Sell the at-the-money call and put at 09:20; each leg has its own stop at +30% of the premium received; whatever is left '
        'is bought back at 15:15. It profits when Nifty stays in a range and option prices decay.',
    'Sellers collect the volatility risk premium: implied volatility (VIX) is usually above the volatility that actually '
        'happens. That is why this strategy also makes money on noise days in the model.',
  ], [
    'Needs roughly ₹1.5-2.5 lakh margin per lot (less with protective far out-of-the-money wings).',
    'The model has no volatility skew, no IV spike when a leg is stopped out and no event-day gaps beyond the sample, so it '
        'overstates the results. A very high Sharpe ratio here is a warning sign, not a promise.',
  ]),
  _Topic(Icons.show_chart, 'Buy & hold futures', [
    'Buy one lot of Nifty futures on the first day and hold to the last day. One lot controls about 65 x Nifty (around '
        '₹16 lakh) for roughly ₹2 lakh of margin, so each Nifty point is ₹65 of profit or loss.',
    'Losses are settled every day. A large drawdown means margin calls; without extra cash the broker closes the position, '
        'often near the bottom. Monthly expiries also force rollovers, which cost spread and charges.',
  ], [
    'It is a benchmark for "just being long the market", not a trading method; its result depends entirely on the start and end dates.',
    'The same view without leverage: a Nifty ETF, with no margin calls or rollovers.',
  ]),
  _Topic(Icons.rule, 'The playbook, EMA crossover and random baseline', [
    'The playbook buys options on a 5/9 EMA crossover confirmed by RSI, MACD, VWAP, support/resistance room and an '
        'opening-range filter, with a 15-point stop, a 20-point first target, then breakeven and a 9-EMA trailing stop. '
        'Its results come from the Python bot\'s full engine (without the open-interest filter, which has no history).',
    'The bare EMA crossover uses the same exits without the filters, showing what the filters add. The random baseline enters '
        'at random times with the same exits: anything that cannot beat it is not using real information.',
  ]),
  _Topic(Icons.analytics_outlined, 'Reading the numbers', [], [
    'Profit factor: gross wins / gross losses. Above 1 is profitable; 1.2-1.5 is good for intraday systems.',
    'Max drawdown: the largest fall from a peak. Size positions so you can live through two or three times this.',
    'Sharpe ratio: average daily return / its volatility, annualised. Above 1 is good; above 3 in a backtest usually means '
        'something is too optimistic.',
    'Daily mean 95% confidence interval: if it includes zero, this sample cannot tell the strategy apart from luck.',
    'Win rate alone means little: it has to be read together with the average win and loss.',
  ]),
  _Topic(Icons.gpp_maybe_outlined, 'Limits and disclaimer', [
    'This is an educational tool. The sample is short (about three months), the option prices are modelled, and past results do '
        'not predict future ones. Real fills, liquidity, margin rules and charges differ. Nothing here is investment advice. '
        'Paper-trade any strategy for several weeks before risking money, and start with one lot.',
  ]),
];

class LearnPage extends StatelessWidget {
  const LearnPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PageBody(maxWidth: 900, children: [
      Text('Learn the strategies', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      for (final (n, topic) in _topics.indexed)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: n == 0,
            leading: Icon(topic.icon),
            title: Text(topic.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in topic.paragraphs) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p)),
              for (final b in topic.bullets) Bullet(b),
            ],
          ),
        ),
    ]);
  }
}
