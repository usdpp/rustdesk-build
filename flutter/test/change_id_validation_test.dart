import 'package:flutter_hbb/common/id_change_validation.dart';

void main() {
  const cases = <String, bool>{
    '123456789': true,
    'Office-PC_01': true,
    'abcdef': true,
    'short': false,
    '-office01': false,
    'office.pc': false,
    'office pc': false,
    '12345678901234567': false,
  };

  for (final entry in cases.entries) {
    final actual = isValidCustomIdFormat(entry.key);
    if (actual != entry.value) {
      throw StateError(
        'Unexpected validation result for ${entry.key}: $actual',
      );
    }
  }
}
