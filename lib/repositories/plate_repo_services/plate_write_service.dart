// lib/repositories/plate_repo_services/plate_write_service.dart
//
// (요청사항) 기존 주석처리 코드 유지, updatedAt 강제 세팅 반영(생성/업데이트/전환/선택 경로)
//
// ✅ (수정안 반영)
// - Header 단일 스위치로 view 삽입(Write) ON/OFF를 통합 관리하므로,
//   recordWhoPlateClick의 view 동기화 로직도 "토글 ON일 때만" 삭제/복구를 수행하도록 정합성 강화.
//   (기존: 선택 시 삭제는 항상 수행, 해제 시 복구는 토글 ON일 때만 → OFF 상태에서 view 불일치 발생 가능)
//
// ✅ (추가 반영: 사용자 화면 정합성)
// - deletePlate 시 plates 문서만 삭제하면 사용자 화면(view 컬렉션)에서는 잔상이 남을 수 있으므로,
//   (옵션으로) parking_requests_view / parking_completed_view / departure_requests_view 에서도 items.{id} 제거를 수행
// - 삭제 시 Firestore 비용(문서 write 개수) 및 write payload 형태를 debugPrint로 확인 가능

import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ 추가

import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';
// import '../../utils/usage_reporter.dart';

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ departure_requests_view 동기화(선택/해제)에 대한 기기 로컬 토글 키
  // - Header 단일 스위치에서 함께 동기화되는 키
  static const String _kDepartureRequestsViewWritePrefsKey =
      'departure_requests_realtime_write_enabled_v1';

  // ✅ parking_requests_view 동기화(선택/해제)에 대한 기기 로컬 토글 키
  // - Header 단일 스위치에서 함께 동기화되는 키
  static const String _kParkingRequestsViewWritePrefsKey =
      'parking_requests_realtime_write_enabled_v1';

  // ✅ parking_completed_view 동기화(업서트/삭제)에 대한 기기 로컬 토글 키
  // - MovementPlate / PlateCreationService와 동일 키
  static const String _kParkingCompletedViewWritePrefsKey =
      'parking_completed_realtime_write_enabled_v1';

  // ✅ (보조) UI 탭(조회) 활성화 토글 키
  // - Write 토글이 OFF여도, 사용자가 테이블을 보고 있다면 최소한 정합성은 지키기 위해 OR 조건으로 활용합니다.
  // - UI 코드(RealTimeTable)와 동일 키를 유지해야 합니다.
  static const String _kDepartureRequestsViewTabPrefsKey =
      'departure_requests_realtime_tab_enabled_v1';
  static const String _kParkingCompletedViewTabPrefsKey =
      'parking_completed_realtime_tab_enabled_v1';

  // ✅ (보조) parking_requests_view 탭(조회) 토글 키 (UI에 존재한다면 동일 키로 맞추세요)
  static const String _kParkingRequestsViewTabPrefsKey =
      'parking_requests_realtime_tab_enabled_v1';

  static SharedPreferences? _prefs;
  static Future<void>? _prefsLoading;

  static Future<SharedPreferences> _ensurePrefs() async {
    _prefsLoading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _prefsLoading;
    return _prefs!;
  }

  static Future<bool> _canUpsertDepartureRequestsView() async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(_kDepartureRequestsViewWritePrefsKey) ?? false; // 기본 OFF
  }

  static Future<bool> _canUpsertParkingRequestsView() async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(_kParkingRequestsViewWritePrefsKey) ?? false; // 기본 OFF
  }

  static Future<bool> _canUpsertParkingCompletedView() async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(_kParkingCompletedViewWritePrefsKey) ?? false; // 기본 OFF
  }

  static Future<bool> _isDepartureRequestsRealtimeTabEnabled() async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(_kDepartureRequestsViewTabPrefsKey) ?? false; // 기본 OFF
  }

  static Future<bool> _isParkingCompletedRealtimeTabEnabled() async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(_kParkingCompletedViewTabPrefsKey) ?? false; // 기본 OFF
  }

  static Future<bool> _isParkingRequestsRealtimeTabEnabled() async {
    final prefs = await _ensurePrefs();
    return prefs.getBool(_kParkingRequestsViewTabPrefsKey) ?? false; // 기본 OFF
  }

  /// ✅ "정합성" 관점에서 view 동기화를 수행할지 결정
  ///
  /// - 기본적으로는 Write 토글을 따릅니다.
  /// - 다만 사용자가 실시간 테이블(탭)을 보고 있는 경우(탭 토글 ON)에는,
  ///   Modify/Update로 인해 UI-DB 불일치가 발생하지 않도록 view 동기화를 허용합니다.
  static Future<bool> _shouldSyncDepartureRequestsView() async {
    final write = await _canUpsertDepartureRequestsView();
    if (write) return true;
    return _isDepartureRequestsRealtimeTabEnabled();
  }

  static Future<bool> _shouldSyncParkingCompletedView() async {
    final write = await _canUpsertParkingCompletedView();
    if (write) return true;
    return _isParkingCompletedRealtimeTabEnabled();
  }

  static Future<bool> _shouldSyncParkingRequestsView() async {
    final write = await _canUpsertParkingRequestsView();
    if (write) return true;
    return _isParkingRequestsRealtimeTabEnabled();
  }

  // ─────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────

  String _fallbackPlateFromDocId(String docId) {
    final idx = docId.lastIndexOf('_');
    if (idx > 0) return docId.substring(0, idx);
    return docId;
  }

  String _fallbackAreaFromDocId(String docId) {
    final idx = docId.lastIndexOf('_');
    if (idx >= 0 && idx + 1 < docId.length) return docId.substring(idx + 1);
    return '';
  }

  String _extractPlateNumberFromPlateDoc(Map<String, dynamic> data, String docId) {
    final v1 = (data['plateNumber'] as String?)?.trim(); // legacy/일부 write 경로
    if (v1 != null && v1.isNotEmpty) return v1;

    final v2 = (data[PlateFields.plateNumber] as String?)?.trim(); // 표준(plate_number)
    if (v2 != null && v2.isNotEmpty) return v2;

    return _fallbackPlateFromDocId(docId);
  }

  String _extractAreaFromPlateDoc(Map<String, dynamic> data, String docId) {
    final v = (data[PlateFields.area] as String?)?.trim();
    if (v != null && v.isNotEmpty) return v;

    final fallback = _fallbackAreaFromDocId(docId).trim();
    return fallback.isNotEmpty ? fallback : '미지정';
  }

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is num) return v.toInt() != 0;
    if (v is String) {
      final t = v.trim().toLowerCase();
      return t == 'true' || t == '1' || t == 'y' || t == 'yes';
    }
    return false;
  }

  String _normalizeLocation(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty ? '미지정' : v;
  }

  dynamic _extractTimestampForAny({
    required Map<String, dynamic> before,
    required Map<String, dynamic> fields,
    required List<String> keys,
  }) {
    // 새 값이 Timestamp면 우선 사용, 아니면 기존 값 Timestamp 사용
    for (final k in keys) {
      final vNew = fields[k];
      if (vNew is Timestamp) return vNew;
      final vOld = before[k];
      if (vOld is Timestamp) return vOld;
    }
    return null;
  }

  // ─────────────────────────────────────────
  // Debug helpers (삭제 비용/형태 확인)
  // ─────────────────────────────────────────

  bool get _dbDebugEnabled => kDebugMode;

  void _debugDeleteCostAndShape({
    required String plateId,
    required String area,
    required bool syncViews,
  }) {
    if (!_dbDebugEnabled) return;

    final viewWrites = syncViews ? 3 : 0;
    final totalWrites = 1 + viewWrites; // plates delete + view set(merge)

    debugPrint(
      '💸 [DB-COST] deletePlate(plateId=$plateId, area=$area, syncViews=$syncViews) '
          'expected_billable_ops: writes=$totalWrites (plates.delete=1, view.set=$viewWrites), reads=0',
    );

    if (!syncViews) return;

    Map<String, dynamic> shape(String col) => <String, dynamic>{
      'collection': '$col/$area',
      'op': 'set(merge)',
      'payload': <String, dynamic>{
        'area': area,
        'updatedAt': '<serverTimestamp>',
        'items': <String, dynamic>{
          plateId: '<FieldValue.delete()>',
        },
      },
    };

    debugPrint('🧾 [DB-SHAPE] ${shape('parking_requests_view')}');
    debugPrint('🧾 [DB-SHAPE] ${shape('parking_completed_view')}');
    debugPrint('🧾 [DB-SHAPE] ${shape('departure_requests_view')}');
  }

  // ─────────────────────────────────────────
  // Writes
  // ─────────────────────────────────────────

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      final docSnapshot =
      await docRef.get().timeout(const Duration(seconds: 10));

      /*final preArea = (docSnapshot.data()?['area'] ?? plate.area ?? 'unknown') as String;
      await UsageReporter.instance.report(
        area: preArea,
        action: 'read',
        n: 1,
        source: 'PlateWriteService.addOrUpdatePlate.prefetch',
      );*/

      var newData = plate.toMap();
      newData = _enforceZeroFeeLock(newData, existing: docSnapshot.data());

      final exists = docSnapshot.exists;
      final existingData = docSnapshot.data() ?? const <String, dynamic>{};

      // 비교 시 로그 필드는 제외
      final compOld = Map<String, dynamic>.from(existingData)
        ..remove(PlateFields.logs);
      final compNew = Map<String, dynamic>.from(newData)
        ..remove(PlateFields.logs);

      // 변화 없음이면 조용히 종료(불필요 write 방지)
      if (exists && _isSameData(compOld, compNew)) {
        return;
      }

      // 기존 문서에 쓰는 경우 Firestore array 병합 충돌 방지 위해 logs 제거
      if (exists) {
        newData.remove(PlateFields.logs);
      }

      // ✅ 생성이든 업데이트든 실제 write를 수행하는 경우 updatedAt은 반드시 서버 시각으로 갱신
      newData['updatedAt'] = FieldValue.serverTimestamp();

      await docRef
          .set(newData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      rethrow;
    } on FirebaseException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> updatePlate(
      String documentId,
      Map<String, dynamic> updatedFields, {
        PlateLogModel? log,
      }) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    // ✅ prefs 접근은 트랜잭션 내부에서 불가 → 사전 결정
    // - Write 토글(기본) + (보조) 실시간 테이블 탭 토글(조회 ON) OR 조건으로 정합성 유지
    final bool shouldSyncPcView = await _shouldSyncParkingCompletedView();
    final bool shouldSyncDepView = await _shouldSyncDepartureRequestsView();
    final bool shouldSyncReqView = await _shouldSyncParkingRequestsView();

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef); // READ 1
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'plate $documentId not found',
          );
        }

        final before = snap.data() ?? <String, dynamic>{};

        // ─────────────────────────────────────────
        // 1) plates 문서 업데이트(기존 정책 유지)
        // ─────────────────────────────────────────
        final fields = _enforceZeroFeeLock(
          Map<String, dynamic>.from(updatedFields),
          existing: before,
        );

        if (log != null) {
          fields['logs'] = FieldValue.arrayUnion([log.toMap()]);
        }

        // ✅ 어떤 업데이트든 write가 발생하면 updatedAt을 서버 시각으로 갱신
        fields['updatedAt'] = FieldValue.serverTimestamp();

        tx.update(docRef, fields); // WRITE 1

        // ─────────────────────────────────────────
        // 2) 변경 전/후 핵심 값 계산(뷰 정합성 판단)
        // ─────────────────────────────────────────
        final String beforeType =
        ((before[PlateFields.type] as String?) ?? '').trim();
        final String afterType =
        (((fields[PlateFields.type] as String?) ?? beforeType)).trim();

        final String beforeArea = _extractAreaFromPlateDoc(before, documentId);
        final String afterArea =
        ((fields[PlateFields.area] as String?)?.trim().isNotEmpty ?? false)
            ? (fields[PlateFields.area] as String).trim()
            : beforeArea;

        final String beforePlateNumber =
        _extractPlateNumberFromPlateDoc(before, documentId);

        String afterPlateNumber = beforePlateNumber;
        final String? pn1 = (fields['plateNumber'] as String?)?.trim();
        final String? pn2 = (fields[PlateFields.plateNumber] as String?)?.trim();
        if (pn1 != null && pn1.isNotEmpty) {
          afterPlateNumber = pn1;
        } else if (pn2 != null && pn2.isNotEmpty) {
          afterPlateNumber = pn2;
        }

        final String beforeLocation =
        _normalizeLocation(before[PlateFields.location] as String?);
        final String afterLocation = _normalizeLocation(
          (fields[PlateFields.location] as String?) ??
              (before[PlateFields.location] as String?),
        );

        final bool beforeSelected = _toBool(before[PlateFields.isSelected]);
        final bool afterSelected = fields.containsKey(PlateFields.isSelected)
            ? _toBool(fields[PlateFields.isSelected])
            : beforeSelected;

        final bool typeChanged = beforeType != afterType;
        final bool areaChanged = beforeArea != afterArea;
        final bool locationChanged = beforeLocation != afterLocation;
        final bool plateNumberChanged = beforePlateNumber != afterPlateNumber;
        final bool selectedChanged = beforeSelected != afterSelected;

        // 변경이 view에 영향 없는 경우 빠르게 종료(불필요 write 방지)
        final bool affectsViews = typeChanged ||
            areaChanged ||
            locationChanged ||
            plateNumberChanged ||
            selectedChanged;

        if (!affectsViews) {
          return;
        }

        // ─────────────────────────────────────────
        // 3) View 동기화(입차 요청/입차 완료/출차 요청)
        // ─────────────────────────────────────────

        DocumentReference<Map<String, dynamic>> _viewRef(
            String collection,
            String area,
            ) =>
            _firestore.collection(collection).doc(area);

        void _txRemoveViewItem({
          required String collection,
          required String area,
          required String plateDocId,
        }) {
          if (area.trim().isEmpty) return;
          final ref = _viewRef(collection, area.trim());

          tx.set(
            ref,
            <String, dynamic>{
              'area': area.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
              'items': <String, dynamic>{
                plateDocId: FieldValue.delete(),
              }
            },
            SetOptions(merge: true),
          );
        }

        void _txUpsertViewItemFields({
          required String collection,
          required String area,
          required String plateDocId,
          required String plateNumber,
          required String location,
          String? primaryTimeField,
          dynamic primaryTimeValue,
        }) {
          if (area.trim().isEmpty) return;

          final ref = _viewRef(collection, area.trim());

          final item = <String, dynamic>{
            // 호환성: camelCase / snake_case 모두 기록(읽기 쪽이 어느 키를 쓰든 대응)
            'plateNumber': plateNumber,
            PlateFields.plateNumber: plateNumber,
            'location': location,
            'updatedAt': FieldValue.serverTimestamp(),
            if (primaryTimeField != null)
              primaryTimeField: primaryTimeValue ?? FieldValue.serverTimestamp(),
          };

          tx.set(
            ref,
            <String, dynamic>{
              'area': area.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
              'items': <String, dynamic>{
                plateDocId: item,
              }
            },
            SetOptions(merge: true),
          );
        }

        const String reqCollection = 'parking_requests_view';
        const String pcCollection = 'parking_completed_view';
        const String depCollection = 'departure_requests_view';

        final bool beforeIsReq =
            beforeType == PlateType.parkingRequests.firestoreValue;
        final bool afterIsReq =
            afterType == PlateType.parkingRequests.firestoreValue;

        final bool beforeIsPc =
            beforeType == PlateType.parkingCompleted.firestoreValue;
        final bool afterIsPc =
            afterType == PlateType.parkingCompleted.firestoreValue;

        final bool beforeIsDep =
            beforeType == PlateType.departureRequests.firestoreValue;
        final bool afterIsDep =
            afterType == PlateType.departureRequests.firestoreValue;

        // ── 3-A) parking_requests_view 정합성
        if (shouldSyncReqView) {
          // ① 이탈(또는 area 이동): 기존 view에서 제거
          if (beforeIsReq && (!afterIsReq || areaChanged)) {
            _txRemoveViewItem(
              collection: reqCollection,
              area: beforeArea,
              plateDocId: documentId,
            );
          }

          // ② 진입/잔류: 선택 상태 정책 포함(선택=true면 테이블에서 숨김)
          if (afterIsReq) {
            if (afterSelected) {
              if (typeChanged ||
                  areaChanged ||
                  selectedChanged ||
                  locationChanged ||
                  plateNumberChanged) {
                _txRemoveViewItem(
                  collection: reqCollection,
                  area: afterArea,
                  plateDocId: documentId,
                );
              }
            } else {
              if (typeChanged ||
                  areaChanged ||
                  selectedChanged ||
                  locationChanged ||
                  plateNumberChanged) {
                final reqAt = _extractTimestampForAny(
                  before: before,
                  fields: fields,
                  keys: const <String>['parkingRequestedAt', 'requestTime'],
                );

                _txUpsertViewItemFields(
                  collection: reqCollection,
                  area: afterArea,
                  plateDocId: documentId,
                  plateNumber: afterPlateNumber,
                  location: afterLocation,
                  primaryTimeField: 'parkingRequestedAt',
                  primaryTimeValue: reqAt,
                );
              }
            }
          }
        }

        // ── 3-B) parking_completed_view 정합성
        if (shouldSyncPcView) {
          // ① 이탈(또는 area 이동): 기존 view에서 제거
          if (beforeIsPc && (!afterIsPc || areaChanged)) {
            _txRemoveViewItem(
              collection: pcCollection,
              area: beforeArea,
              plateDocId: documentId,
            );
          }

          // ② 진입/잔류: location(및 plateNumber) 갱신
          if (afterIsPc) {
            if (typeChanged || areaChanged || locationChanged || plateNumberChanged) {
              final pcAt = _extractTimestampForAny(
                before: before,
                fields: fields,
                keys: const <String>['parkingCompletedAt'],
              );

              _txUpsertViewItemFields(
                collection: pcCollection,
                area: afterArea,
                plateDocId: documentId,
                plateNumber: afterPlateNumber,
                location: afterLocation,
                primaryTimeField: 'parkingCompletedAt',
                primaryTimeValue: pcAt,
              );
            }
          }
        }

        // ── 3-C) departure_requests_view 정합성
        if (shouldSyncDepView) {
          // ① 이탈(또는 area 이동): 기존 view에서 제거
          if (beforeIsDep && (!afterIsDep || areaChanged)) {
            _txRemoveViewItem(
              collection: depCollection,
              area: beforeArea,
              plateDocId: documentId,
            );
          }

          // ② 진입/잔류: 선택 상태에 따라 노출/숨김을 포함해 동기화
          if (afterIsDep) {
            // 출차 요청 테이블 정책:
            // - isSelected == true  → view에서 제거(숨김)
            // - isSelected == false → view에 upsert(복구)
            if (afterSelected) {
              if (typeChanged ||
                  areaChanged ||
                  selectedChanged ||
                  locationChanged ||
                  plateNumberChanged) {
                _txRemoveViewItem(
                  collection: depCollection,
                  area: afterArea,
                  plateDocId: documentId,
                );
              }
            } else {
              if (typeChanged ||
                  areaChanged ||
                  selectedChanged ||
                  locationChanged ||
                  plateNumberChanged) {
                final depAt = _extractTimestampForAny(
                  before: before,
                  fields: fields,
                  keys: const <String>['departureRequestedAt'],
                );

                _txUpsertViewItemFields(
                  collection: depCollection,
                  area: afterArea,
                  plateDocId: documentId,
                  plateNumber: afterPlateNumber,
                  location: afterLocation,
                  primaryTimeField: 'departureRequestedAt',
                  primaryTimeValue: depAt,
                );
              }
            }
          }
        }
      });

      debugPrint("✅ 문서 업데이트 완료(+view sync): $documentId");
    } on FirebaseException catch (e) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      rethrow;
    } catch (e) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      rethrow;
    }
  }

  /// ✅ 삭제
  ///
  /// - 기존 호출 호환을 위해 signature 유지 + optional params 추가
  /// - area가 없으면 docId(plate_area)에서 fallback 추출
  ///
  /// syncViews=true일 때 예상 Firestore billable write:
  /// - plates/{id}.delete()                                       -> 1 write
  /// - parking_requests_view/{area}.set(merge, items.{id}:delete) -> 1 write
  /// - parking_completed_view/{area}.set(merge, items.{id}:delete)-> 1 write
  /// - departure_requests_view/{area}.set(merge, items.{id}:delete)->1 write
  /// => 총 4 writes (batch.commit 1회지만 문서 write는 4개로 과금)
  Future<void> deletePlate(
      String documentId, {
        String? area,
        bool syncViews = true,
      }) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    final normalizedArea = (area ?? '').trim().isNotEmpty
        ? area!.trim()
        : _fallbackAreaFromDocId(documentId).trim();

    _debugDeleteCostAndShape(
      plateId: documentId,
      area: normalizedArea,
      syncViews: syncViews && normalizedArea.isNotEmpty,
    );

    try {
      if (!syncViews || normalizedArea.isEmpty) {
        await docRef.delete();
        dev.log("🗑️ 문서 삭제 완료(plates only): $documentId", name: "Firestore");
        return;
      }

      // ✅ batch로 plates + view 정리를 원샷 커밋
      final batch = _firestore.batch();

      batch.delete(docRef);

      void removeFromView(String collection) {
        final viewRef = _firestore.collection(collection).doc(normalizedArea);
        batch.set(
          viewRef,
          <String, dynamic>{
            'area': normalizedArea,
            'updatedAt': FieldValue.serverTimestamp(),
            'items': <String, dynamic>{
              documentId: FieldValue.delete(),
            }
          },
          SetOptions(merge: true),
        );
      }

      removeFromView('parking_requests_view');
      removeFromView('parking_completed_view');
      removeFromView('departure_requests_view');

      await batch.commit();

      dev.log(
        "🗑️ 문서 삭제 완료(+view cleanup): $documentId",
        name: "Firestore",
      );
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        debugPrint("⚠️ 삭제 시 문서 없음 (무시): $documentId");
        return;
      }
      dev.log("🔥 문서 삭제 실패: $e", name: "Firestore");
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  /// ✅ 전환(입차/출차 완료 등) 트랜잭션:
  Future<void> transitionPlateType({
    required String plateId,
    required String actor,
    required String fromType,
    required String toType,
    Map<String, dynamic>? extraFields,
    bool forceOverride = true,
  }) async {
    final docRef = _firestore.collection('plates').doc(plateId);

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef); // READ 1
        if (!snap.exists) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
        }
        final data = snap.data() ?? <String, dynamic>{};
        final currType = (data['type'] as String?) ?? '';

        if (currType != fromType) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'invalid-state',
            message: 'expected $fromType but was $currType',
          );
        }

        final currentSelectedBy = data['selectedBy'] as String?;
        if (!forceOverride &&
            currentSelectedBy != null &&
            currentSelectedBy.isNotEmpty &&
            currentSelectedBy != actor) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'conflict',
            message: 'selected by $currentSelectedBy',
          );
        }

        final update = <String, dynamic>{
          'type': toType,
          'isSelected': false,
          'selectedBy': null,
          'updatedAt': FieldValue.serverTimestamp(),
          if (extraFields != null) ...extraFields,
          'logs': FieldValue.arrayUnion([
            {
              'action': '$fromType → $toType',
              'performedBy': actor,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ]),
        };

        tx.update(docRef, update); // WRITE 1
      });
    } on FirebaseException {
      rethrow;
    } catch (e) {
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  /// ✅ ‘주행’ 커밋 트랜잭션: 서버 상태 검증 + 원샷 업데이트
  ///
  /// ✅ (확장)
  /// - departure_requests 상태: 선택/해제에 따라 departure_requests_view 동기화(삭제/복구)
  /// - parking_requests 상태: 선택/해제에 따라 parking_requests_view 동기화(삭제/복구)
  ///
  /// ✅ (수정안 반영: 정합성)
  /// - 기존: 선택 시 삭제는 항상 수행, 해제 시 복구만 토글 ON일 때 수행 → OFF에서 view 불일치 가능
  /// - 변경: 토글 ON일 때만 삭제/복구 모두 수행(OFF면 view sync 완전 중지)
  Future<void> recordWhoPlateClick(
      String id,
      bool isSelected, {
        String? selectedBy,
        required String area,
      }) async {
    final docRef = _firestore.collection('plates').doc(id);

    // ✅ 트랜잭션 내부에서 prefs 조회 불가 → 사전 조회
    final canUpsertDepView = await _canUpsertDepartureRequestsView();
    final canUpsertReqView = await _canUpsertParkingRequestsView();

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef); // READ 1
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'plate $id not found',
          );
        }

        final data = snap.data() ?? {};
        final type = (data['type'] as String?) ?? '';

        // ✅ 요청 계열 상태에서만 주행(선택) 허용
        const allowed = {'parking_requests', 'departure_requests'};
        if (!allowed.contains(type)) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'invalid-state',
            message: 'cannot set driving on $type',
          );
        }

        // ✅ 선택 충돌 방지
        final currentSelectedBy = data['selectedBy'] as String?;
        if (isSelected &&
            currentSelectedBy != null &&
            currentSelectedBy.isNotEmpty &&
            currentSelectedBy != selectedBy) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'conflict',
            message: 'already selected by $currentSelectedBy',
          );
        }

        final update = <String, dynamic>{
          'isSelected': isSelected,
          'selectedBy': isSelected ? selectedBy : null,
          'updatedAt': FieldValue.serverTimestamp(),
          if (isSelected && (selectedBy?.trim().isNotEmpty ?? false))
            'logs': FieldValue.arrayUnion([
              {
                'action': '주행 중',
                'performedBy': selectedBy,
                'timestamp': DateTime.now().toIso8601String(),
              }
            ]),
        };

        tx.update(docRef, update); // WRITE 1

        final docArea = ((data['area'] as String?) ?? area).trim();

        // ─────────────────────────────────────────
        // departure_requests_view sync
        // ─────────────────────────────────────────
        if (type == 'departure_requests' && docArea.isNotEmpty) {
          // ✅ 토글 OFF면 departure_requests_view 동기화(삭제/복구) 자체를 수행하지 않음
          if (!canUpsertDepView) {
            return;
          }

          final viewRef =
          _firestore.collection('departure_requests_view').doc(docArea);

          if (isSelected) {
            // ✅ 선택 시: items.{id} 삭제 (토글 ON일 때만)
            tx.set(
              viewRef,
              <String, dynamic>{
                'area': docArea,
                'updatedAt': FieldValue.serverTimestamp(),
                'items': <String, dynamic>{
                  id: FieldValue.delete(),
                }
              },
              SetOptions(merge: true),
            );
          } else {
            // ✅ 선택 해제 시: view 복구(upsert) (토글 ON일 때만)
            final plateNumber =
            ((data['plateNumber'] as String?) ?? _fallbackPlateFromDocId(id))
                .trim();
            final location = _normalizeLocation(data['location'] as String?);
            final depRequestedAt = data['departureRequestedAt'];

            tx.set(
              viewRef,
              <String, dynamic>{
                'area': docArea,
                'updatedAt': FieldValue.serverTimestamp(),
                'items': <String, dynamic>{
                  id: <String, dynamic>{
                    'plateNumber': plateNumber,
                    PlateFields.plateNumber: plateNumber,
                    'location': location,
                    'departureRequestedAt':
                    depRequestedAt ?? FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }
                }
              },
              SetOptions(merge: true),
            );
          }
        }

        // ─────────────────────────────────────────
        // parking_requests_view sync
        // ─────────────────────────────────────────
        if (type == 'parking_requests' && docArea.isNotEmpty) {
          // ✅ 토글 OFF면 parking_requests_view 동기화(삭제/복구) 자체를 수행하지 않음
          if (!canUpsertReqView) {
            return;
          }

          final viewRef =
          _firestore.collection('parking_requests_view').doc(docArea);

          if (isSelected) {
            // ✅ 선택 시: items.{id} 삭제 (토글 ON일 때만)
            tx.set(
              viewRef,
              <String, dynamic>{
                'area': docArea,
                'updatedAt': FieldValue.serverTimestamp(),
                'items': <String, dynamic>{
                  id: FieldValue.delete(),
                }
              },
              SetOptions(merge: true),
            );
          } else {
            // ✅ 선택 해제 시: view 복구(upsert) (토글 ON일 때만)
            final plateNumber =
            ((data['plateNumber'] as String?) ?? _fallbackPlateFromDocId(id))
                .trim();
            final location = _normalizeLocation(data['location'] as String?);

            // plates 쪽 시간 필드 우선순위:
            // 1) requestTime(기존 PlateModel)
            // 2) parkingRequestedAt(혹시 직접 저장하는 경우)
            // 3) 서버 시각
            final reqAt = data['requestTime'] ?? data['parkingRequestedAt'];

            tx.set(
              viewRef,
              <String, dynamic>{
                'area': docArea,
                'updatedAt': FieldValue.serverTimestamp(),
                'items': <String, dynamic>{
                  id: <String, dynamic>{
                    'plateNumber': plateNumber,
                    PlateFields.plateNumber: plateNumber,
                    'location': location,
                    'parkingRequestedAt': reqAt ?? FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }
                }
              },
              SetOptions(merge: true),
            );
          }
        }
      });
    } on FirebaseException {
      rethrow;
    } catch (e) {
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  Map<String, dynamic> _enforceZeroFeeLock(
      Map<String, dynamic> data, {
        Map<String, dynamic>? existing,
      }) {
    int effInt(String key) {
      if (data.containsKey(key)) return _toInt(data[key]);
      if (existing != null && existing.containsKey(key)) {
        return _toInt(existing[key]);
      }
      return 0;
    }

    final int basic = effInt(PlateFields.basicAmount);
    final int add = effInt(PlateFields.addAmount);

    final bool shouldLock = (basic == 0 && add == 0);

    if (shouldLock) {
      data[PlateFields.isLockedFee] = true;

      data.putIfAbsent(
        PlateFields.lockedAtTimeInSeconds,
            () => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      );
      data.putIfAbsent(PlateFields.lockedFeeAmount, () => 0);
    }

    return data;
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is num) return v.toInt();
    return 0;
  }

  bool _isSameData(Map<String, dynamic> oldData, Map<String, dynamic> newData) {
    if (oldData.length != newData.length) return false;

    for (String key in oldData.keys) {
      final oldValue = oldData[key];
      final newValue = newData[key];

      if (!_deepEquals(oldValue, newValue)) {
        return false;
      }
    }
    return true;
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }

    if (a is Timestamp && b is Timestamp) {
      return a.toDate() == b.toDate();
    }

    return a == b;
  }
}
