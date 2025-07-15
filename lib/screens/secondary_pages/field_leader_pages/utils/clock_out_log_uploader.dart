import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';

class ClockOutLogUploader {
  // 🔐 Google Sheets 설정
  static const _spreadsheetId = '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo';
  static const _sheetName = '기록'; // ✅ 통합 시트 이름
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  /// ✅ 퇴근 기록 업로드 (중복 방지 포함)
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
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final recordedTime = data['recordedTime'] ?? '';
      final status = '퇴근';

      // ✅ [1] 중복 체크
      final existingRows = await _loadAllRecords();
      final isDuplicate = existingRows.any((row) =>
      row.length >= 7 &&
          row[0] == dateStr &&
          row[2] == userId &&
          row[6] == status
      );

      if (isDuplicate) {
        debugPrint('⚠️ 이미 퇴근 기록이 존재합니다.');
        return false;
      }

      // ✅ [2] 업로드할 행 구성
      final row = [
        dateStr,
        recordedTime,
        userId,
        userName,
        area,
        division,
        status,
      ];

      final client = await _getSheetsClient();
      final sheetsApi = SheetsApi(client);

      // ✅ [3] 시트에 행 추가
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

  /// 📥 기록 시트 전체 불러오기 (중복 검사용)
  static Future<List<List<String>>> _loadAllRecords() async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final result = await sheetsApi.spreadsheets.values.get(
      _spreadsheetId,
      '$_sheetName!A2:G',
    );

    client.close();

    return result.values?.map((row) =>
        row.map((cell) => cell.toString()).toList()
    ).toList() ?? [];
  }

  /// (옵션) 시트 링크 반환
  static String getDownloadPath({
    required String division,
    required String area,
    required String userId,
    DateTime? dateTime,
  }) {
    return 'https://docs.google.com/spreadsheets/d/$_spreadsheetId/edit';
  }
}
