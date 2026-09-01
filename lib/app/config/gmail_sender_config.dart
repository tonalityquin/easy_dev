import 'package:shared_preferences/shared_preferences.dart';

class GmailSenderConfig {
  GmailSenderConfig._();

  static const String domain = 'gmail.com';
  static const String suffix = '@gmail.com';
  static const String _localPartKey = 'gmail_sender_local_part_v1';

  static Future<String?> readLocalPart() async {
    final prefs = await SharedPreferences.getInstance();
    final value = normalizeLocalPart(prefs.getString(_localPartKey) ?? '');
    return isValidLocalPart(value) ? value : null;
  }

  static Future<String?> readEmail() async {
    final localPart = await readLocalPart();
    return localPart == null ? null : '$localPart$suffix';
  }

  static Future<void> setLocalPart(String rawLocalPart) async {
    final localPart = normalizeLocalPart(rawLocalPart);
    if (!isValidLocalPart(localPart)) {
      throw const FormatException('gmail_sender_local_part_invalid');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localPartKey, localPart);
  }

  static Future<bool> initializeFromEmailIfUnset(String? email) async {
    final current = await readLocalPart();
    if (current != null) return false;
    final localPart = localPartFromEmail(email);
    if (localPart == null || !isValidLocalPart(localPart)) return false;
    await setLocalPart(localPart);
    return true;
  }

  static String normalizeLocalPart(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.endsWith(suffix)) {
      normalized = normalized.substring(0, normalized.length - suffix.length);
    }
    return normalized.trim();
  }

  static String? localPartFromEmail(String? email) {
    final normalized = email?.trim().toLowerCase() ?? '';
    if (!normalized.endsWith(suffix)) return null;
    final localPart = normalized.substring(0, normalized.length - suffix.length);
    return localPart.isEmpty ? null : localPart;
  }

  static String emailForLocalPart(String localPart) {
    return '${normalizeLocalPart(localPart)}$suffix';
  }

  static bool isValidLocalPart(String value) {
    final normalized = normalizeLocalPart(value);
    if (normalized.isEmpty || normalized.length > 64) return false;
    if (normalized.startsWith('.') || normalized.endsWith('.')) return false;
    if (normalized.contains('..')) return false;
    return RegExp(r'^[a-z0-9.]+$').hasMatch(normalized);
  }
}
