import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';
import '../../screens/service_mode/type_package/common_widgets/reverse_sheet_package/services/parking_completed_logger.dart';
import '../../screens/service_mode/type_package/common_widgets/reverse_sheet_package/services/status_mapping.dart';

// import '../../utils/usage_reporter.dart';

/// 🔹 중복 번호판 전용 도메인 예외
class DuplicatePlateException implements Exception {
  final String message;

  DuplicatePlateException(this.message);

  @override
  String toString() => message;
}

/// ✅ parking_completed_view "쓰기(Upsert/Delete)"를 기기 로컬 토글(SharedPreferences)로 제어
/// - UI 토글과 동일 키를 사용해야 실제로 연동됩니다.
/// - 이 클래스는 "쓰기 지점"에서만 사용합니다(트랜잭션 내부에서 prefs 읽기 금지 → 트랜잭션 밖에서 값 확보).
class _ParkingCompletedViewWriteGate {
  static const String prefsKey = 'parking_completed_realtime_write_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
  }

  /// ✅ 항상 prefs에서 최신 값을 읽어옵니다(캐싱된 bool을 들고 있지 않음)
  static Future<bool> canWrite() async {
    await _ensureLoaded();
    return _prefs!.getBool(prefsKey) ?? false; // 기본 OFF
  }
}

class PlateCreationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ✅ (변경) 2안용: 경량 View 컬렉션명
  static const String _parkingCompletedViewCollection = 'parking_completed_view';

  /// ✅ (추가) 정기(월정기) 전용 컬렉션명
  static const String _monthlyPlateStatusCollection = 'monthly_plate_status';

  static final Map<String, Map<String, dynamic>> _billCache = {};
  static final Map<String, DateTime> _billCacheExpiry = {};
  static const Duration _billTtl = Duration(minutes: 10);

  /// ✅ (추가) view 문서(=area) 안에 들어갈 item payload
  Map<String, dynamic> _buildParkingCompletedViewItem({
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) {
    final safeLocation = location.isNotEmpty ? location : '미지정';
    return <String, dynamic>{
      // key는 items.{plateDocId}
      plateDocId: <String, dynamic>{
        PlateFields.plateNumber: plateNumber,
        PlateFields.location: safeLocation,
        // 이 값은 해당 차량의 "입차 완료 시각"
        'parkingCompletedAt': FieldValue.serverTimestamp(),
        PlateFields.updatedAt: FieldValue.serverTimestamp(),
      },
    };
  }

  Future<Map<String, dynamic>?> _getBillCached({
    required String? billingType,
    required String area,
  }) async {
    if (billingType == null || billingType.trim().isEmpty) return null;
    final key = '${billingType}_$area';
    final now = DateTime.now();

    final exp = _billCacheExpiry[key];
    final cached = _billCache[key];
    if (cached != null && exp != null && exp.isAfter(now)) {
      // 캐시 히트 → Firestore .get() 미수행, READ 미계측
      return cached;
    }

    final billDoc = await _firestore.collection('bill').doc(key).get();

    /*await UsageReporter.instance.report(
      area: area,
      action: 'read',
      n: 1,
      source: 'PlateCreationService.addPlate.billRead',
    );*/

    if (billDoc.exists) {
      final data = billDoc.data()!;
      _billCache[key] = data;
      _billCacheExpiry[key] = now.add(_billTtl);
      return data;
    } else {
      _billCache.remove(key);
      _billCacheExpiry.remove(key);
      return null;
    }
  }

  Future<void> addPlate({
    required String plateNumber,
    required String location,
    required String area,
    required PlateType plateType,
    required String userName,
    String? billingType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    required String region,
    List<String>? imageUrls,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
    required String selectedBillType,
  }) async {
    // ✅ plates 문서명(documentId) = {plateNumber}_{area}
    final String plateDocId = '${plateNumber}_$area';

    // ✅ (핵심) parking_completed_view 쓰기 가능 여부(트랜잭션 밖에서 미리 확보)
    final bool canWriteView = await _ParkingCompletedViewWriteGate.canWrite();
    if (kDebugMode) {
      debugPrint('🧩 [PlateCreationService] canWrite parking_completed_view = $canWriteView');
    }

    int? regularAmount;
    int? regularDurationHours;

    // ── bill 캐시 사용 (정기 아닌 경우만)
    if (selectedBillType != '정기' && billingType != null && billingType.isNotEmpty) {
      try {
        final billData = await _getBillCached(billingType: billingType, area: area);
        if (billData == null) {
          throw Exception('Firestore에서 정산 데이터를 찾을 수 없음');
        }
        basicStandard = billData['basicStandard'] ?? 0;
        basicAmount = billData['basicAmount'] ?? 0;
        addStandard = billData['addStandard'] ?? 0;
        addAmount = billData['addAmount'] ?? 0;
        regularAmount = billData['regularAmount'];
        regularDurationHours = billData['regularDurationHours'];
      } catch (e, st) {
        try {
          await DebugDatabaseLogger().log({
            'op': 'bill.read.forPlateCreation',
            'collection': 'bill',
            'docId': '${billingType}_$area',
            'inputs': {
              'billingType': billingType,
              'area': area,
              'selectedBillType': selectedBillType,
            },
            'error': {
              'type': e.runtimeType.toString(),
              if (e is FirebaseException) 'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['bill', 'read', 'error'],
          }, level: 'error');
        } catch (_) {}
        debugPrint("🔥 정산 정보 로드 실패: $e");
        throw Exception("Firestore 정산 정보 로드 실패: $e");
      }
    } else if (selectedBillType == '정기') {
      // 정기 과금은 기본/추가 0으로
      basicStandard = 0;
      basicAmount = 0;
      addStandard = 0;
      addAmount = 0;
    }

    final plateFourDigit =
    plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;

    // billingType이 없으면 요금 잠금 처리
    final effectiveIsLockedFee = isLockedFee || (billingType == null || billingType.trim().isEmpty);

    final base = PlateModel(
      id: plateDocId,
      plateNumber: plateNumber,
      plateFourDigit: plateFourDigit,
      type: plateType.firestoreValue,
      requestTime: DateTime.now(),
      endTime: endTime,
      location: location.isNotEmpty ? location : '미지정',
      area: area,
      userName: userName,
      billingType: billingType,
      statusList: statusList ?? [],
      basicStandard: basicStandard ?? 0,
      basicAmount: basicAmount ?? 0,
      addStandard: addStandard ?? 0,
      addAmount: addAmount ?? 0,
      region: region,
      imageUrls: imageUrls,
      isSelected: false,
      selectedBy: null,
      isLockedFee: effectiveIsLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
      paymentMethod: paymentMethod,
      customStatus: customStatus,
      regularAmount: regularAmount,
      regularDurationHours: regularDurationHours,
    );

    // ✅ 로그 병합(트랜잭션 안에서 한꺼번에 기록)
    PlateModel plateWithLog = base.addLog(
      action: '생성',
      performedBy: userName,
      from: '',
      to: base.location,
    );
    final entryLabel = (plateType == PlateType.parkingRequests) ? '입차 요청' : plateType.label;
    plateWithLog = plateWithLog.addLog(
      action: entryLabel,
      performedBy: userName,
      from: '-',
      to: entryLabel,
    );

    final docRef = _firestore.collection('plates').doc(plateDocId);

    // 🔹 이 호출에서 "처음부터 입차 완료(parking_completed)로 생성"된 경우를 감지하기 위한 플래그
    bool createdAsParkingCompleted = false;

    try {
      int writes = 0;
      int reads = 0;

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        reads += 1; // ✅ tx.get → read 1

        // ✅ (변경) viewRef는 "지역(area) 문서" 1개
        final viewRef = _firestore.collection(_parkingCompletedViewCollection).doc(area);

        if (snap.exists) {
          final data = snap.data();
          final existingTypeStr = (data?['type'] as String?) ?? '';
          final existingType = PlateType.values.firstWhere(
                (t) => t.firestoreValue == existingTypeStr,
            orElse: () => PlateType.parkingRequests,
          );

          if (!_isAllowedDuplicate(existingType)) {
            debugPrint("🚨 중복된 번호판 등록 시도: $plateNumber (${existingType.name})");
            throw DuplicatePlateException("이미 등록된 번호판입니다: $plateNumber");
          } else {
            // 기존 logs 보존 + 신규 로그 append
            final List<Map<String, dynamic>> existingLogs = (() {
              final raw = data?['logs'];
              if (raw is List) {
                return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
              }
              return <Map<String, dynamic>>[];
            })();

            final List<Map<String, dynamic>> newLogs =
            (plateWithLog.logs ?? []).map((e) => e.toMap()).toList();
            final List<Map<String, dynamic>> mergedLogs = [...existingLogs, ...newLogs];

            final partial = <String, dynamic>{
              PlateFields.type: plateType.firestoreValue,
              PlateFields.updatedAt: FieldValue.serverTimestamp(),
              if (base.location.isNotEmpty) PlateFields.location: base.location,
              if (endTime != null) PlateFields.endTime: endTime,
              if (billingType != null && billingType.trim().isNotEmpty) PlateFields.billingType: billingType,
              if (imageUrls != null) PlateFields.imageUrls: imageUrls,
              if (paymentMethod != null) PlateFields.paymentMethod: paymentMethod,
              if (lockedAtTimeInSeconds != null) PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
              if (lockedFeeAmount != null) PlateFields.lockedFeeAmount: lockedFeeAmount,
              PlateFields.isLockedFee: effectiveIsLockedFee,
              PlateFields.logs: mergedLogs,
            };

            // ✅ parking_completed로 “등록/갱신”하는 경우:
            // - plates에도 parkingCompletedAt 기록
            // - view(area 문서)의 items.{plateDocId} upsert (단, canWriteView=true일 때만)
            if (plateType == PlateType.parkingCompleted) {
              partial['parkingCompletedAt'] = FieldValue.serverTimestamp();

              if (canWriteView) {
                tx.set(
                  viewRef,
                  <String, dynamic>{
                    PlateFields.area: area,
                    PlateFields.updatedAt: FieldValue.serverTimestamp(),
                    'items': _buildParkingCompletedViewItem(
                      plateDocId: plateDocId,
                      plateNumber: plateNumber,
                      location: base.location,
                    ),
                  },
                  SetOptions(merge: true),
                );
                writes += 1; // view set(merge)
              } else {
                if (kDebugMode) {
                  debugPrint('🚫 [PlateCreationService] skip parking_completed_view upsert (toggle OFF)');
                }
              }
            }

            final bool wasLocked = (data?['isLockedFee'] == true);
            if (wasLocked) {
              final countersRef = _firestore.collection('plate_counters').doc('area_$area');
              tx.set(
                countersRef,
                {'departureCompletedEvents': FieldValue.increment(1)},
                SetOptions(merge: true),
              );
              writes += 1; // counters set
            }

            tx.update(docRef, partial);
            writes += 1; // plates update
          }
        } else {
          // 신규 set: 로그 2건 포함
          final map = plateWithLog.toMap();
          map[PlateFields.updatedAt] = FieldValue.serverTimestamp();

          // ✅ 처음부터 parking_completed로 생성되는 경우:
          // - plates 문서에도 parkingCompletedAt 기록
          // - view(area 문서)의 items.{plateDocId} upsert (단, canWriteView=true일 때만)
          if (plateType == PlateType.parkingCompleted) {
            map['parkingCompletedAt'] = FieldValue.serverTimestamp();

            if (canWriteView) {
              tx.set(
                viewRef,
                <String, dynamic>{
                  PlateFields.area: area,
                  PlateFields.updatedAt: FieldValue.serverTimestamp(),
                  'items': _buildParkingCompletedViewItem(
                    plateDocId: plateDocId,
                    plateNumber: plateNumber,
                    location: base.location,
                  ),
                },
                SetOptions(merge: true),
              );
              writes += 1; // view set(merge)
            } else {
              if (kDebugMode) {
                debugPrint('🚫 [PlateCreationService] skip parking_completed_view upsert (toggle OFF)');
              }
            }

            createdAsParkingCompleted = true; // (SQLite 유지 플래그)
          }

          tx.set(docRef, map);
          writes += 1; // plates set
        }
      });

      // 🔹 트랜잭션 종료 후: 처음부터 parking_completed 로 만든 경우에만 SQLite 기록(기존 유지)
      if (createdAsParkingCompleted) {
        // ignore: unawaited_futures
        ParkingCompletedLogger.instance.maybeLogCompleted(
          plateNumber: plateNumber,
          location: location.isNotEmpty ? location : '미지정',
          oldStatus: kStatusEntryRequest,
          newStatus: kStatusEntryDone,
        );
      }

      if (reads > 0) {
        /*await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: reads,
          source: 'PlateCreationService.addPlate.tx',
        );*/
      }
      if (writes > 0) {
        /*await UsageReporter.instance.report(
          area: area,
          action: 'write',
          n: writes,
          source: 'PlateCreationService.addPlate.tx',
        );*/
      }
    } on DuplicatePlateException {
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plate.create.transaction',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': plateDocId,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'location': location,
            'plateType': plateType.firestoreValue,
            'selectedBillType': selectedBillType,
            'billingType': billingType,
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plate', 'create', 'transaction', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }

    // =========================================================================
    // ✅ (리팩터링) 메모/상태 upsert
    // - 정기(selectedBillType == '정기')   → monthly_plate_status 에만 저장 (plate_status 금지)
    // - 그 외                              → plate_status 저장(+expireAt 유지)
    //
    // 기존 문제 원인: customStatus가 있으면 무조건 plate_status에 expireAt 포함 set() 하던 블록
    // =========================================================================
    final String memo = (customStatus ?? '').trim();
    final List<String> statuses = (statusList ?? const <String>[])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final bool hasMemoOrStatus = memo.isNotEmpty || statuses.isNotEmpty;
    if (!hasMemoOrStatus) return;

    final bool isMonthly = selectedBillType.trim() == '정기';
    final String targetCollection = isMonthly ? _monthlyPlateStatusCollection : 'plate_status';
    final statusDocRef = _firestore.collection(targetCollection).doc(plateDocId);

    final payload = <String, dynamic>{
      'customStatus': memo,
      'statusList': statuses,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': userName,
      'area': area,
      if (isMonthly) 'type': '정기',
      // 정기에서 countType이 필요하다면 billingType을 보조로 적재(프로젝트 정책에 따라 제거 가능)
      if (isMonthly && billingType != null && billingType.trim().isNotEmpty) 'countType': billingType.trim(),
      // 비정기(plate_status)에서만 TTL 유지
      if (!isMonthly)
        'expireAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1)),
        ),
    };

    try {
      await statusDocRef.set(payload, SetOptions(merge: true));
      /*await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'PlateCreationService.addPlate.statusUpsert/$targetCollection',
      );*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': isMonthly ? 'monthlyPlateStatus.upsert.set' : 'plateStatus.upsert.set',
          'collection': targetCollection,
          'docPath': statusDocRef.path,
          'docId': plateDocId,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'selectedBillType': selectedBillType,
            'statusListLen': statuses.length,
            'customStatusLen': memo.length,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': [
            isMonthly ? 'monthlyPlateStatus' : 'plateStatus',
            'upsert',
            'set',
            'error',
          ],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': isMonthly ? 'monthlyPlateStatus.upsert.unknown' : 'plateStatus.upsert.unknown',
          'collection': targetCollection,
          'docPath': statusDocRef.path,
          'docId': plateDocId,
          'inputs': {
            'plateNumber': plateNumber,
            'area': area,
            'selectedBillType': selectedBillType,
            'statusListLen': statuses.length,
            'customStatusLen': memo.length,
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': [
            isMonthly ? 'monthlyPlateStatus' : 'plateStatus',
            'upsert',
            'error',
          ],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  bool _isAllowedDuplicate(PlateType type) {
    // ✅ 출차 완료(departureCompleted)는 중복 허용
    return type == PlateType.departureCompleted;
  }
}
