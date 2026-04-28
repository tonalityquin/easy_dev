






import 'package:shared_preferences/shared_preferences.dart';

class EmailConfig {
  final String to; 

  const EmailConfig({required this.to});

  static const _kMailToKey = 'mail.to';

  
  static String _defaultTo() => '';

  static Future<EmailConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final to = (prefs.getString(_kMailToKey) ?? _defaultTo()).trim();
    return EmailConfig(to: to);
  }

  static Future<void> save(EmailConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMailToKey, cfg.to.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMailToKey, _defaultTo());
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
