import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';

class ClockOutLogUploader {
  // 🔐 서비스 계정 키 경로 & Google Sheets 설정
  static const _spreadsheetId = '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo';
  static const _sheetName = '퇴근기록';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  /// ✅ 퇴근 기록 Google Sheets에 업로드
  static Future<bool> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = userState.user?.selectedArea ?? '';
      final division = areaState.currentDivision;
      final userId = userState.user?.id ?? '';
      final userName = userState.name;

      final now = DateTime.now();
      final year = now.year.toString().padLeft(4, '0');
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');
      final dateStr = '$year-$month-$day';
      final recordedTime = data['recordedTime'] ?? '';

      // 📋 Google Sheets에 추가할 행 데이터
      final row = [
        dateStr,
        recordedTime,
        userId,
        userName,
        area,
        division,
        '퇴근',
      ];

      // 🔐 인증 및 Sheets API 클라이언트 생성
      final client = await _getSheetsClient();
      final sheetsApi = SheetsApi(client);

      // 📤 행 데이터 시트에 append
      await sheetsApi.spreadsheets.values.append(
        ValueRange(values: [row]),
        _spreadsheetId,
        '$_sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('✅ 퇴근 기록 업로드 완료 (Google Sheets)');
      return true;
    } catch (e) {
      debugPrint('❌ 퇴근 기록 업로드 실패: $e');
      return false;
    }
  }

  /// 🔐 인증 클라이언트 생성
  static Future<AuthClient> _getSheetsClient() async {
    final jsonStr = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonStr);
    return await clientViaServiceAccount(
      credentials,
      [SheetsApi.spreadsheetsScope],
    );
  }

  /// (선택) GCS처럼 다운로드 링크 제공하려면 사용
  static String getDownloadPath({
    required String division,
    required String area,
    required String userId,
    DateTime? dateTime,
  }) {
    return 'https://docs.google.com/spreadsheets/d/$_spreadsheetId/edit';
  }
}
