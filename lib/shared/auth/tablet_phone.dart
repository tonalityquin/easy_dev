class TabletPhone {
  const TabletPhone._();

  static String normalize(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static bool isValid(String value) {
    return RegExp(r'^[0-9]{10,11}$').hasMatch(normalize(value));
  }

  static String format(String value) {
    final digits = normalize(value);
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return digits;
  }

  static String mask(String value) {
    final digits = normalize(value);
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-****-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-***-${digits.substring(6)}';
    }
    if (digits.length <= 4) return digits;
    final visible = digits.substring(digits.length - 4);
    return '***$visible';
  }
}
