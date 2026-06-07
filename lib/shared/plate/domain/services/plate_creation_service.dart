import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../enums/plate_type.dart';
import '../models/plate_model.dart';
import 'plate_billing_count_service.dart';
import 'plate_status_service.dart';

const String _kLocSep = ' - ';
const String _kLocUnknown = '미지정';

Map<String, dynamic> _locationToMap(String display) {
  final raw = display.trim();

  if (raw.isEmpty || raw == _kLocUnknown) {
    return <String, dynamic>{
      'parent': '',
      'child': '',
      'slot': '',
      'full': _kLocUnknown,
      'leaf': _kLocUnknown,
    };
  }

  final parts = raw
      .split(_kLocSep)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String parent = '';
  String child = '';
  String slot = '';

  if (parts.isEmpty) {
    return <String, dynamic>{
      'parent': '',
      'child': '',
      'slot': '',
      'full': _kLocUnknown,
      'leaf': _kLocUnknown,
    };
  }

  if (parts.length == 1) {
    parent = parts[0];
  } else if (parts.length == 2) {
    parent = parts[0];
    child = parts[1];
  } else {
    parent = parts[0];
    child = parts[1];
    slot = parts.sublist(2).join(_kLocSep);
  }

  final fullSegs =
      <String>[parent, child, slot].where((e) => e.trim().isNotEmpty).toList();
  final full = fullSegs.isEmpty ? _kLocUnknown : fullSegs.join(_kLocSep);

  final leafSegs =
      <String>[child, slot].where((e) => e.trim().isNotEmpty).toList();
  final leaf = leafSegs.isNotEmpty
      ? leafSegs.join(_kLocSep)
      : (parent.trim().isEmpty ? _kLocUnknown : parent);

  return <String, dynamic>{
    'parent': parent,
    'child': child,
    'slot': slot,
    'full': full,
    'leaf': leaf,
  };
}

String _normalizeLocationString(String raw) {
  final v = raw.trim();
  return v.isEmpty ? _kLocUnknown : v;
}

class DuplicatePlateException implements Exception {
  final String message;

  DuplicatePlateException(this.message);

  @override
  String toString() => message;
}

class _ParkingCompletedViewWriteGate {
  static const String prefsKey = 'parking_completed_realtime_write_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() async {
    if (_prefs != null) return;
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
  }

  static Future<bool> canWrite() async {
    await _ensureLoaded();
    await _prefs!.setBool(prefsKey, true);
    return true;
  }
}

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
    await _prefs!.setBool(prefsKey, true);
    return true;
  }
}

class PlateCreationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final PlateStatusService _plateStatusService = PlateStatusService();

  static const String _parkingCompletedViewCollection =
      'parking_completed_view';
  static const String _parkingRequestsViewCollection = 'parking_requests_view';

  static const String _monthlyPlateStatusCollection = 'monthly_plate_status';

  static final Map<String, Map<String, dynamic>> _billCache = {};
  static final Map<String, DateTime> _billCacheExpiry = {};
  static const Duration _billTtl = Duration(minutes: 10);

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
    required String division,
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
    String? manufacturerName,
    String? modelName,
    String? priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
  }) async {
    final String plateDocId = '${plateNumber}_$area';

    final bool canWriteCompletedView =
        await _ParkingCompletedViewWriteGate.canWrite();
    final bool canWriteRequestsView =
        await _ParkingRequestsViewWriteGate.canWrite();

    if (kDebugMode) {
      debugPrint(
          '🧩 [PlateCreationService] canWrite parking_completed_view = $canWriteCompletedView');
      debugPrint(
          '🧩 [PlateCreationService] canWrite parking_requests_view = $canWriteRequestsView');
    }

    int? regularAmount;
    int? regularDurationHours;

    if (selectedBillType != '정기' &&
        billingType != null &&
        billingType.isNotEmpty) {
      try {
        final billData =
            await _getBillCached(billingType: billingType, area: area);
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

    final plateFourDigit = plateNumber.length >= 4
        ? plateNumber.substring(plateNumber.length - 4)
        : plateNumber;

    final effectiveIsLockedFee =
        isLockedFee || (billingType == null || billingType.trim().isEmpty);

    final normalizedLocation = _normalizeLocationString(location);
    final normalizedDivision = division.trim().isEmpty ? '미지정' : division.trim();
    final countedAt = DateTime.now();

    final base = PlateModel(
      id: plateDocId,
      plateNumber: plateNumber,
      plateFourDigit: plateFourDigit,
      type: plateType.firestoreValue,
      requestTime: DateTime.now(),
      endTime: endTime,
      location: normalizedLocation,
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
      manufacturerName: manufacturerName?.trim(),
      modelName: modelName?.trim(),
      parkingPriority1SlotKey: priority1SlotKey?.trim(),
      parkingPriority2SlotKey: priority2SlotKey?.trim(),
      parkingPriority3SlotKey: priority3SlotKey?.trim(),
    );

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

    final docRef = _firestore.collection('plates').doc(plateDocId);
    final bool shouldIncrementBillingCount =
        plateType == PlateType.parkingRequests ||
        plateType == PlateType.parkingCompleted;

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        final completedViewRef =
            _firestore.collection(_parkingCompletedViewCollection).doc(area);
        final requestsViewRef =
            _firestore.collection(_parkingRequestsViewCollection).doc(area);

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
            final bool shouldIncrementReentryBillingCount =
                existingType == PlateType.departureCompleted &&
                    shouldIncrementBillingCount;

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
              PlateFields.company: normalizedDivision,
              PlateFields.division: normalizedDivision,
              PlateFields.updatedAt: FieldValue.serverTimestamp(),
              if (base.location.isNotEmpty)
                PlateFields.location: _locationToMap(base.location),
              if (endTime != null) PlateFields.endTime: endTime,
              if (billingType != null && billingType.trim().isNotEmpty)
                PlateFields.billingType: billingType,
              if (imageUrls != null) PlateFields.imageUrls: imageUrls,
              if (paymentMethod != null)
                PlateFields.paymentMethod: paymentMethod,
              if ((manufacturerName ?? '').trim().isNotEmpty)
                PlateFields.manufacturerName: manufacturerName!.trim(),
              if ((modelName ?? '').trim().isNotEmpty)
                PlateFields.modelName: modelName!.trim(),
              if ((priority1SlotKey ?? '').trim().isNotEmpty)
                PlateFields.parkingPriority1SlotKey: priority1SlotKey!.trim(),
              if ((priority2SlotKey ?? '').trim().isNotEmpty)
                PlateFields.parkingPriority2SlotKey: priority2SlotKey!.trim(),
              if ((priority3SlotKey ?? '').trim().isNotEmpty)
                PlateFields.parkingPriority3SlotKey: priority3SlotKey!.trim(),
              if (lockedAtTimeInSeconds != null)
                PlateFields.lockedAtTimeInSeconds: lockedAtTimeInSeconds,
              if (lockedFeeAmount != null)
                PlateFields.lockedFeeAmount: lockedFeeAmount,
              PlateFields.isLockedFee: effectiveIsLockedFee,
              PlateFields.logs: mergedLogs,
            };

            if (shouldIncrementReentryBillingCount) {
              partial[PlateFields.lastBillingCountedAt] =
                  FieldValue.serverTimestamp();
            }

            if (plateType == PlateType.parkingRequests) {
              partial[PlateFields.requestTime] = FieldValue.serverTimestamp();

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
                  debugPrint(
                      '🚫 [PlateCreationService] skip parking_requests_view upsert (toggle OFF)');
                }
              }
            } else {
              if (existingType == PlateType.parkingRequests &&
                  canWriteRequestsView) {
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
                  debugPrint(
                      '🚫 [PlateCreationService] skip parking_completed_view upsert (toggle OFF)');
                }
              }

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
              final countersRef =
                  _firestore.collection('plate_counters').doc('area_$area');
              tx.set(
                countersRef,
                {'departureCompletedEvents': FieldValue.increment(1)},
                SetOptions(merge: true),
              );
            }

            tx.update(docRef, partial);

            if (shouldIncrementReentryBillingCount) {
              PlateBillingCountService.incrementInTransaction(
                transaction: tx,
                firestore: _firestore,
                company: normalizedDivision,
                area: area,
                plateDocId: plateDocId,
                plateNumber: plateNumber,
                countedAt: countedAt,
                userName: userName,
              );
            }
          }
        } else {
          final map = plateWithLog.toMap();
          map[PlateFields.company] = normalizedDivision;
          map[PlateFields.division] = normalizedDivision;
          map[PlateFields.createdAt] = FieldValue.serverTimestamp();
          if (shouldIncrementBillingCount) {
            map[PlateFields.lastBillingCountedAt] = FieldValue.serverTimestamp();
          }
          map[PlateFields.requestTime] = FieldValue.serverTimestamp();
          map[PlateFields.updatedAt] = FieldValue.serverTimestamp();

          map[PlateFields.location] = _locationToMap(base.location);

          if (plateType == PlateType.parkingRequests) {

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
                debugPrint(
                    '🚫 [PlateCreationService] skip parking_requests_view upsert (toggle OFF)');
              }
            }
          }

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
                debugPrint(
                    '🚫 [PlateCreationService] skip parking_completed_view upsert (toggle OFF)');
              }
            }

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

          tx.set(docRef, map);
          if (shouldIncrementBillingCount) {
            PlateBillingCountService.incrementInTransaction(
              transaction: tx,
              firestore: _firestore,
              company: normalizedDivision,
              area: area,
              plateDocId: plateDocId,
              plateNumber: plateNumber,
              countedAt: countedAt,
              userName: userName,
            );
          }
        }
      });
    } on DuplicatePlateException {
      rethrow;
    } catch (_) {
      rethrow;
    }

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

    final statusDocRef =
        _firestore.collection(_monthlyPlateStatusCollection).doc(plateDocId);

    final payload = <String, dynamic>{
      'customStatus': memo,
      'statusList': statuses,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': userName,
      'area': area,
      'type': '정기',
      if (billingType != null && billingType.trim().isNotEmpty)
        'countType': billingType.trim(),
    };

    try {
      await statusDocRef.set(payload, SetOptions(merge: true));
    } on FirebaseException catch (e, st) {
      await DevFirebaseDebugDialog.show(
        operation: 'monthly.plateCreation.memoStatus.upsert',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'docId': plateDocId,
          'plateNumber': plateNumber,
          'area': area,
          'selectedBillType': selectedBillType,
          'billingType': billingType,
          'createdBy': userName,
          'customStatus': memo,
          'statusList': statuses,
          'writePath': 'PlateCreationService.addPlate monthly_plate_status set merge',
        },
      );
      rethrow;
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        operation: 'monthly.plateCreation.memoStatus.upsert.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'docId': plateDocId,
          'plateNumber': plateNumber,
          'area': area,
          'selectedBillType': selectedBillType,
          'billingType': billingType,
          'createdBy': userName,
          'customStatus': memo,
          'statusList': statuses,
          'writePath': 'PlateCreationService.addPlate monthly_plate_status set merge',
        },
      );
      rethrow;
    }
  }

  bool _isAllowedDuplicate(PlateType type) {
    return type == PlateType.departureCompleted;
  }
}
