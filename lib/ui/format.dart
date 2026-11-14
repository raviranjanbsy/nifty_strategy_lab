/// Indian digit grouping: 137257 -> 1,37,257.
String groupIndian(int n) {
  final neg = n < 0;
  var s = n.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return neg ? '-$s' : s;
}

/// Rupees with Indian grouping, e.g. inr(-2005.3) -> '-₹2,005'.
String inr(num? v, {bool sign = false, int decimals = 0}) {
  if (v == null) return '-';
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  var body = groupIndian(int.parse(parts[0]));
  if (decimals > 0) body = '$body.${parts[1]}';
  final zero = double.parse(fixed) == 0;
  final s = zero ? '' : (v < 0 ? '-' : (sign ? '+' : ''));
  return '$s₹$body';
}

/// Short rupee labels for chart axes: ₹1.4L, ₹45k, ₹800.
String inrCompact(num v) {
  final a = v.abs();
  final s = v < 0 ? '-' : '';
  if (a >= 1e7) return '$s₹${(a / 1e7).toStringAsFixed(1)}Cr';
  if (a >= 1e5) return '$s₹${(a / 1e5).toStringAsFixed(a >= 1e6 ? 0 : 1)}L';
  if (a >= 1e3) return '$s₹${(a / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1)}k';
  return '$s₹${a.toStringAsFixed(0)}';
}

String pct(num? v, [int d = 1]) => v == null ? '-' : '${v.toStringAsFixed(d)}%';

String num2(num? v, [int d = 2]) => v == null ? '-' : v.toStringAsFixed(d);

String hm(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

const reasonLabels = {
  'TARGET': 'Target hit',
  'STOP_LOSS': 'Stop-loss hit',
  'FLAT_TIME': '15:15 square-off',
  'ST_FLIP': 'Supertrend flipped',
  'BREAKEVEN_STOP': 'Breakeven stop',
};

String reasonLabel(String r) => reasonLabels[r] ?? r.replaceAll('_', ' ').toLowerCase();

const strategyNames = {
  'playbook': 'Playbook (EMA 5/9 + filters)',
  'ema_cross': 'Bare EMA 5/9 crossover',
  'orb': 'Opening-range breakout',
  'supertrend': 'Supertrend flip',
  'short_straddle_920': '09:20 short straddle (selling)',
  'random': 'Random entries (baseline)',
  'buy_hold': 'Buy & hold futures',
};

String strategyName(String id) => strategyNames[id] ?? id;
