import 'package:http/http.dart' as http;
import 'google_auth_session.dart';

class GoogleAuthV7 {
  GoogleAuthV7._();

  static Future<http.Client> authedClient(List<String> _ignoredScopes) async {
    await GoogleAuthSession.instance.refreshIfNeeded();
    return await GoogleAuthSession.instance.safeClient();
  }

  static Future<void> signOut() async {
    await GoogleAuthSession.instance.signOut();
  }
}
