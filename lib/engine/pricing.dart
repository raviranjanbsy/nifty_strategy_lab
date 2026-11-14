// Option pricing and the trading-time clock, ported from the Python bot (nifty_bot/backtest.py) so both engines
// produce the same modelled premiums.
import 'dart:math' as math;

const double riskFree = 0.065;
const double divYield = 0.013;

/// Variance accrues while the market is open; each night between sessions counts as [overnightShare] of a session.
/// A calendar clock would put nearly all decay overnight and hand intraday option buyers free gamma.
const int sessionMinutes = 375;
const double overnightShare = 0.25;
const double yearMinutes = 252 * sessionMinutes * (1 + overnightShare);
const int marketOpenMin = 9 * 60 + 15;
const int marketCloseMin = 15 * 60 + 30;
const int flatMin = 15 * 60 + 15;
const int barMinutes = 5;

/// Round half to even, like Python's round() and numpy's np.round.
double roundHalfEven(double x) {
  final f = x.floorToDouble();
  final d = x - f;
  if (d > 0.5) return f + 1;
  if (d < 0.5) return f;
  return f % 2 == 0 ? f : f + 1;
}

/// Standard normal CDF (Abramowitz-Stegun 7.1.26, abs error < 1.5e-7: far below the 0.05 price tick).
double ncdf(double x) {
  final z = x.abs() / math.sqrt(2.0);
  final t = 1.0 / (1.0 + 0.3275911 * z);
  final poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  final erf = 1.0 - poly * math.exp(-z * z);
  return 0.5 * (1.0 + (x >= 0 ? erf : -erf));
}

/// Black-Scholes with a continuous dividend yield.
double bsPrice(double spot, double strike, double tYears, double iv, bool call) {
  final t = math.max(tYears, 1e-9);
  final v = math.max(iv, 1e-4);
  final sd = v * math.sqrt(t);
  final d1 = (math.log(spot / strike) + (riskFree - divYield + 0.5 * v * v) * t) / sd;
  final d2 = d1 - sd;
  if (call) {
    return spot * math.exp(-divYield * t) * ncdf(d1) - strike * math.exp(-riskFree * t) * ncdf(d2);
  }
  return strike * math.exp(-riskFree * t) * ncdf(-d2) - spot * math.exp(-divYield * t) * ncdf(-d1);
}

/// Exchange tick (0.05) with a one-tick floor.
double tick(double x, [double size = 0.05]) => math.max(roundHalfEven(x / size) * size, size);

/// Weekdays Monday..Friday (Dart weekday 1..5).
bool isWeekday(DateTime d) => d.weekday <= DateTime.friday;

DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

/// Years to the expiry close on the trading-time clock, from a bar ending at [barEndMin] (minutes after midnight).
double tradingYears(DateTime day, int barEndMin, DateTime expiry) {
  var mins = math.max(marketCloseMin - barEndMin, 0).toDouble();
  var d = day;
  while (d.isBefore(expiry)) {
    d = addDays(d, 1);
    if (isWeekday(d)) mins += sessionMinutes * (1 + overnightShare);
  }
  return math.max(mins, 5.0) / yearMinutes;
}

/// Nearest Tuesday on/after [d]; if that day was not a trading day (holiday) the expiry moves to the previous one.
DateTime weeklyExpiry(DateTime d, Set<DateTime> tradingDays) {
  final pyWeekday = d.weekday - 1; // Monday = 0, as in Python
  var e = addDays(d, (1 - pyWeekday) % 7);
  final lastKnown = tradingDays.isEmpty ? d : tradingDays.reduce((a, b) => a.isAfter(b) ? a : b);
  while (!e.isAfter(lastKnown) && !tradingDays.contains(e)) {
    e = addDays(e, -1);
  }
  return e.isBefore(d) ? d : e;
}

int atmStrike(double price, int step) => (roundHalfEven(price / step) * step).toInt();

/// ATM shifted [itmSteps] in-the-money (call: lower strike, put: higher strike). Negative = out of the money.
int selectStrike(double price, bool call, int step, int itmSteps) {
  final atm = atmStrike(price, step);
  return call ? atm - itmSteps * step : atm + itmSteps * step;
}
