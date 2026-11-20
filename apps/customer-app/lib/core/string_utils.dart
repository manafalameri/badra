extension LatinDigitsExtension on String {
  static const _arabicDigits = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };

  String toLatinDigits() {
    return splitMapJoin(
      RegExp('[٠١٢٣٤٥٦٧٨٩]'),
      onMatch: (m) => _arabicDigits[m.group(0)] ?? m.group(0)!,
      onNonMatch: (n) => n,
    );
  }

  String groupedDigits(int groupSize) {
    final onlyDigits = replaceAll(RegExp('[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < onlyDigits.length; i++) {
      if (i > 0 && i % groupSize == 0) buffer.write(' ');
      buffer.write(onlyDigits[i]);
    }
    return buffer.toString();
  }

  /// Returns the phone number without country code for display.
  /// Example: '967730975496' → '730975496'
  String withoutCountryCode() {
    final digits = toLatinDigits().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 9) return digits.substring(digits.length - 9);
    return digits;
  }

  /// Build the wallet id from the user's phone number.
  /// Wallet id format: '101' + last 9 phone digits (strips country code).
  String toWalletId() {
    final digits = toLatinDigits().replaceAll(RegExp(r'[^0-9]'), '');
    final local = digits.length >= 9
        ? digits.substring(digits.length - 9)
        : digits.padLeft(9, '0');
    return '101$local';
  }
}
