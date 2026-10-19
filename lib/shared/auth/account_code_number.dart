import 'dart:math';

import 'package:flutter/services.dart';

enum UserCodeEntryMode {
  generated,
  developerManual,
}

class AccountCodeNumber {
  static const int length = 11;
  static const String _letters = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  const AccountCodeNumber._();

  static String generate({Random? random}) {
    final source = random ?? Random.secure();
    final chars = List<String>.generate(
      length,
      (_) => _alphabet[source.nextInt(_alphabet.length)],
      growable: false,
    );
    if (!chars.any(_isLetter)) {
      chars[source.nextInt(length)] = _letters[source.nextInt(_letters.length)];
    }
    if (!chars.any(_isDigit)) {
      var index = source.nextInt(length);
      if (_isLetter(chars[index]) && chars.where(_isLetter).length == 1) {
        index = (index + 1) % length;
      }
      chars[index] = _digits[source.nextInt(_digits.length)];
    }
    return chars.join();
  }

  static String normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String format(String value) {
    final normalized = normalize(value);
    final clipped = normalized.length > length
        ? normalized.substring(0, length)
        : normalized;
    if (clipped.length <= 3) return clipped;
    if (RegExp(r'^[0-9]{10}$').hasMatch(clipped)) {
      return '${clipped.substring(0, 3)}-${clipped.substring(3, 6)}-${clipped.substring(6)}';
    }
    if (clipped.length <= 7) {
      return '${clipped.substring(0, 3)}-${clipped.substring(3)}';
    }
    return '${clipped.substring(0, 3)}-${clipped.substring(3, 7)}-${clipped.substring(7)}';
  }

  static bool isValid(String value) {
    final normalized = normalize(value);
    if (RegExp(r'^[0-9]{10,11}$').hasMatch(normalized)) return true;
    return isGeneratedCode(normalized);
  }

  static bool isGeneratedCode(String value) {
    final normalized = normalize(value);
    if (!RegExp(r'^[a-z0-9]{11}$').hasMatch(normalized)) return false;
    return normalized.split('').any(_isLetter) &&
        normalized.split('').any(_isDigit);
  }

  static bool isDeveloperManualCode(String value) {
    return RegExp(r'^\d{11}$').hasMatch(value.trim());
  }

  static String documentId({
    required String codeNumber,
    required String area,
  }) {
    final normalized = normalize(codeNumber);
    final normalizedArea = area.trim();
    if (!isValid(normalized) || normalizedArea.isEmpty) return '';
    return '$normalized-$normalizedArea';
  }

  static String mask(String value) {
    final normalized = normalize(value);
    if (RegExp(r'^[0-9]{10}$').hasMatch(normalized)) {
      return '${normalized.substring(0, 3)}-***-${normalized.substring(6)}';
    }
    if (normalized.length != length) return normalized.isEmpty ? '-' : '***';
    return '${normalized.substring(0, 3)}-****-${normalized.substring(7)}';
  }

  static String maskDocumentId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '-';
    final separator = normalized.indexOf('-');
    if (separator <= 0 || separator >= normalized.length - 1) {
      return mask(normalized);
    }
    final codeNumber = normalized.substring(0, separator);
    final area = normalized.substring(separator + 1);
    final masked = mask(codeNumber);
    return area.isEmpty ? masked : '$masked-$area';
  }

  static bool _isLetter(String value) => RegExp(r'^[a-z]$').hasMatch(value);

  static bool _isDigit(String value) => RegExp(r'^[0-9]$').hasMatch(value);
}

class AccountCodeNumberInputFormatter extends TextInputFormatter {
  const AccountCodeNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = AccountCodeNumber.normalize(newValue.text);
    final clipped = normalized.length > AccountCodeNumber.length
        ? normalized.substring(0, AccountCodeNumber.length)
        : normalized;
    final formatted = AccountCodeNumber.format(clipped);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
