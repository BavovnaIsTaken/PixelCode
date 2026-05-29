/// Formats a гримні (₲) amount into a compact human-readable string with
/// K / M / B suffixes. Used by the hub toolbar display, shop labels and
/// donation toasts so all currency surfaces stay in sync.
///
/// Examples: 950 → "950", 2_500 → "2.5K", 2_767_300 → "2.8M",
/// 1_100_000_000 → "1.1B".
String formatGrymni(int n) {
  if (n < 0) return '-${formatGrymni(-n)}';
  if (n < 1000) return n.toString();
  // Thresholds bumped slightly so values that would round to "1000.0X"
  // promote to the next unit instead (e.g. 999_950 → "1.0M", not "1000.0K").
  if (n < 999950) return _compact(n, 1000, 'K');
  if (n < 999950000) return _compact(n, 1000000, 'M');
  return _compact(n, 1000000000, 'B');
}

String _compact(int n, int divisor, String suffix) {
  final exact = n % divisor == 0;
  return '${(n / divisor).toStringAsFixed(exact ? 0 : 1)}$suffix';
}
