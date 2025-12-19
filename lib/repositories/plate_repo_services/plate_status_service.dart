// lib/repositories/plate_repo_services/plate_status_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';
// import '../../utils/usage_reporter.dart';

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================================================
  // ✅ (리팩터링) plate_status 월 단위 샤딩 경로
  //   plate_status/{area}/months/{yyyyMM}/plates/{plateDocId}
  //
  // - area: 상위 문서
  // - months: 월 단위 서브컬렉션
  // - plates: 실제 상태 문서들이 저장되는 서브컬렉션
  //
  // ✅ (핵심 변경)
  // - docId(문서명)는 반드시 "{plateNumber}_{area}" 유지
  //   예) 72-로-6085_가로수길(캔버스랩)
  //
  // - 기존 "plateKey(하이픈 제거)"는 docId에 사용하지 않고
  //   "검색/정렬/인덱스 목적"으로만 문서 필드로 저장할 수 있음
  // ===========================================================================
  static const String _plateStatusRoot = 'plate_status';
  static const String _monthsSub = 'months';
  static const String _platesSub = 'plates';

  String _monthKey(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}'; // yyyyMM

  String _safeArea(String area) => area.isNotEmpty ? area : 'unknown';

  /// ✅ 문서명(plateDocId) 정책: "{plateNumber}_{area}" 그대로 유지
  String _plateDocId(String plateNumber, String area) =>
      '${plateNumber}_$area';

  /// ✅ (선택) 검색/정렬/인덱스 목적의 정규화 키(하이픈 제거)
  /// - docId에는 사용하지 않습니다.
  String _normalizedPlateKey(String plateNumber) =>
      plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();

  /// ✅ TTL/정리 정책(월 단위 관리 목적):
  /// - 비정기 plate_status는 "다음 달 1일 00:00(UTC)"까지 유지하도록 expireAt을 갱신
  /// - (원하시면 월별 컬렉션 관리만으로 충분하면 expireAt 제거도 가능)
  DateTime _nextMonthStartUtc(DateTime dt) => DateTime.utc(dt.year, dt.month + 1, 1);

  DocumentReference<Map<String, dynamic>> _docRef(
      String plateNumber,
      String area, {
        DateTime? forDate,
      }) {
    final dt = forDate ?? DateTime.now();
    final month = _monthKey(dt);

    // Firestore 경로 상 doc(area)는 빈 문자열 불가 → 안전 처리
    final safeArea = _safeArea(area);

    // ✅ (핵심) 문서명은 plateDocId = "{plateNumber}_{area}" 유지
    // - 단, area가 빈 값이면 safeArea로 통일 (실제 운영에서는 area가 비어있지 않도록 보장 권장)
    final docId = _plateDocId(plateNumber, safeArea);

    return _firestore
        .collection(_plateStatusRoot)
        .doc(safeArea)
        .collection(_monthsSub)
        .doc(month)
        .collection(_platesSub)
        .doc(docId);
  }

  // ✅ 월정기 전용 컬렉션 참조(기존 유지: 평면 docId = {plateNumber}_{area})
  DocumentReference<Map<String, dynamic>> _monthlyDocRef(String plateNumber, String area) =>
      _firestore.collection('monthly_plate_status').doc('${plateNumber}_$area');

  bool _isEmptyInput(String customStatus, List<String> statusList) =>
      customStatus.trim().isEmpty && statusList.isEmpty;

  /// ✅ 월정기 저장용 "빈 입력" 판정
  /// - 월정기는 customStatus/statusList가 비어있어도 문서를 저장해야 하므로,
  ///   monthly 필드까지 모두 비어있는 경우에만 deleteWhenEmpty를 적용한다.
  bool _isEmptyMonthlyPayload({
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationHours,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
  }) {
    final memoEmpty = customStatus.trim().isEmpty;
    final statusesEmpty = statusList.isEmpty;

    final countTypeEmpty = countType.trim().isEmpty;
    final amountEmpty = regularAmount == 0;
    final durationEmpty = regularDurationHours == 0;

    final regularTypeEmpty = regularType.trim().isEmpty;
    final startEmpty = startDate.trim().isEmpty;
    final endEmpty = endDate.trim().isEmpty;
    final periodUnitEmpty = periodUnit.trim().isEmpty;

    final specialNoteEmpty = (specialNote ?? '').trim().isEmpty;
    final extendedEmpty = isExtended == null;

    return memoEmpty &&
        statusesEmpty &&
        countTypeEmpty &&
        amountEmpty &&
        durationEmpty &&
        regularTypeEmpty &&
        startEmpty &&
        endEmpty &&
        periodUnitEmpty &&
        specialNoteEmpty &&
        extendedEmpty;
  }

  List<DateTime> _candidateMonths(DateTime base, {int lookbackMonths = 1}) {
    final out = <DateTime>[];
    for (int i = 0; i <= lookbackMonths; i++) {
      out.add(DateTime(base.year, base.month - i, 1));
    }
    return out;
  }

  /// plate_status 세팅 (월 단위 샤딩)
  /// - 빈 입력 → deleteWhenEmpty=true면 현재월/직전월까지 삭제(lookbackMonths)
  /// - 값 있음 → tx.get 1 + set(merge) 1
  ///
  /// [forDate]를 주면 해당 월로 저장됨(특정 월 편집/백필용).
  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
    bool deleteWhenEmpty = true,
    Map<String, dynamic>? extra,
    DateTime? forDate,
    int deleteLookbackMonths = 1,
  }) async {
    final dt = forDate ?? DateTime.now();
    final safeArea = _safeArea(area);
    final ref = _docRef(plateNumber, safeArea, forDate: dt);

    try {
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          // ✅ 월별 구조로 분리되었으므로, UX 상 잔존 방지를 위해 현재월/직전월을 함께 삭제(기본 1개월 룩백)
          final months = _candidateMonths(dt, lookbackMonths: deleteLookbackMonths);
          for (final m in months) {
            final r = _docRef(plateNumber, safeArea, forDate: m);
            await r.delete().timeout(const Duration(seconds: 10));
          }
          /*await UsageReporter.instance.report(area: area, action: 'delete', n: months.length,
              source: 'PlateStatusService.setPlateStatus.delete');*/
        }
        return;
      }

      final plateDocId = _plateDocId(plateNumber, safeArea); // ✅ "{plateNumber}_{area}" 유지
      final normalizedKey = _normalizedPlateKey(plateNumber); // ✅ 필드용(선택)
      final monthKey = _monthKey(dt);

      final data = <String, dynamic>{
        ...?extra,

        // ✅ 식별/관리 필드(권장)
        'plateNumber': plateNumber, // 표시용(원본)
        'plateDocId': plateDocId, // ✅ docId와 동일 값(추적/디버깅 편의)
        'plateKey': normalizedKey, // ✅ 하이픈 제거 키(검색/인덱스 목적)
        'monthKey': monthKey, // yyyyMM

        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'area': safeArea,

        // ✅ 월 단위 유지용 TTL(선택 정책)
        'expireAt': Timestamp.fromDate(_nextMonthStartUtc(dt)),
      };

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) data['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));

      /*await UsageReporter.instance.report(area: area, action: 'read', n: 1, source: 'PlateStatusService.setPlateStatus.tx');
      await UsageReporter.instance.report(area: area, action: 'write', n: 1, source: 'PlateStatusService.setPlateStatus.tx');*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.set',
          'collection': _plateStatusRoot,
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'plateDocId': _plateDocId(plateNumber, safeArea),
            'plateKey': _normalizedPlateKey(plateNumber),
            'monthKey': _monthKey(dt),
            'area': safeArea,
            'customStatusLen': customStatus.length,
            'statusListLen': statusList.length,
            'deleteWhenEmpty': deleteWhenEmpty,
            'deleteLookbackMonths': deleteLookbackMonths,
            if (extra != null) 'extraKeys': extra.keys.take(30).toList(),
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.set.timeout',
          'collection': _plateStatusRoot,
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'plateDocId': _plateDocId(plateNumber, safeArea),
            'plateKey': _normalizedPlateKey(plateNumber),
            'monthKey': _monthKey(dt),
            'area': safeArea,
            'deleteWhenEmpty': deleteWhenEmpty,
            'deleteLookbackMonths': deleteLookbackMonths,
          },
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.set.unknown',
          'collection': _plateStatusRoot,
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'plateDocId': _plateDocId(plateNumber, safeArea),
            'plateKey': _normalizedPlateKey(plateNumber),
            'monthKey': _monthKey(dt),
            'area': safeArea,
          },
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'set', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// ✅ 월정기 상태 세팅 (기존 유지: monthly_plate_status는 평면 docId)
  /// - 월정기는 customStatus/statusList가 비어도 저장 가능해야 함
  /// - truly empty payload(월정기 필드까지 전부 empty)일 때만 deleteWhenEmpty 적용
  Future<void> setMonthlyPlateStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationHours,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
    bool deleteWhenEmpty = true,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);
    try {
      final emptyMonthly = _isEmptyMonthlyPayload(
        customStatus: customStatus,
        statusList: statusList,
        countType: countType,
        regularAmount: regularAmount,
        regularDurationHours: regularDurationHours,
        regularType: regularType,
        startDate: startDate,
        endDate: endDate,
        periodUnit: periodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      if (emptyMonthly) {
        if (deleteWhenEmpty) {
          await ref.delete().timeout(const Duration(seconds: 10));
        }
        return;
      }

      final base = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'type': '정기',
        'countType': countType,
        'regularAmount': regularAmount,
        'regularDurationHours': regularDurationHours,
        'regularType': regularType,
        'startDate': startDate,
        'endDate': endDate,
        'periodUnit': periodUnit,
        'area': area,
        if (specialNote != null) 'specialNote': specialNote,
        if (isExtended != null) 'isExtended': isExtended,
      };

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) base['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, base, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthly',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'countType': countType,
            'regularAmount': regularAmount,
            'regularDurationHours': regularDurationHours,
            'regularType': regularType,
            'periodUnit': periodUnit,
            'hasSpecialNote': specialNote != null,
            'isExtended': isExtended,
            'deleteWhenEmpty': deleteWhenEmpty,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthly.timeout',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthly.unknown',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthly', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// ✅ 정기(월정기)일 때: monthly_plate_status에 "메모/상태"만 업데이트
  /// - 핵심: update()를 사용하여 "문서가 없으면 생성되지 않도록" 강제
  /// - skipIfDocMissing=true 이고 not-found면 조용히 return
  Future<void> setMonthlyMemoAndStatusOnly({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    bool skipIfDocMissing = true,
  }) async {
    final ref = _monthlyDocRef(plateNumber, area);

    final data = <String, dynamic>{
      'customStatus': customStatus.trim(),
      'statusList': statusList,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'area': area,
    };

    try {
      await ref.update(data).timeout(const Duration(seconds: 10));
    } on FirebaseException catch (e, st) {
      // 문서 미존재: 정책상 생성하지 않음
      if (skipIfDocMissing && e.code == 'not-found') {
        return;
      }

      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthlyMemoAndStatusOnly',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'customStatusLen': customStatus.length,
            'statusListLen': statusList.length,
            'skipIfDocMissing': skipIfDocMissing,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthlyMemo', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthlyMemoAndStatusOnly.timeout',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area, 'skipIfDocMissing': skipIfDocMissing},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthlyMemo', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.setMonthlyMemoAndStatusOnly.unknown',
          'collection': 'monthly_plate_status',
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {'plateNumber': plateNumber, 'area': area, 'skipIfDocMissing': skipIfDocMissing},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'setMonthlyMemo', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> deletePlateStatus(
      String plateNumber,
      String area, {
        DateTime? forDate,
        int lookbackMonths = 1,
      }) async {
    final dt = forDate ?? DateTime.now();
    final safeArea = _safeArea(area);
    final ref = _docRef(plateNumber, safeArea, forDate: dt);

    try {
      // ✅ 월별 구조이므로 기본적으로 현재월/직전월까지 삭제(lookbackMonths)
      final months = _candidateMonths(dt, lookbackMonths: lookbackMonths);
      for (final m in months) {
        final r = _docRef(plateNumber, safeArea, forDate: m);
        await r.delete();
      }
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.delete',
          'collection': _plateStatusRoot,
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'plateDocId': _plateDocId(plateNumber, safeArea),
            'plateKey': _normalizedPlateKey(plateNumber),
            'monthKey': _monthKey(dt),
            'area': safeArea,
            'lookbackMonths': lookbackMonths,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.delete.timeout',
          'collection': _plateStatusRoot,
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'plateDocId': _plateDocId(plateNumber, safeArea),
            'plateKey': _normalizedPlateKey(plateNumber),
            'monthKey': _monthKey(dt),
            'area': safeArea,
            'lookbackMonths': lookbackMonths,
          },
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plateStatus.delete.unknown',
          'collection': _plateStatusRoot,
          'docPath': ref.path,
          'docId': ref.id,
          'inputs': {
            'plateNumber': plateNumber,
            'plateDocId': _plateDocId(plateNumber, safeArea),
            'plateKey': _normalizedPlateKey(plateNumber),
            'monthKey': _monthKey(dt),
            'area': safeArea,
            'lookbackMonths': lookbackMonths,
          },
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['plateStatus', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
