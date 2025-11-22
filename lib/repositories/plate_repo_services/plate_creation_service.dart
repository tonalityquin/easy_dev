import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/dev_package/debug_package/debug_database_logger.dart';
import '../../screens/type_package/parking_completed_package/table_package/services/parking_completed_logger.dart';
import '../../screens/type_package/parking_completed_package/table_package/services/status_mapping.dart';
// import '../../utils/usage_reporter.dart';

// 🔹 ParkingCompleted 로컬 로깅용

/// 🔹 중복 번호판 전용 도메인 예외
class DuplicatePlateException implements Exception {
  final String message;

  DuplicatePlateException(this.message);

  @override
  String toString() => message;
}

class PlateCreationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final Map<String, Map<String, dynamic>> _billCache = {};
  static final Map<String, DateTime> _billCacheExpiry = {};
  static const Duration _billTtl = Duration(minutes: 10);

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
    final documentId = '${plateNumber}_$area';

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
    final effectiveIsLockedFee =
        isLockedFee || (billingType == null || billingType.trim().isEmpty);

    final base = PlateModel(
      id: documentId,
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
    final entryLabel =
    (plateType == PlateType.parkingRequests) ? '입차 요청' : plateType.label;
    plateWithLog = plateWithLog.addLog(
      action: entryLabel,
      performedBy: userName,
      from: '-',
      to: entryLabel,
    );

    final docRef = _firestore.collection('plates').doc(documentId);

    // 🔹 이 호출에서 "처음부터 입차 완료(parking_completed)로 생성"된 경우를 감지하기 위한 플래그
    bool createdAsParkingCompleted = false;

    try {
      int writes = 0;
      int reads = 0;

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        reads += 1; // ✅ tx.get → read 1

        if (snap.exists) {
          final data = snap.data();
          final existingTypeStr = (data?['type'] as String?) ?? '';
          final existingType = PlateType.values.firstWhere(
                (t) => t.firestoreValue == existingTypeStr,
            orElse: () => PlateType.parkingRequests,
          );

          if (!_isAllowedDuplicate(existingType)) {
            debugPrint(
                "🚨 중복된 번호판 등록 시도: $plateNumber (${existingType.name})");
            // 🔹 여기서 더 이상 일반 Exception이 아닌 도메인 예외를 던짐
            throw DuplicatePlateException("이미 등록된 번호판입니다: $plateNumber");
          } else {
            // 기존 logs 보존 + 신규 로그 append
            final List<Map<String, dynamic>> existingLogs = (() {
              final raw = data?['logs'];
              if (raw is List) {
                return raw
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
              }
              return <Map<String, dynamic>>[];
            })();

            final List<Map<String, dynamic>> newLogs =
            (plateWithLog.logs ?? []).map((e) => e.toMap()).toList();
            final List<Map<String, dynamic>> mergedLogs = [
              ...existingLogs,
              ...newLogs
            ];

            final partial = <String, dynamic>{
              PlateFields.type: plateType.firestoreValue,
              // ✅ 클라이언트 시각 → 서버 타임스탬프로 일원화
              PlateFields.updatedAt: FieldValue.serverTimestamp(),
              if (base.location.isNotEmpty) PlateFields.location: base.location,
              if (endTime != null) PlateFields.endTime: endTime,
              if (billingType != null && billingType.trim().isNotEmpty)
                PlateFields.billingType: billingType,
              if (imageUrls != null) PlateFields.imageUrls: imageUrls,
              if (paymentMethod != null) PlateFields.paymentMethod: paymentMethod,
              if (lockedAtTimeInSeconds != null)
                PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
              if (lockedFeeAmount != null)
                PlateFields.lockedFeeAmount: lockedFeeAmount,
              PlateFields.isLockedFee: effectiveIsLockedFee,
              PlateFields.logs: mergedLogs,
            };

            final bool wasLocked = (data?['isLockedFee'] == true);
            if (wasLocked) {
              final countersRef =
              _firestore.collection('plate_counters').doc('area_$area');
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
          // ✅ 생성 시에도 updatedAt을 서버 타임스탬프로 강제 주입
          final map = plateWithLog.toMap();
          map[PlateFields.updatedAt] = FieldValue.serverTimestamp();
          tx.set(docRef, map);
          writes += 1; // plates set

          // 🔸 이 호출에서 "처음부터 parking_completed 로 생성"한 경우 플래그 세팅
          if (plateType == PlateType.parkingCompleted) {
            createdAsParkingCompleted = true;
          }
        }
      });

      // 🔹 트랜잭션이 정상적으로 끝난 뒤, 처음부터 parking_completed 로 만든 경우에만
      //    로컬 SQLite(ParkingCompletedDb)에 한 번 기록
      if (createdAsParkingCompleted) {
        // Firestore 비용 없음: 로컬(SQLite)만 기록
        // 기존 스트림 기반 로깅과 동일하게 old/new Status 텍스트 사용
        // (입차 요청 → 입차 완료로 바로 간 것처럼 취급)
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
      // 🔸 중복 번호판은 도메인 예외이므로 DebugDatabaseLogger에 기록하지 않음
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'plate.create.transaction',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
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

    // ✅ plate_status upsert → updatedAt도 서버 타임스탬프로 (일관화)
    if (customStatus != null && customStatus.trim().isNotEmpty) {
      final statusDocRef =
      _firestore.collection('plate_status').doc(documentId);
      final expireAt = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 1)),
      );

      final payload = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'updatedAt': FieldValue.serverTimestamp(), // ← 여기 일원화
        'createdBy': userName,
        'expireAt': expireAt,
        'area': area,
      };

      try {
        await statusDocRef.set(payload, SetOptions(merge: true));
        /*await UsageReporter.instance.report(
          area: area,
          action: 'write',
          n: 1,
          source: 'PlateCreationService.addPlate.statusUpsert',
        );*/
      } on FirebaseException catch (e, st) {
        try {
          await DebugDatabaseLogger().log({
            'op': 'plateStatus.upsert.set',
            'collection': 'plate_status',
            'docPath': statusDocRef.path,
            'docId': documentId,
            'error': {
              'type': e.runtimeType.toString(),
              'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['plateStatus', 'upsert', 'set', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      } catch (e, st) {
        try {
          await DebugDatabaseLogger().log({
            'op': 'plateStatus.upsert.unknown',
            'collection': 'plate_status',
            'docPath': statusDocRef.path,
            'docId': documentId,
            'error': {
              'type': e.runtimeType.toString(),
              if (e is FirebaseException) 'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['plateStatus', 'upsert', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    }
  }

  bool _isAllowedDuplicate(PlateType type) {
    // ✅ 출차 완료(departureCompleted)는 중복 허용
    return type == PlateType.departureCompleted;
  }
}
