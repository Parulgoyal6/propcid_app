// core/utils/amount_in_words.dart
//
// Indian-numbering word-spelling for a price — Dart port of propcid-main's
// `utility.ts` (`amountToWordsIndian`/`groupIndianDigits`, :119-152) and
// `AmountInWords.tsx`. Digits-only input, no decimals, singular "Lakh"/
// "Crore" only (never plural — matches the reference exactly), blank on
// empty/zero/more-than-12-digits.

const List<String> _ones = [
  '',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];

const List<String> _tens = [
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];

String _under100(int n) {
  if (n < 20) return _ones[n];
  final tens = n ~/ 10;
  final rest = n % 10;
  return rest == 0 ? _tens[tens] : '${_tens[tens]} ${_ones[rest]}';
}

/// Recursive Indian-numbering grouping — ports `indianWords` (utility.ts:128-134).
String _indianWords(int n) {
  if (n == 0) return '';
  if (n < 100) return _under100(n);
  if (n < 1000) {
    final head = '${_ones[n ~/ 100]} Hundred';
    final rest = n % 100;
    return rest == 0 ? head : '$head ${_under100(rest)}';
  }
  if (n < 100000) {
    final head = '${_under100(n ~/ 1000)} Thousand';
    final rest = n % 1000;
    return rest == 0 ? head : '$head ${_indianWords(rest)}';
  }
  if (n < 10000000) {
    final head = '${_under100(n ~/ 100000)} Lakh';
    final rest = n % 100000;
    return rest == 0 ? head : '$head ${_indianWords(rest)}';
  }
  // Crores recurse on the crore count itself, so e.g. 1200 crore spells as
  // "One Thousand Two Hundred Crore" — matches the reference exactly.
  final head = '${_indianWords(n ~/ 10000000)} Crore';
  final rest = n % 10000000;
  return rest == 0 ? head : '$head ${_indianWords(rest)}';
}

String _cleanDigits(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^\d]'), '');
  return digits.replaceFirst(RegExp(r'^0+'), '');
}

/// Spells [value] out in Indian-numbering words (e.g. "Twenty Five Lakh"),
/// or '' when [value] is empty, zero, or more than 12 digits — mirrors
/// `amountToWordsIndian` (utility.ts:141-145) exactly, including its silence
/// on those edge cases.
String amountToWordsIndian(String? value) {
  final digits = _cleanDigits(value);
  if (digits.isEmpty || digits.length > 12) return '';
  final n = int.tryParse(digits);
  if (n == null || n == 0) return '';
  return _indianWords(n);
}

/// [value]'s digits grouped Indian-style (e.g. "45,00,000") — mirrors
/// `groupIndianDigits` (utility.ts:148-152).
String groupIndianDigits(String? value) {
  final digits = _cleanDigits(value);
  if (digits.isEmpty) return '0';
  if (digits.length <= 3) return digits;

  final groups = <String>[digits.substring(digits.length - 3)];
  var remaining = digits.substring(0, digits.length - 3);
  while (remaining.length > 2) {
    groups.add(remaining.substring(remaining.length - 2));
    remaining = remaining.substring(0, remaining.length - 2);
  }
  if (remaining.isNotEmpty) groups.add(remaining);
  return groups.reversed.join(',');
}
