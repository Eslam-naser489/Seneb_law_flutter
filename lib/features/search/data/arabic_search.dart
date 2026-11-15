import 'package:sqlite3/sqlite3.dart';

String normalizeArabic(String input) {
  final output = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    if ((rune >= 0x610 && rune <= 0x61a) ||
        (rune >= 0x64b && rune <= 0x65f) ||
        rune == 0x670 ||
        (rune >= 0x6d6 && rune <= 0x6ed) ||
        rune == 0x640) {
      continue;
    }
    output.writeCharCode(switch (rune) {
      0x622 || 0x623 || 0x625 || 0x671 => 0x627,
      0x629 => 0x647,
      0x649 => 0x64a,
      >= 0x660 && <= 0x669 => rune - 0x660 + 48,
      >= 0x6f0 && <= 0x6f9 => rune - 0x6f0 + 48,
      _ => rune,
    });
  }
  return output.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _digits(String value) =>
    normalizeArabic(value).replaceAll(RegExp(r'[^0-9]'), '');

String normalizeEgyptianPhone(String value) {
  var digits = _digits(value);
  if (digits.startsWith('0020')) digits = digits.substring(2);
  if (digits.length == 12 && digits.startsWith('201')) {
    digits = '0${digits.substring(2)}';
  }
  return digits;
}

void registerSearchFunctions(Database db) {
  for (final entry in <String, String Function(String)>{
    'office_normalize': normalizeArabic,
    'office_phone': normalizeEgyptianPhone,
    'office_digits': _digits,
  }.entries) {
    db.createFunction(
      functionName: entry.key,
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      function: (args) => entry.value(args.first as String? ?? ''),
    );
  }
}
