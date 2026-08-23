import '../../shared/area_remote_settings/application/area_snapshot_scope.dart';

class EmailConfig {
  final String to;

  const EmailConfig({required this.to});

  static Future<EmailConfig> load() async {
    final area = await AreaSnapshotScope.readCurrentArea();
    return EmailConfig(to: area?.email.trim() ?? '');
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
}
