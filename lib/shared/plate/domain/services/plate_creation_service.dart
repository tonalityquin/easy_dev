import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../enums/plate_type.dart';
import '../models/plate_model.dart';
import '../models/plate_status_draft.dart';
import '../models/plate_status_lookup_result.dart';
import 'plate_status_record.dart';
import 'plate_billing_count_service.dart';

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


  static const String _parkingCompletedViewCollection =
      'parking_completed_view';
  static const String _parkingRequestsViewCollection = 'parking_requests_view';

  static const String _monthlyPlateStatusCollection = 'monthly_plate_status';

  String _monthKey(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}';
  }

  String _normalizedPlateKey(String plateNumber) {
    return plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();
  }

  String _plateFourDigitValue(String plateNumber) {
    final key = _normalizedPlateKey(plateNumber);
    if (key.length <= 4) return key;
    return key.substring(key.length - 4);
  }

  DocumentReference<Map<String, dynamic>> _historyStatusRef({
    required String plateNumber,
    required String area,
    required DateTime date,
  }) {
    final monthKey = _monthKey(date);
    return _firestore
        .collection('plate_status')
        .doc(area)
        .collection('months')
        .doc(monthKey)
        .collection('plates')
        .doc('${plateNumber}_$area');
  }

  void _writeStatusInTransaction({
    required Transaction transaction,
    required String plateNumber,
    required String area,
    required String userName,
    required String memo,
    required bool monthlyStatusScope,
    required bool monthlyStatusExists,
    required String expectedStatusSourcePath,
    required DateTime now,
  }) {
    if (monthlyStatusScope) {
      if (!monthlyStatusExists) return;
      final monthlyRef = _firestore
          .collection(_monthlyPlateStatusCollection)
          .doc('${plateNumber}_$area');
      transaction.set(
        monthlyRef,
        <String, dynamic>{
          'customStatus': memo,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': userName,
          'lastMemoUpdatedBy': userName,
          'lastMemoSource': 'PlateCreationService.addPlate',
          'area': area,
        },
        SetOptions(merge: true),
      );
      return;
    }

    final currentRef = _historyStatusRef(
      plateNumber: plateNumber,
      area: area,
      date: now,
    );
    final previousRef = _historyStatusRef(
      plateNumber: plateNumber,
      area: area,
      date: DateTime(now.year, now.month - 1, 1),
    );
    if (memo.isEmpty) {
      transaction.delete(currentRef);
      transaction.delete(previousRef);
      final sourcePath = expectedStatusSourcePath.trim();
      if (sourcePath.isNotEmpty &&
          sourcePath != currentRef.path &&
          sourcePath != previousRef.path) {
        transaction.delete(_firestore.doc(sourcePath));
      }
      return;
    }

    transaction.set(
      currentRef,
      <String, dynamic>{
        'plateNumber': plateNumber,
        'plateDocId': '${plateNumber}_$area',
        'plateKey': _normalizedPlateKey(plateNumber),
        'plate_four_digit': _plateFourDigitValue(plateNumber),
        'source': 'PlateCreationService.addPlate',
        'platesDocId': '${plateNumber}_$area',
        'statusScope': 'plate_status',
        'monthKey': _monthKey(now),
        'customStatus': memo,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': userName,
        'area': area,
        'expireAt': Timestamp.fromDate(
          DateTime.utc(now.year, now.month + 1, 1),
        ),
      },
      SetOptions(merge: true),
    );
  }

  static final Map<String, Map<String, dynamic>> _billCache = {};
  static final Map<String, DateTime> _billCacheExpiry = {};
  static const Duration _billTtl = Duration(minutes: 10);

  Map<String, dynamic> _buildParkingCompletedViewItem({
    required String plateDocId,
    required String plateNumber,
    required String location,
    String? sectorId,
    String? sectorName,
  }) {
    final safeLocation = location.isNotEmpty ? location : '미지정';
    return <String, dynamic>{
      plateDocId: <String, dynamic>{
        PlateFields.plateNumber: plateNumber,
        PlateFields.location: safeLocation,
        PlateFields.sectorId:
            (sectorId ?? '').trim().isEmpty ? null : sectorId!.trim(),
        PlateFields.sectorName:
            (sectorName ?? '').trim().isEmpty ? null : sectorName!.trim(),
        'parkingCompletedAt': FieldValue.serverTimestamp(),
        PlateFields.updatedAt: FieldValue.serverTimestamp(),
      },
    };
  }

  Map<String, dynamic> _buildParkingRequestsViewItem({
    required String plateDocId,
    required String plateNumber,
    required String location,
    String? sectorId,
    String? sectorName,
  }) {
    final safeLocation = location.isNotEmpty ? location : '미지정';
    return <String, dynamic>{
      plateDocId: <String, dynamic>{
        PlateFields.plateNumber: plateNumber,
        PlateFields.location: safeLocation,
        PlateFields.sectorId:
            (sectorId ?? '').trim().isEmpty ? null : sectorId!.trim(),
        PlateFields.sectorName:
            (sectorName ?? '').trim().isEmpty ? null : sectorName!.trim(),
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
    required bool statusWriteRequested,
    required PlateStatusLookupState statusLookupState,
    required bool statusEditedByUser,
    required PlateStatusDraft expectedOriginalStatus,
    String? expectedStatusSourcePath,
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
    String? sectorId,
    String? sectorName,
  }) async {
    final String plateDocId = '${plateNumber}_$area';
    final String statusActorName =
        userName.trim().isEmpty ? 'unknown' : userName.trim();
    final String statusMemo = (customStatus ?? '').trim();
    final bool monthlyStatusScope = selectedBillType.trim() == '정기';
    final monthlyStatusRef = _firestore
        .collection(_monthlyPlateStatusCollection)
        .doc(plateDocId);
    final DateTime statusWriteTime = DateTime.now();
    final currentHistoryStatusRef = _historyStatusRef(
      plateNumber: plateNumber,
      area: area,
      date: statusWriteTime,
    );
    final previousHistoryStatusRef = _historyStatusRef(
      plateNumber: plateNumber,
      area: area,
      date: DateTime(
        statusWriteTime.year,
        statusWriteTime.month - 1,
        1,
      ),
    );
    final expectedSourcePath = expectedStatusSourcePath?.trim() ?? '';
    final expectedSourceRef = expectedSourcePath.isEmpty
        ? null
        : _firestore.doc(expectedSourcePath);
    final bool hasResolvedStatusSnapshot =
        statusLookupState == PlateStatusLookupState.found ||
        statusLookupState == PlateStatusLookupState.notFound;
    final bool shouldApplyPlateStatusFields =
        statusEditedByUser || hasResolvedStatusSnapshot;
    final bool shouldValidateStatusSnapshot =
        shouldApplyPlateStatusFields || statusWriteRequested;

    if (statusLookupState == PlateStatusLookupState.idle ||
        statusLookupState == PlateStatusLookupState.loading) {
      throw const PlateStatusConflictException(
        '상태 정보 확인이 완료되지 않아 입차 정보를 저장하지 않았습니다.',
      );
    }
    if (statusLookupState == PlateStatusLookupState.inactive) {
      throw const PlateStatusScopeException(
        '상태 정보의 유효기간이 확인되지 않아 입차 정보를 저장하지 않았습니다.',
      );
    }

    debugPrint(
      '[PlateCreationService][Status] plate=$plateNumber area=$area '
      'scope=${monthlyStatusScope ? 'monthly' : 'history'} '
      'memoLength=${statusMemo.length} '
      'writeRequested=$statusWriteRequested '
      'lookupState=${statusLookupState.name} edited=$statusEditedByUser '
      'sourcePath=$expectedSourcePath '
      'applyPlateFields=$shouldApplyPlateStatusFields '
      'validateSnapshot=$shouldValidateStatusSnapshot saveMode=transaction',
    );

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
        regularDurationHours = billData['regularDurationValue'] ?? billData['regularDurationHours'];
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
    final normalizedSectorId = (sectorId ?? '').trim();
    final normalizedSectorName = (sectorName ?? '').trim();
    final hasSector =
        normalizedSectorId.isNotEmpty && normalizedSectorName.isNotEmpty;
    if (normalizedSectorId.isEmpty != normalizedSectorName.isEmpty) {
      throw ArgumentError('sectorId와 sectorName은 함께 전달되어야 합니다.');
    }
    debugPrint(
      '[PlateCreationService][Sector] plate=$plateNumber area=$area '
      'hasSector=$hasSector sectorId=$normalizedSectorId '
      'sectorName=$normalizedSectorName',
    );
    final normalizedDivision =
        division.trim().isEmpty ? '미지정' : division.trim();
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
      basicStandard: basicStandard ?? 0,
      basicAmount: basicAmount ?? 0,
      addStandard: addStandard ?? 0,
      addAmount: addAmount ?? 0,
      region: region,
      imageUrls: imageUrls,
      isSelected: false,
      selectedBy: null,
      sectorId: hasSector ? normalizedSectorId : null,
      sectorName: hasSector ? normalizedSectorName : null,
      isLockedFee: effectiveIsLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
      paymentMethod: paymentMethod,
      customStatus: statusMemo,
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
        final monthlyStatusSnapshot =
            (monthlyStatusScope || shouldValidateStatusSnapshot)
                ? await tx.get(monthlyStatusRef)
                : null;
        if (monthlyStatusScope) {
          final monthlyData = monthlyStatusSnapshot?.data();
          if (!(monthlyStatusSnapshot?.exists ?? false) || monthlyData == null) {
            throw const PlateStatusScopeException(
              '정기 상태 문서를 찾지 못해 입차 정보를 저장하지 않았습니다.',
            );
          }
          final monthlyRecord = PlateStatusRecord.fromMap(
            monthlyData,
            docId: monthlyStatusSnapshot!.id,
          );
          if (!monthlyRecord.isActiveAt(statusWriteTime)) {
            throw const PlateStatusScopeException(
              '정기 주차 기간이 만료되어 입차 정보를 저장하지 않았습니다.',
            );
          }
        }

        if (shouldValidateStatusSnapshot) {
          if (statusLookupState == PlateStatusLookupState.failed) {
            throw const PlateStatusConflictException(
              '기존 상태 정보를 확인하지 못해 최신 상태를 보호했습니다. 다시 조회한 뒤 저장해 주세요.',
            );
          }

          if (monthlyStatusScope) {
            if (expectedSourcePath.isNotEmpty &&
                expectedSourcePath != monthlyStatusRef.path) {
              throw const PlateStatusConflictException(
                '조회한 정기 상태 문서와 저장 대상이 달라 입차 정보를 저장하지 않았습니다.',
              );
            }
            final latestMonthlyDraft = PlateStatusDraft.fromMap(
              monthlyStatusSnapshot?.data(),
            );
            if (statusLookupState == PlateStatusLookupState.found &&
                !latestMonthlyDraft.sameAs(expectedOriginalStatus)) {
              throw const PlateStatusConflictException(
                '다른 사용자가 정기 상태 메모를 먼저 수정했습니다. 최신 정보를 다시 불러온 뒤 저장해 주세요.',
              );
            }
            if (statusLookupState != PlateStatusLookupState.found) {
              throw const PlateStatusConflictException(
                '정기 상태 원본이 변경되어 입차 정보를 저장하지 않았습니다. 최신 정보를 다시 불러와 주세요.',
              );
            }
          } else {
            final monthlyData = monthlyStatusSnapshot?.data();
            if ((monthlyStatusSnapshot?.exists ?? false) &&
                monthlyData != null) {
              final monthlyRecord = PlateStatusRecord.fromMap(
                monthlyData,
                docId: monthlyStatusSnapshot!.id,
              );
              if (monthlyRecord.isActiveAt(statusWriteTime)) {
                throw const PlateStatusScopeException(
                  '활성 정기 상태 문서가 확인되어 일반 상태 문서에 저장하지 않았습니다.',
                );
              }
            }
            final currentStatusSnapshot =
                await tx.get(currentHistoryStatusRef);
            final previousStatusSnapshot =
                await tx.get(previousHistoryStatusRef);
            DocumentSnapshot<Map<String, dynamic>>? sourceStatusSnapshot;
            if (expectedSourceRef != null) {
              if (expectedSourceRef.path == currentHistoryStatusRef.path) {
                sourceStatusSnapshot = currentStatusSnapshot;
              } else if (expectedSourceRef.path ==
                  previousHistoryStatusRef.path) {
                sourceStatusSnapshot = previousStatusSnapshot;
              } else {
                sourceStatusSnapshot = await tx.get(expectedSourceRef);
              }
            }

            if (statusLookupState == PlateStatusLookupState.found) {
              if (sourceStatusSnapshot == null ||
                  !sourceStatusSnapshot.exists) {
                throw const PlateStatusConflictException(
                  '조회했던 상태 문서가 변경되어 입차 정보를 저장하지 않았습니다. 최신 정보를 다시 불러와 주세요.',
                );
              }
              final sourceDraft = PlateStatusDraft.fromMap(
                sourceStatusSnapshot.data(),
              );
              if (!sourceDraft.sameAs(expectedOriginalStatus)) {
                throw const PlateStatusConflictException(
                  '다른 사용자가 상태 메모를 먼저 수정했습니다. 최신 정보를 다시 불러온 뒤 저장해 주세요.',
                );
              }
              for (final snapshot in <DocumentSnapshot<Map<String, dynamic>>>[
                currentStatusSnapshot,
                previousStatusSnapshot,
              ]) {
                if (!snapshot.exists ||
                    snapshot.reference.path == sourceStatusSnapshot.reference.path) {
                  continue;
                }
                final draft = PlateStatusDraft.fromMap(snapshot.data());
                if (!draft.sameAs(expectedOriginalStatus)) {
                  throw const PlateStatusConflictException(
                    '다른 사용자가 최신 월 상태 메모를 먼저 수정했습니다. 최신 정보를 다시 불러온 뒤 저장해 주세요.',
                  );
                }
              }
            } else if (statusLookupState == PlateStatusLookupState.notFound) {
              if (currentStatusSnapshot.exists || previousStatusSnapshot.exists) {
                throw const PlateStatusConflictException(
                  '상태 조회 이후 새 상태 메모가 등록되었습니다. 최신 정보를 다시 불러온 뒤 저장해 주세요.',
                );
              }
            }
          }
        }

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
              if (shouldApplyPlateStatusFields)
                PlateFields.customStatus: statusMemo,
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
              PlateFields.sectorId:
                  hasSector ? normalizedSectorId : FieldValue.delete(),
              PlateFields.sectorName:
                  hasSector ? normalizedSectorName : FieldValue.delete(),
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
                      sectorId: base.sectorId,
                      sectorName: base.sectorName,
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
                      sectorId: base.sectorId,
                      sectorName: base.sectorName,
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
                    sectorId: base.sectorId,
                    sectorName: base.sectorName,
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
                    sectorId: base.sectorId,
                    sectorName: base.sectorName,
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

        if (statusWriteRequested) {
          _writeStatusInTransaction(
            transaction: tx,
            plateNumber: plateNumber,
            area: area,
            userName: statusActorName,
            memo: statusMemo,
            monthlyStatusScope: monthlyStatusScope,
            monthlyStatusExists: monthlyStatusSnapshot?.exists ?? false,
            expectedStatusSourcePath: expectedSourcePath,
            now: statusWriteTime,
          );
        }
      });
    } on DuplicatePlateException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  bool _isAllowedDuplicate(PlateType type) {
    return type == PlateType.departureCompleted;
  }
}
