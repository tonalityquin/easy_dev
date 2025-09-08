import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

/// 구글 캘린더 읽기 전용 서비스 (서비스 계정 사용 데모)
class GoogleCalendarService {
  static const _scopes = [gcal.CalendarApi.calendarReadonlyScope];

  final http.Client _base = http.Client();
  auth.AuthClient? _client;
  gcal.CalendarApi? _api;

  Future<void> _ensureAuthClient() async {
    if (_client != null) return;
    // ★ assets에 포함된 서비스계정 키 로드
    final jsonStr =
    await rootBundle.loadString('assets/keys/easydev-97fb6-e31d7e6b30f9.json');
    final Map<String, dynamic> jsonMap = json.decode(jsonStr);

    final creds = auth.ServiceAccountCredentials.fromJson(jsonMap);
    _client = await auth.clientViaServiceAccount(creds, _scopes, baseClient: _base);
    _api = gcal.CalendarApi(_client!);
  }

  Future<List<gcal.Event>> listEvents({
    required String calendarId,
    DateTime? timeMin,
    DateTime? timeMax,
    int maxResults = 100,
  }) async {
    await _ensureAuthClient();
    final resp = await _api!.events.list(
      calendarId,
      timeMin: (timeMin ?? DateTime.now().subtract(const Duration(days: 30))).toUtc(),
      timeMax: (timeMax ?? DateTime.now().add(const Duration(days: 60))).toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
      maxResults: maxResults,
    );
    return resp.items ?? <gcal.Event>[];
  }

  void dispose() {
    _client?.close();
    _base.close();
  }
}
