import '../../shared/area_remote_settings/application/area_snapshot_scope.dart';

class EmailConfig {
  final String to;

  const EmailConfig({required this.to});

  static const String gmailSuffix = '@gmail.com';

  static Future<EmailConfig> load() async {
    final area = await AreaSnapshotScope.readCurrentArea();
    return EmailConfig(to: area?.email.trim() ?? '');
  }

  static String normalizeToList(String raw) {
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  static bool isValidToList(String csv) {
    final list = csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    if (list.isEmpty) return false;
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    for (final addr in list) {
      if (!regex.hasMatch(addr)) return false;
    }
    return true;
  }

  static String normalizeGmailLocalPart(String raw) {
    return raw.trim().toLowerCase();
  }

  static String normalizeGmailLocalPartList(String raw) {
    return raw
        .split(',')
        .map(normalizeGmailLocalPart)
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  static bool isValidGmailLocalPart(String raw) {
    final value = normalizeGmailLocalPart(raw);
    if (value.isEmpty || value.length > 64) return false;
    if (value.contains('@')) return false;
    if (value.startsWith('.') || value.endsWith('.')) return false;
    if (value.contains('..')) return false;
    return RegExp(r'^[a-z0-9.]+$').hasMatch(value);
  }

  static bool isValidGmailLocalPartList(String raw) {
    final normalized = normalizeGmailLocalPartList(raw);
    final parts = normalized
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return false;
    return parts.every(isValidGmailLocalPart);
  }

  static String gmailAddressListFromLocalParts(String raw) {
    final normalized = normalizeGmailLocalPartList(raw);
    if (!isValidGmailLocalPartList(normalized)) {
      throw const FormatException('invalid gmail local part list');
    }
    return normalized
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => '$value$gmailSuffix')
        .join(', ');
  }

  static Future<EmailConfig> saveLocal(String raw) async {
    final normalized = normalizeToList(raw);
    if (!isValidToList(normalized)) {
      throw const FormatException('invalid email list');
    }
    final updated = await AreaSnapshotScope.updateCurrentAreaEmail(normalized);
    final stored = updated.email.trim();
    if (stored != normalized) {
      throw StateError('local email verification failed');
    }
    return EmailConfig(to: stored);
  }
}
