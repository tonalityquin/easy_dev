import 'dart:convert';
import 'package:flutter/material.dart';

// ▼ SQLite (경로는 프로젝트에 맞게 조정하세요)
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

class OfflineInputPlateService {
  /// 차량 입차 등록을 SQLite `offline_plates`에 기록합니다.
  ///
  /// 정책:
  /// - 위치가 확정된 경우(status_type: 'parkingCompleted'), 아니면 'parkingRequests'
  /// - plate_key: "plateNumber|area" 규칙으로 구성 (UNIQUE)
  /// - 이미 같은 plate_number+area 레코드가 있으면 최신 1건을 UPDATE, 없으면 INSERT
  /// - selectedStatuses는 logs(JSON)로 보관, customStatus는 custom_status 컬럼에 저장
  static Future<bool> registerPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected, // 위치 확정 여부(확정이면 parkingCompleted)
    required String? selectedBill,
    required List<String> selectedStatuses,
    required int basicStandard,
    required int basicAmount,
    required int addStandard,
    required int addAmount,
    required String region,
    String? customStatus,
    required String selectedBillType, // '변동' | '고정' | '정기'
  }) async {
    const String kStatusParkingRequests  = 'parkingRequests';
    const String kStatusParkingCompleted = 'parkingCompleted';

    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();

    final uid = (session?.userId ?? '').trim();
    final uname = (session?.name ?? '').trim();
    final area = await _loadCurrentArea();

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final plateFour = _extractLast4Digits(plateNumber);
    final plateKey = '$plateNumber|$area';

    // '정기'는 금액/기준 0으로 강제
    final int finalBasicStandard = (selectedBillType == '정기') ? 0 : basicStandard;
    final int finalBasicAmount  = (selectedBillType == '정기') ? 0 : basicAmount;
    final int finalAddStandard  = (selectedBillType == '정기') ? 0 : addStandard;
    final int finalAddAmount    = (selectedBillType == '정기') ? 0 : addAmount;

    final String logsJson = jsonEncode({
      'statuses': selectedStatuses,
      'selectedBillType': selectedBillType,
      'savedAt': now.toIso8601String(),
      'by': uname,
    });

    // 위치 선택 여부에 따라 최종 상태 결정
    final String finalStatus =
    isLocationSelected ? kStatusParkingCompleted : kStatusParkingRequests;

    return await db.transaction<bool>((txn) async {
      // 기존 레코드 탐색: 동일 plate_number + area, 최신 1건
      final existing = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id'],
        where: 'plate_number = ? AND area = ?',
        whereArgs: [plateNumber, area],
        orderBy: 'created_at DESC',
        limit: 1,
      );

      final values = <String, Object?>{
        'plate_key': plateKey,
        'plate_number': plateNumber,
        'plate_four_digit': plateFour,
        'region': region,
        'area': area,
        'location': location,
        'billing_type': selectedBill ?? '',
        'custom_status': (customStatus ?? '').trim(),
        'basic_amount': finalBasicAmount,
        'basic_standard': finalBasicStandard,
        'add_amount': finalAddAmount,
        'add_standard': finalAddStandard,
        'is_locked_fee': 0,
        'locked_fee_amount': 0,
        'status_type': finalStatus,                // ★ 핵심: 상태 반영
        'updated_at': nowMs,
        'request_time': '$nowMs',                 // TEXT 컬럼에 epoch ms 문자열로 저장(정렬 일관성)
        'user_name': uname,
        'selected_by': uid,
        'user_adjustment': 0,
        'regular_amount': 0,
        'regular_duration_hours': 0,
        'image_urls': '',
        'logs': logsJson,
      };

      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        final count = await txn.update(
          OfflineAuthDb.tablePlates,
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
        return count > 0;
      } else {
        final insertedId = await txn.insert(
          OfflineAuthDb.tablePlates,
          {
            ...values,
            'created_at': nowMs,
          },
        );
        return insertedId > 0;
      }
    });
  }

  /// 현재 지역 로딩: userId로 우선 조회 → 없으면 isSelected=1 행 사용
  static Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    String area = '';

    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        area = ((r1.first['currentArea'] as String?) ??
            (r1.first['selectedArea'] as String?) ??
            '')
            .trim();
      }
    }

    if (area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        area = ((r2.first['currentArea'] as String?) ??
            (r2.first['selectedArea'] as String?) ??
            '')
            .trim();
      }
    }

    // 마지막 안전장치
    if (area.isEmpty) area = 'HQ 지역';
    return area;
  }

  static String _extractLast4Digits(String plate) {
    final match = RegExp(r'(\d{4})\D*$').firstMatch(plate);
    if (match != null) return match.group(1)!;
    // 숫자만 모아서 뒤 4자리
    final digits = plate.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
  }
}
