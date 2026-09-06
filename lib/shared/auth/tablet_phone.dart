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

  static String documentId({
    required String phone,
    required String area,
  }) {
    final digits = normalize(phone);
    final normalizedArea = area.trim();
    if (digits.isEmpty || normalizedArea.isEmpty) return '';
    return '$digits-$normalizedArea';
  }

  static String maskDocumentId(String value) {
    final normalized = value.trim();
    final directDigits = normalize(normalized);
    if ((directDigits.length == 10 || directDigits.length == 11) &&
        RegExp(r'^[0-9-]+$').hasMatch(normalized)) {
      return mask(directDigits);
    }
    final separator = normalized.indexOf('-');
    if (separator <= 0 || separator >= normalized.length - 1) {
      return normalized;
    }
    final phone = normalized.substring(0, separator);
    final area = normalized.substring(separator + 1);
    final digits = normalize(phone);
    if (digits.length != 10 && digits.length != 11) {
      return normalized;
    }
    return '${mask(digits)}-$area';
  }
}
