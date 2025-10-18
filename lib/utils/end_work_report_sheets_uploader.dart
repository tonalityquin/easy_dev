// lib/utils/end_work_report_sheets_uploader.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

import 'sheets_config.dart';
// ✅ 전역 OAuth 세션만 사용 (초기화는 main.dart에서 1회 수행)
import 'google_auth_session.dart';

class EndWorkReportSheetsUploader {
  /// 기본 시트(탭) 이름
  static const String _defaultSheetName = '업무종료보고';

  /// A: createdAt
  /// B: division
  /// C: area
  /// D: vehicleInput
  /// E: vehicleOutput
  /// F: totalLockedFee
  /// G: uploadedBy
  static const List<String> _header = [
    'createdAt',
    'division',
    'area',
    'vehicleInput',
    'vehicleOutput',
    'totalLockedFee',
    'uploadedBy',
  ];

  // ─────────────────────────────────────────
  // 공개 API
  // ─────────────────────────────────────────

  /// GCS 업로드가 끝난 뒤 시트에 한 줄 append
  /// - 링크/카운트(보고/로그 URL, snapshotCount)는 더 이상 시트에 쓰지 않음.
  /// - [sheetName]을 지정하면 해당 탭으로 기록(기본: '업무종료보고')
  static Future<bool> appendRow({
    required Map<String, dynamic> reportJson,
    String sheetName = _defaultSheetName,
  }) async {
    final spreadsheetId = await SheetsConfig.getEndReportSheetId();
    if (spreadsheetId == null || spreadsheetId.isEmpty) {
      debugPrint('❌ [EndWorkReport] spreadsheetId가 비어 있습니다. 설정 화면에서 저장 필요.');
      return false;
    }

    auth.AuthClient? client;
    try {
      // ✅ 중앙 세션에서 재사용 가능한 AuthClient 제공 (별도 로그인 UI 없음)
      client = await GoogleAuthSession.instance.client();
      final api = SheetsApi(client);

      // 1) 탭 존재 보장(없으면 자동 생성)
      await _ensureSheetExists(api, spreadsheetId, sheetName);

      // 2) 헤더 보장(없으면 A1:G1에 생성)
      await _ensureHeader(api, spreadsheetId, sheetName);

      // 3) 행 생성 및 append
      final createdAt = (reportJson['createdAt'] ?? '').toString(); // ISO
      final division = (reportJson['division'] ?? '').toString();
      final area = (reportJson['area'] ?? '').toString();
      final vc = (reportJson['vehicleCount'] ?? {}) as Map;
      final vehicleInput = vc['vehicleInput'] ?? 0;
      final vehicleOutput = vc['vehicleOutput'] ?? 0;
      final totalLockedFee = reportJson['totalLockedFee'] ?? 0;
      final uploadedBy = (reportJson['uploadedBy'] ?? '').toString();

      final row = [
        createdAt,
        division,
        area,
        vehicleInput,
        vehicleOutput,
        totalLockedFee,
        uploadedBy,
      ];

      await api.spreadsheets.values.append(
        ValueRange(values: [row]),
        spreadsheetId,
        '$sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('✅ [EndWorkReport] 스프레드시트 append 성공 -> $sheetName');
      return true;
    } catch (e) {
      debugPrint('❌ [EndWorkReport] 스프레드시트 append 실패: $e');
      return false;
    } finally {
      client?.close();
    }
  }

  // ─────────────────────────────────────────
  // 내부 유틸
  // ─────────────────────────────────────────

  /// 탭 존재 확인 후 없으면 생성
  static Future<void> _ensureSheetExists(
      SheetsApi api,
      String spreadsheetId,
      String sheetName,
      ) async {
    final meta = await api.spreadsheets.get(spreadsheetId);
    final exists =
    (meta.sheets ?? const <Sheet>[]).any((s) => s.properties?.title == sheetName);

    if (exists) return;

    await api.spreadsheets.batchUpdate(
      BatchUpdateSpreadsheetRequest(
        requests: [
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(title: sheetName),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
    debugPrint('ℹ️ [EndWorkReport] 시트 탭이 없어 새로 생성: $sheetName');
  }

  /// A1에 헤더가 없으면 생성 (A1:G1)
  static Future<void> _ensureHeader(
      SheetsApi api,
      String spreadsheetId,
      String sheetName,
      ) async {
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A1:G1',
    );

    final hasHeader =
    (res.values != null && res.values!.isNotEmpty && res.values!.first.isNotEmpty);
    if (hasHeader) return;

    await api.spreadsheets.values.update(
      ValueRange(values: [_header]),
      spreadsheetId,
      '$sheetName!A1',
      valueInputOption: 'RAW',
    );
    debugPrint('ℹ️ [EndWorkReport] 헤더가 없어 A1에 생성 완료: $sheetName');
  }
}
