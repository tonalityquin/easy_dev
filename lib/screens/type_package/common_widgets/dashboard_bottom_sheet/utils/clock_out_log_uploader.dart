// lib/screens/.../ClockOutLogUploader.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../utils/sheets_config.dart';

class ClockOutLogUploader {
  static const _sheetName = '출퇴근기록';

  // ─────────────────────────────────────────
  // OAuth 헬퍼
  // ─────────────────────────────────────────
  /// ✅ GCP “웹 애플리케이션” 클라이언트 ID
  static const String _kWebClientId =
      '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

  static bool _gsInitialized = false;

  static Future<void> _ensureGsInitialized() async {
    if (_gsInitialized) return;
    try {
      await GoogleSignIn.instance.initialize(serverClientId: _kWebClientId);
    } catch (_) {}
    _gsInitialized = true;
  }

  static Future<GoogleSignInAccount> _waitForSignInEvent() async {
    final signIn = GoogleSignIn.instance;
    final c = Completer<GoogleSignInAccount>();
    late final StreamSubscription sub;

    sub = signIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          if (!c.isCompleted) c.complete(event.user);
        case GoogleSignInAuthenticationEventSignOut():
          break;
      }
    }, onError: (e) {
      if (!c.isCompleted) c.completeError(e);
    });

    try {
      try {
        await signIn.attemptLightweightAuthentication();
      } catch (_) {}
      if (signIn.supportsAuthenticate()) {
        await signIn.authenticate(); // 필요 시 UI
      }
      return await c.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw Exception('Google 로그인 응답 시간 초과'),
      );
    } finally {
      await sub.cancel();
    }
  }

  static Future<auth.AuthClient> _getSheetsAuthClientRW() async {
    await _ensureGsInitialized();
    const scopes = [SheetsApi.spreadsheetsScope]; // RW
    final user = await _waitForSignInEvent();
    var authorization =
    await user.authorizationClient.authorizationForScopes(scopes);
    authorization ??=
    await user.authorizationClient.authorizeScopes(scopes);
    return authorization.authClient(scopes: scopes);
  }

  // ─────────────────────────────────────────
  // 업로드/조회 로직
  // ─────────────────────────────────────────
  static Future<bool> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedArea = prefs.getString('selectedArea')?.trim() ?? '';

      final spreadsheetId = await SheetsConfig.getCommuteSheetId();
      if (spreadsheetId == null || spreadsheetId.isEmpty) {
        debugPrint('❌ 퇴근 업로드 실패: 스프레드시트 ID가 설정되지 않았습니다. (commute_sheet_id)');
        return false;
      }

      final userName = data['userName']?.toString().trim() ?? '';
      final userId = data['userId']?.toString().trim() ?? '';
      final division = data['division']?.toString().trim() ?? '';
      final recordedTime = data['recordedTime']?.toString().trim() ?? '';

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      const status = '퇴근';
      final area = selectedArea;

      if (userId.isEmpty || userName.isEmpty || division.isEmpty || recordedTime.isEmpty) {
        debugPrint('❌ 필수 항목 누락: userId=$userId, userName=$userName, division=$division, recordedTime=$recordedTime');
        return false;
      }

      // 중복 검사
      final existingRows = await _loadAllRecords(spreadsheetId);
      final isDuplicate = existingRows.any(
            (row) =>
        row.length >= 7 &&
            row[0] == dateStr &&
            row[2] == userId &&
            row[6] == status,
      );
      if (isDuplicate) {
        debugPrint('⚠️ 이미 퇴근 기록이 존재합니다.');
        return false;
      }

      // 업로드
      final row = [dateStr, recordedTime, userId, userName, area, division, status];
      auth.AuthClient? client;
      try {
        client = await _getSheetsAuthClientRW();
        final sheetsApi = SheetsApi(client);
        await sheetsApi.spreadsheets.values.append(
          ValueRange(values: [row]),
          spreadsheetId,
          '$_sheetName!A1',
          valueInputOption: 'USER_ENTERED',
        );
      } finally {
        client?.close();
      }

      debugPrint('✅ 퇴근 기록 업로드 완료 ($area)');
      return true;
    } catch (e) {
      debugPrint('❌ 퇴근 기록 업로드 실패: $e');
      return false;
    }
  }

  static Future<List<List<String>>> _loadAllRecords(String spreadsheetId) async {
    auth.AuthClient? client;
    try {
      client = await _getSheetsAuthClientRW(); // RW(조회도 포함)
      final sheetsApi = SheetsApi(client);
      final result = await sheetsApi.spreadsheets.values.get(
        spreadsheetId,
        '$_sheetName!A2:G',
      );
      return result.values
          ?.map((row) => row.map((cell) => cell.toString()).toList())
          .toList() ??
          [];
    } finally {
      client?.close();
    }
  }
}
