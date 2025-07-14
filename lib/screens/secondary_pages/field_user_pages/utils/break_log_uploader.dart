import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';

class BreakLogUploader {
  // 🟡 Google Sheets 설정
  static const _spreadsheetId = '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo'; // 사용자 제공 ID
  static const _sheetName = '휴게기록'; // Google Sheets에서 사용 중인 시트 탭 이름
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  /// ✅ 휴게 기록을 Google Sheets에 업로드
  static Future<bool> uploadBreakJson({
    required BuildContext context,
    required Map<String, dynamic> data, // recordedTime 포함
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

      // 📋 업로드할 데이터 행 구성
      final row = [
        dateStr,
        recordedTime,
        userId,
        userName,
        area,
        division,
        '휴게', // 상태
      ];

      // 🔐 서비스 계정 인증 및 Sheets API 클라이언트 생성
      final client = await _getSheetsClient();
      final sheetsApi = SheetsApi(client);

      // 📤 Google Sheets에 행 추가 (append)
      await sheetsApi.spreadsheets.values.append(
        ValueRange(values: [row]),
        _spreadsheetId,
        '$_sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('✅ 휴게 기록 업로드 완료 (Google Sheets)');
      return true;
    } catch (e) {
      debugPrint('❌ 휴게 기록 업로드 실패: $e');
      return false;
    }
  }

  /// 🔐 Google Sheets API 사용을 위한 인증 클라이언트 생성
  static Future<AuthClient> _getSheetsClient() async {
    final jsonStr = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonStr);
    return await clientViaServiceAccount(
      credentials,
      [SheetsApi.spreadsheetsScope],
    );
  }

  /// (옵션) 다운로드용 URL 등 구성할 경우, 기존 getDownloadPath는 생략하거나 수정 가능
  static String getDownloadPath({
    required String division,
    required String area,
    required String userId,
    DateTime? dateTime,
  }) {
    // GCS 다운로드 URL은 더 이상 필요 없음
    return 'https://docs.google.com/spreadsheets/d/$_spreadsheetId/edit';
  }
}
