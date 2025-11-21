// File: lib/utils/end_work_report_sheets_uploader.dart

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/sheets/v4.dart';

import 'sheets_config.dart';
// ✅ 전역 OAuth 세션만 사용 (초기화는 main.dart에서 1회 수행)
import 'google_auth_session.dart';

// 🔎 API 실패 시 분석용 로그 기록
import '../screens/dev_package/debug_package/debug_api_logger.dart';

/// 업무 종료 보고를 "업무종료보고" 시트 탭에 한 줄씩 적재하는 유틸
///
/// - GCS 업로드(보고/로그 JSON)가 끝난 뒤 이 유틸을 호출하여 시트에 기록
/// - 스프레드시트 ID는 [SheetsConfig.getEndReportSheetId]에서 가져옴
/// - OAuth / 토큰 만료(401 / invalid_token) 시 ClockOutLogUploader와 동일하게
///   1회 토큰 강제 재검증 + 재시도까지 수행
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
  ///
  /// - [reportJson]은 EndWorkReportService에서 생성한 보고 JSON
  ///   (예: division, area, vehicleCount, metrics, createdAt, uploadedBy 등)
  /// - 링크/카운트(보고/로그 URL, snapshotCount)는 더 이상 시트에 쓰지 않음.
  /// - [sheetName]을 지정하면 해당 탭으로 기록(기본: '업무종료보고')
  /// - Google 토큰 만료/invalid_token 발생 시 한 번 토큰을 강제 갱신 후 재시도
  /// - 모든 시도가 실패하면 false 반환
  static Future<bool> appendRow({
    required Map<String, dynamic> reportJson,
    String sheetName = _defaultSheetName,
  }) async {
    // 🔎 로깅용 필드들 (catch 블록에서도 참조할 수 있도록 바깥에서 선언)
    String? spreadsheetId;
    String division = '';
    String area = '';
    String uploadedBy = '';
    String createdAt = '';
    num totalLockedFee = 0;

    Future<bool> runOnce({required bool allowRethrowInvalid}) async {
      try {
        // 1) 스프레드시트 ID 확인
        spreadsheetId = await SheetsConfig.getEndReportSheetId();
        if (spreadsheetId == null || spreadsheetId!.isEmpty) {
          const msg =
              '업무 종료 보고 업로드 실패: 업무종료보고 시트 ID(end_report_sheet_id)가 설정되지 않았습니다.\n'
              '관리자에게 업무종료보고 스프레드시트 ID를 설정해 달라고 요청해 주세요.';
          debugPrint('❌ [EndWorkReport] $msg');

          // 운영 관점에서 중요한 설정 누락이므로 로그 남김
          await DebugApiLogger().log(
            {
              'tag': 'EndWorkReportSheetsUploader.appendRow',
              'message': '업무 종료 보고 업로드 실패 - end_report_sheet_id 미설정',
              'reason': 'missing_spreadsheet_id',
              'spreadsheetId': spreadsheetId,
              'sheetName': sheetName,
              'reportJson': reportJson,
            },
            level: 'error',
            tags: const ['sheets', 'end_work_report'],
          );

          return false;
        }

        // 2) reportJson에서 값 추출 (필드 값들을 미리 꺼내서 로깅에도 사용)
        createdAt = (reportJson['createdAt'] ?? '').toString(); // ISO 문자열
        division = (reportJson['division'] ?? '').toString();
        area = (reportJson['area'] ?? '').toString();
        uploadedBy = (reportJson['uploadedBy'] ?? '').toString();

        final vc = (reportJson['vehicleCount'] ?? {}) as Map;
        final vehicleInput = vc['vehicleInput'] ?? 0;
        final vehicleOutput = vc['vehicleOutput'] ?? 0;

        // ⚠️ 기존 코드에서는 reportJson['totalLockedFee']만 보던 상태였으나,
        // 실제로는 metrics.snapshot_totalLockedFee에 들어 있으므로 우선 그 값을 사용.
        final metrics = (reportJson['metrics'] ?? {}) as Map;
        totalLockedFee =
        (reportJson['totalLockedFee'] ?? metrics['snapshot_totalLockedFee'] ?? 0)
        as num;

        // 3) 중앙 OAuth 세션에서 AuthClient 획득
        final authClient = await GoogleAuthSession.instance.safeClient();
        final api = SheetsApi(authClient);

        // 4) 탭 존재 보장(없으면 자동 생성)
        await _ensureSheetExists(api, spreadsheetId!, sheetName);

        // 5) 헤더 보장(없으면 A1:G1에 생성)
        await _ensureHeader(api, spreadsheetId!, sheetName);

        // 6) 행 생성 및 append
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
          spreadsheetId!,
          '$sheetName!A1',
          valueInputOption: 'USER_ENTERED',
        );

        debugPrint(
          '✅ [EndWorkReport] 스프레드시트 append 성공 -> sheet="$sheetName", '
              'area="$area", division="$division", uploadedBy="$uploadedBy"',
        );

        return true;
      } catch (e, st) {
        final msg = '업무 종료 보고를 스프레드시트에 기록하는 중 오류가 발생했습니다. ($e)';
        debugPrint('❌ [EndWorkReport] $msg');

        // 🔴 실제 예외(네트워크/권한 문제 등)는 API 로거에 상세히 기록
        await DebugApiLogger().log(
          {
            'tag': 'EndWorkReportSheetsUploader.appendRow',
            'message': '업무 종료 보고 스프레드시트 append 중 예외 발생',
            'reason': 'exception',
            'error': e.toString(),
            'stack': st.toString(),
            'spreadsheetId': spreadsheetId,
            'sheetName': sheetName,
            'division': division,
            'area': area,
            'uploadedBy': uploadedBy,
            'createdAt': createdAt,
            'totalLockedFee': totalLockedFee,
            'reportJson': reportJson,
          },
          level: 'error',
          tags: const ['sheets', 'end_work_report'],
        );

        // invalid_token 계열이면 한 번은 rethrow해서 바깥에서 refreshIfNeeded()를 유도
        if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
          rethrow;
        }

        return false;
      }
    }

    // 첫 번째 시도: invalid_token이면 예외를 바깥으로 던져 토큰 재발급/재시도를 유도
    try {
      return await runOnce(allowRethrowInvalid: true);
    } catch (e) {
      // invalid_token 계열이면 토큰 강제 갱신 후 한 번 더 시도
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        debugPrint(
            '⚠️ [EndWorkReport] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...');

        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
        } catch (refreshError, refreshSt) {
          // 토큰 갱신 단계에서 실패해도 추가로 로깅만 남기고 false 반환
          await DebugApiLogger().log(
            {
              'tag': 'EndWorkReportSheetsUploader.appendRow',
              'message': '토큰 강제 갱신(refreshIfNeeded) 실패',
              'reason': 'refresh_failed',
              'error': refreshError.toString(),
              'stack': refreshSt.toString(),
              'spreadsheetId': spreadsheetId,
              'sheetName': sheetName,
              'division': division,
              'area': area,
              'uploadedBy': uploadedBy,
              'createdAt': createdAt,
              'totalLockedFee': totalLockedFee,
              'reportJson': reportJson,
            },
            level: 'error',
            tags: const ['sheets', 'end_work_report', 'auth'],
          );
          return false;
        }

        // 토큰 갱신 후 두 번째 시도 (이때는 invalid_token이어도 rethrow 안 함)
        return await runOnce(allowRethrowInvalid: false);
      }

      // invalid_token 이외의 예외는 여기까지 올라온 시점에서는 이미 로깅이 되어 있으므로
      // 별도 처리 없이 false만 반환
      debugPrint(
          '❌ [EndWorkReport] 스프레드시트 업로드 중 알 수 없는 오류가 발생했습니다. ($e)');
      return false;
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
