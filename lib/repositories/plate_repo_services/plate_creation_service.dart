import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
import '../../screens/service_mode/type_package/common_widgets/reverse_sheet_package/services/parking_completed_logger.dart';
import '../../screens/service_mode/type_package/common_widgets/reverse_sheet_package/services/status_mapping.dart';

// ✅ (추가) 비정기 plate_status는 월 단위 샤딩 저장을 PlateStatusService에 위임
import 'plate_status_service.dart';

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

/// ✅ parking_requests_view "쓰기(Upsert/Delete)"를 기기 로컬 토글(SharedPreferences)로 제어
class _ParkingRequestsViewWriteGate {
  static const String prefsKey = 'parking_requests_realtime_write_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
  }

  static Future<bool> canWrite() async {
    await _ensureLoaded();
    return _prefs!.getBool(prefsKey) ?? false; // 기본 OFF
  }
}

class PlateCreationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ✅ (추가) 비정기 plate_status 저장 위임 서비스
  final PlateStatusService _plateStatusService = PlateStatusService();

  /// ✅ view 컬렉션명
  static const String _parkingCompletedViewCollection = 'parking_completed_view';
  static const String _parkingRequestsViewCollection = 'parking_requests_view';

  /// ✅ (추가) 정기(월정기) 전용 컬렉션명
  static const String _monthlyPlateStatusCollection = 'monthly_plate_status';

  static final Map<String, Map<String, dynamic>> _billCache = {};
  static final Map<String, DateTime> _billCacheExpiry = {};
  static const Duration _billTtl = Duration(minutes: 10);

  /// ✅ view 문서(=area) 안에 들어갈 item payload: parking_completed
  Map<String, dynamic> _buildParkingCompletedViewItem({
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) {
    final safeLocation = location.isNotEmpty ? location : '미지정';
    return <String, dynamic>{
      plateDocId: <String, dynamic>{
        PlateFields.plateNumber: plateNumber,
        PlateFields.location: safeLocation,
        'parkingCompletedAt': FieldValue.serverTimestamp(),
        PlateFields.updatedAt: FieldValue.serverTimestamp(),
      },
    };
  }

  /// ✅ view 문서(=area) 안에 들어갈 item payload: parking_requests
  Map<String, dynamic> _buildParkingRequestsViewItem({
    required String plateDocId,
    required String plateNumber,
    required String location,
  }) {
    final safeLocation = location.isNotEmpty ? location : '미지정';
    return <String, dynamic>{
      plateDocId: <String, dynamic>{
        PlateFields.plateNumber: plateNumber,
        PlateFields.location: safeLocation,
        'parkingRequestedAt': FieldValue.serverTimestamp(),
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
      return cached;
    }

    final billDoc = await _firestore.collection('bill').doc(key).get();

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
    final String plateDocId = '${plateNumber}_$area';

    // ✅ view write 토글은 트랜잭션 밖에서 미리 확보
    final bool canWriteCompletedView = await _ParkingCompletedViewWriteGate.canWrite();
    final bool canWriteRequestsView = await _ParkingRequestsViewWriteGate.canWrite();

    if (kDebugMode) {
      debugPrint('🧩 [PlateCreationService] canWrite parking_completed_view = $canWriteCompletedView');
      debugPrint('🧩 [PlateCreationService] canWrite parking_requests_view = $canWriteRequestsView');
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
        debugPrint("🔥 정산 정보 로드 실패: $e");
        if (kDebugMode) {
          debugPrint("stack: $st");
        }
        throw Exception("Firestore 정산 정보 로드 실패: $e");
      }
    } else if (selectedBillType == '정기') {
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
    bool createdAsParkingCompleted = false;

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        final completedViewRef = _firestore.collection(_parkingCompletedViewCollection).doc(area);
        final requestsViewRef = _firestore.collection(_parkingRequestsViewCollection).doc(area);

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

            // ✅ (요구사항) 타입이 parking_requests가 되면 view에 생성
            if (plateType == PlateType.parkingRequests) {
              // plates에 requestTime도 정합성 있게 갱신
              partial['requestTime'] = FieldValue.serverTimestamp();

              if (canWriteRequestsView) {
                tx.set(
                  requestsViewRef,
                  <String, dynamic>{
                    PlateFields.area: area,
                    PlateFields.updatedAt: FieldValue.serverTimestamp(),
                    'items': _buildParkingRequestsViewItem(
                      plateDocId: plateDocId,
                      plateNumber: plateNumber,
                      location: base.location,
                    ),
                  },
                  SetOptions(merge: true),
                );
              } else {
                if (kDebugMode) {
                  debugPrint('🚫 [PlateCreationService] skip parking_requests_view upsert (toggle OFF)');
                }
              }
            } else {
              // ✅ parking_requests가 아니면(=다른 타입으로 갱신) view에서 제거
              if (existingType == PlateType.parkingRequests && canWriteRequestsView) {
                tx.set(
                  requestsViewRef,
                  <String, dynamic>{
                    PlateFields.area: area,
                    PlateFields.updatedAt: FieldValue.serverTimestamp(),
                    'items': <String, dynamic>{
                      plateDocId: FieldValue.delete(),
                    },
                  },
                  SetOptions(merge: true),
                );
              }
            }

            // ✅ parking_completed로 “등록/갱신”하는 경우 view upsert
            if (plateType == PlateType.parkingCompleted) {
              partial['parkingCompletedAt'] = FieldValue.serverTimestamp();

              if (canWriteCompletedView) {
                tx.set(
                  completedViewRef,
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
              } else {
                if (kDebugMode) {
                  debugPrint('🚫 [PlateCreationService] skip parking_completed_view upsert (toggle OFF)');
                }
              }

              // ✅ parking_completed로 갱신되면 parking_requests_view에서는 제거(안전)
              if (canWriteRequestsView) {
                tx.set(
                  requestsViewRef,
                  <String, dynamic>{
                    PlateFields.area: area,
                    PlateFields.updatedAt: FieldValue.serverTimestamp(),
                    'items': <String, dynamic>{
                      plateDocId: FieldValue.delete(),
                    },
                  },
                  SetOptions(merge: true),
                );
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
            }

            tx.update(docRef, partial);
          }
        } else {
          // 신규 set: 로그 2건 포함
          final map = plateWithLog.toMap();
          map[PlateFields.updatedAt] = FieldValue.serverTimestamp();

          // ✅ 신규가 parking_requests면 view 생성
          if (plateType == PlateType.parkingRequests) {
            map['requestTime'] = FieldValue.serverTimestamp();

            if (canWriteRequestsView) {
              tx.set(
                requestsViewRef,
                <String, dynamic>{
                  PlateFields.area: area,
                  PlateFields.updatedAt: FieldValue.serverTimestamp(),
                  'items': _buildParkingRequestsViewItem(
                    plateDocId: plateDocId,
                    plateNumber: plateNumber,
                    location: base.location,
                  ),
                },
                SetOptions(merge: true),
              );
            } else {
              if (kDebugMode) {
                debugPrint('🚫 [PlateCreationService] skip parking_requests_view upsert (toggle OFF)');
              }
            }
          }

          // ✅ 처음부터 parking_completed로 생성되는 경우: view upsert + SQLite(기존 정책)
          if (plateType == PlateType.parkingCompleted) {
            map['parkingCompletedAt'] = FieldValue.serverTimestamp();

            if (canWriteCompletedView) {
              tx.set(
                completedViewRef,
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
            } else {
              if (kDebugMode) {
                debugPrint('🚫 [PlateCreationService] skip parking_completed_view upsert (toggle OFF)');
              }
            }

            // ✅ parking_completed로 생성되면 parking_requests_view에서는 제거(안전)
            if (canWriteRequestsView) {
              tx.set(
                requestsViewRef,
                <String, dynamic>{
                  PlateFields.area: area,
                  PlateFields.updatedAt: FieldValue.serverTimestamp(),
                  'items': <String, dynamic>{
                    plateDocId: FieldValue.delete(),
                  },
                },
                SetOptions(merge: true),
              );
            }

            createdAsParkingCompleted = true;
          }

          tx.set(docRef, map);
        }
      });

      // 트랜잭션 종료 후: 처음부터 parking_completed 로 만든 경우에만 SQLite 기록(기존 유지)
      if (createdAsParkingCompleted) {
        // ignore: unawaited_futures
        ParkingCompletedLogger.instance.maybeLogCompleted(
          plateNumber: plateNumber,
          location: location.isNotEmpty ? location : '미지정',
          oldStatus: kStatusEntryRequest,
          newStatus: kStatusEntryDone,
        );
      }
    } on DuplicatePlateException {
      rethrow;
    } catch (_) {
      rethrow;
    }

    // =========================================================================
    // ✅ (리팩터링) 메모/상태 upsert
    // - 정기(selectedBillType == '정기')   → monthly_plate_status 에만 저장
    // - 그 외                              → plate_status를 월 단위 샤딩 구조로 저장
    // =========================================================================
    final String memo = (customStatus ?? '').trim();
    final List<String> statuses = (statusList ?? const <String>[])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final bool hasMemoOrStatus = memo.isNotEmpty || statuses.isNotEmpty;
    if (!hasMemoOrStatus) return;

    final bool isMonthly = selectedBillType.trim() == '정기';

    if (!isMonthly) {
      await _plateStatusService.setPlateStatus(
        plateNumber: plateNumber,
        area: area,
        customStatus: memo,
        statusList: statuses,
        createdBy: userName,
        deleteWhenEmpty: false,
        extra: <String, dynamic>{
          'source': 'PlateCreationService.addPlate',
          'platesDocId': plateDocId,
        },
        forDate: DateTime.now(),
      );
      return;
    }

    // 정기: monthly_plate_status는 기존대로 평면 docId로 저장
    final statusDocRef = _firestore.collection(_monthlyPlateStatusCollection).doc(plateDocId);

    final payload = <String, dynamic>{
      'customStatus': memo,
      'statusList': statuses,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': userName,
      'area': area,
      'type': '정기',
      if (billingType != null && billingType.trim().isNotEmpty) 'countType': billingType.trim(),
    };

    try {
      await statusDocRef.set(payload, SetOptions(merge: true));
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  bool _isAllowedDuplicate(PlateType type) {
    // ✅ 출차 완료(departureCompleted)는 중복 허용
    return type == PlateType.departureCompleted;
  }
}
