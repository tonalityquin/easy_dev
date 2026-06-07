import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../enums/plate_type.dart';
import '../models/plate_log_model.dart';
import '../models/plate_model.dart';

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

String _locationFullFromAny(dynamic raw) {
  if (raw is Map) {
    final m = Map<String, dynamic>.from(raw);
    final full = (m['full'] as String?)?.trim();
    if (full != null && full.isNotEmpty) return full;

    final parent = (m['parent'] as String?)?.trim() ?? '';
    final child = (m['child'] as String?)?.trim() ?? '';
    final slot = (m['slot'] as String?)?.trim() ?? '';
    final segs = <String>[parent, child, slot]
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return segs.isEmpty ? _kLocUnknown : segs.join(_kLocSep);
  }

  if (raw is String) {
    final v = raw.trim();
    return v.isEmpty ? _kLocUnknown : v;
  }

  return _kLocUnknown;
}

Map<String, dynamic> _normalizePlatesLocationValue(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String) return _locationToMap(v);
  return _locationToMap(_kLocUnknown);
}

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _kDepartureRequestsViewWritePrefsKey =
      'departure_requests_realtime_write_enabled_v1';

  static const String _kParkingRequestsViewWritePrefsKey =
      'parking_requests_realtime_write_enabled_v1';

  static const String _kParkingCompletedViewWritePrefsKey =
      'parking_completed_realtime_write_enabled_v1';

  static const String _kDepartureRequestsViewTabPrefsKey =
      'departure_requests_realtime_tab_enabled_v1';
  static const String _kParkingCompletedViewTabPrefsKey =
      'parking_completed_realtime_tab_enabled_v1';

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
    await prefs.setBool(_kDepartureRequestsViewWritePrefsKey, true);
    return true;
  }

  static Future<bool> _canUpsertParkingRequestsView() async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(_kParkingRequestsViewWritePrefsKey, true);
    return true;
  }

  static Future<bool> _canUpsertParkingCompletedView() async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(_kParkingCompletedViewWritePrefsKey, true);
    return true;
  }

  static Future<bool> _isDepartureRequestsRealtimeTabEnabled() async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(_kDepartureRequestsViewTabPrefsKey, true);
    return true;
  }

  static Future<bool> _isParkingCompletedRealtimeTabEnabled() async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(_kParkingCompletedViewTabPrefsKey, true);
    return true;
  }

  static Future<bool> _isParkingRequestsRealtimeTabEnabled() async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(_kParkingRequestsViewTabPrefsKey, true);
    return true;
  }

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

  String _extractPlateNumberFromPlateDoc(
      Map<String, dynamic> data, String docId) {
    final v1 = (data['plateNumber'] as String?)?.trim();
    if (v1 != null && v1.isNotEmpty) return v1;

    final v2 = (data[PlateFields.plateNumber] as String?)?.trim();
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

  String _normalizeLocation(dynamic raw) {
    final v = _locationFullFromAny(raw).trim();
    return v.isEmpty ? '미지정' : v;
  }

  dynamic _extractTimestampForAny({
    required Map<String, dynamic> before,
    required Map<String, dynamic> fields,
    required List<String> keys,
  }) {
    for (final k in keys) {
      final vNew = fields[k];
      if (vNew is Timestamp) return vNew;
      final vOld = before[k];
      if (vOld is Timestamp) return vOld;
    }
    return null;
  }

  bool get _dbDebugEnabled => kDebugMode;

  void _debugDeleteCostAndShape({
    required String plateId,
    required String area,
    required bool syncViews,
  }) {
    if (!_dbDebugEnabled) return;

    final viewWrites = syncViews ? 3 : 0;
    final totalWrites = 1 + viewWrites;

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

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      final docSnapshot =
          await docRef.get().timeout(const Duration(seconds: 10));

      var newData = plate.toMap();

      if (newData.containsKey(PlateFields.location)) {
        newData[PlateFields.location] =
            _normalizePlatesLocationValue(newData[PlateFields.location]);
      }

      newData = _enforceZeroFeeLock(newData, existing: docSnapshot.data());

      final exists = docSnapshot.exists;
      final existingData = docSnapshot.data() ?? const <String, dynamic>{};

      final compOld = Map<String, dynamic>.from(existingData)
        ..remove(PlateFields.logs);
      final compNew = Map<String, dynamic>.from(newData)
        ..remove(PlateFields.logs);

      if (exists && _isSameData(compOld, compNew)) {
        return;
      }

      if (exists) {
        newData.remove(PlateFields.logs);
      }

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

    final bool shouldSyncPcView = await _shouldSyncParkingCompletedView();
    final bool shouldSyncDepView = await _shouldSyncDepartureRequestsView();
    final bool shouldSyncReqView = await _shouldSyncParkingRequestsView();

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'plate $documentId not found',
          );
        }

        final before = snap.data() ?? <String, dynamic>{};

        final fields = _enforceZeroFeeLock(
          Map<String, dynamic>.from(updatedFields),
          existing: before,
        );

        if (fields.containsKey(PlateFields.location)) {
          fields[PlateFields.location] =
              _normalizePlatesLocationValue(fields[PlateFields.location]);
        }

        if (log != null) {
          fields['logs'] = FieldValue.arrayUnion([log.toMap()]);
        }

        fields['updatedAt'] = FieldValue.serverTimestamp();

        tx.update(docRef, fields);

        final String beforeType =
            ((before[PlateFields.type] as String?) ?? '').trim();
        final String afterType =
            (((fields[PlateFields.type] as String?) ?? beforeType)).trim();

        final String beforeArea = _extractAreaFromPlateDoc(before, documentId);

        final String afterArea = (() {
          final raw = fields[PlateFields.area];
          if (raw is String && raw.trim().isNotEmpty) return raw.trim();
          return beforeArea;
        })();

        final String beforePlateNumber =
            _extractPlateNumberFromPlateDoc(before, documentId);

        String afterPlateNumber = beforePlateNumber;
        final String? pn1 = (fields['plateNumber'] as String?)?.trim();
        final String? pn2 =
            (fields[PlateFields.plateNumber] as String?)?.trim();
        if (pn1 != null && pn1.isNotEmpty) {
          afterPlateNumber = pn1;
        } else if (pn2 != null && pn2.isNotEmpty) {
          afterPlateNumber = pn2;
        }

        final String beforeLocation =
            _normalizeLocation(before[PlateFields.location]);
        final String afterLocation = _normalizeLocation(
          fields.containsKey(PlateFields.location)
              ? fields[PlateFields.location]
              : before[PlateFields.location],
        );

        final bool beforeSelected = _toBool(before[PlateFields.isSelected]);
        final bool afterSelected = fields.containsKey(PlateFields.isSelected)
            ? _toBool(fields[PlateFields.isSelected])
            : beforeSelected;

        final String beforeSelectedBy =
            ((before[PlateFields.selectedBy] as String?) ?? '').trim();
        final String afterSelectedBy = (() {
          final raw = fields[PlateFields.selectedBy];
          if (raw is String) return raw.trim();
          if (fields.containsKey(PlateFields.selectedBy)) return '';
          return beforeSelectedBy;
        })();

        final bool typeChanged = beforeType != afterType;
        final bool areaChanged = beforeArea != afterArea;
        final bool locationChanged = beforeLocation != afterLocation;
        final bool plateNumberChanged = beforePlateNumber != afterPlateNumber;
        final bool selectedChanged = beforeSelected != afterSelected;
        final bool selectedByChanged = beforeSelectedBy != afterSelectedBy;

        final bool affectsViews = typeChanged ||
            areaChanged ||
            locationChanged ||
            plateNumberChanged ||
            selectedChanged ||
            selectedByChanged;

        if (!affectsViews) {
          return;
        }

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
          bool includeSelectionState = false,
          bool isSelected = false,
          String? selectedBy,
        }) {
          if (area.trim().isEmpty) return;

          final ref = _viewRef(collection, area.trim());
          final selectedByValue = isSelected ? selectedBy?.trim() : null;

          final item = <String, dynamic>{
            'plateNumber': plateNumber,
            PlateFields.plateNumber: plateNumber,
            'location': location,
            'updatedAt': FieldValue.serverTimestamp(),
            if (primaryTimeField != null)
              primaryTimeField:
                  primaryTimeValue ?? FieldValue.serverTimestamp(),
            if (includeSelectionState) 'isSelected': isSelected,
            if (includeSelectionState)
              'selectedBy': selectedByValue == null || selectedByValue.isEmpty
                  ? null
                  : selectedByValue,
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

        if (shouldSyncReqView) {
          if (beforeIsReq && (!afterIsReq || areaChanged)) {
            _txRemoveViewItem(
              collection: reqCollection,
              area: beforeArea,
              plateDocId: documentId,
            );
          }

          if (afterIsReq) {
            if (typeChanged ||
                areaChanged ||
                selectedChanged ||
                selectedByChanged ||
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
                includeSelectionState: true,
                isSelected: afterSelected,
                selectedBy: afterSelectedBy,
              );
            }
          }
        }

        if (shouldSyncPcView) {
          if (beforeIsPc && (!afterIsPc || areaChanged)) {
            _txRemoveViewItem(
              collection: pcCollection,
              area: beforeArea,
              plateDocId: documentId,
            );
          }

          if (afterIsPc) {
            if (typeChanged ||
                areaChanged ||
                locationChanged ||
                plateNumberChanged) {
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

        if (shouldSyncDepView) {
          if (beforeIsDep && (!afterIsDep || areaChanged)) {
            _txRemoveViewItem(
              collection: depCollection,
              area: beforeArea,
              plateDocId: documentId,
            );
          }

          if (afterIsDep) {
            if (typeChanged ||
                areaChanged ||
                selectedChanged ||
                selectedByChanged ||
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
                includeSelectionState: true,
                isSelected: afterSelected,
                selectedBy: afterSelectedBy,
              );
            }
          }
        }
      });

      debugPrint("✅ 문서 업데이트 완료(+view sync): $documentId");
    } on FirebaseException catch (e, st) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'plateWrite.updatePlate',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'documentId': documentId,
            'updatedFields': updatedFields.keys.toList(growable: false),
            'hasLog': log != null,
          },
        ),
      );
      rethrow;
    } catch (e, st) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'plateWrite.updatePlate',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'documentId': documentId,
            'updatedFields': updatedFields.keys.toList(growable: false),
            'hasLog': log != null,
          },
        ),
      );
      rethrow;
    }
  }

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
        final snap = await tx.get(docRef);
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

        Map<String, dynamic>? normalizedExtra;
        if (extraFields != null) {
          normalizedExtra = Map<String, dynamic>.from(extraFields);
          if (normalizedExtra.containsKey(PlateFields.location)) {
            normalizedExtra[PlateFields.location] =
                _normalizePlatesLocationValue(
                    normalizedExtra[PlateFields.location]);
          } else if (normalizedExtra.containsKey('location')) {
            normalizedExtra['location'] =
                _normalizePlatesLocationValue(normalizedExtra['location']);
          }
        }

        final update = <String, dynamic>{
          'type': toType,
          'isSelected': false,
          'selectedBy': null,
          'updatedAt': FieldValue.serverTimestamp(),
          if (normalizedExtra != null) ...normalizedExtra,
          'logs': FieldValue.arrayUnion([
            {
              'action': '$fromType → $toType',
              'performedBy': actor,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ]),
        };

        tx.update(docRef, update);
      });
    } on FirebaseException catch (e, st) {
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'plateWrite.transitionPlateType',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'plateId': plateId,
            'actor': actor,
            'fromType': fromType,
            'toType': toType,
            'extraFields': extraFields?.keys.toList(growable: false),
            'forceOverride': forceOverride,
          },
        ),
      );
      rethrow;
    } catch (e, st) {
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'plateWrite.transitionPlateType',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'plateId': plateId,
            'actor': actor,
            'fromType': fromType,
            'toType': toType,
            'extraFields': extraFields?.keys.toList(growable: false),
            'forceOverride': forceOverride,
          },
        ),
      );
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  Future<void> recordWhoPlateClick(
    String id,
    bool isSelected, {
    String? selectedBy,
    required String area,
  }) async {
    final docRef = _firestore.collection('plates').doc(id);

    final canUpsertDepView = await _canUpsertDepartureRequestsView();
    final canUpsertReqView = await _canUpsertParkingRequestsView();

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'plate $id not found',
          );
        }

        final data = snap.data() ?? {};
        final type = (data['type'] as String?) ?? '';
        final typeEnum = plateTypeFromFirestoreValue(type);

        final allowed = {
          PlateType.parkingRequests,
          PlateType.departureRequests,
        };
        if (!allowed.contains(typeEnum)) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'invalid-state',
            message: 'cannot set driving on $type',
          );
        }

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

        tx.update(docRef, update);

        final docArea = ((data['area'] as String?) ?? area).trim();

        if (typeEnum == PlateType.departureRequests && docArea.isNotEmpty) {
          if (!canUpsertDepView) {
            return;
          }

          final viewRef =
              _firestore.collection('departure_requests_view').doc(docArea);

          final plateNumber = ((data['plateNumber'] as String?) ??
                  _fallbackPlateFromDocId(id))
              .trim();

          final location = _normalizeLocation(data['location']);

          final depRequestedAt = data['departureRequestedAt'];
          final selectedByValue = isSelected ? selectedBy?.trim() : null;

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
                  'isSelected': isSelected,
                  'selectedBy': selectedByValue == null || selectedByValue.isEmpty
                      ? null
                      : selectedByValue,
                  'updatedAt': FieldValue.serverTimestamp(),
                }
              }
            },
            SetOptions(merge: true),
          );
        }

        if (typeEnum == PlateType.parkingRequests && docArea.isNotEmpty) {
          if (!canUpsertReqView) {
            return;
          }

          final viewRef =
              _firestore.collection('parking_requests_view').doc(docArea);

          final plateNumber = ((data['plateNumber'] as String?) ??
                  _fallbackPlateFromDocId(id))
              .trim();

          final location = _normalizeLocation(data['location']);

          final reqAt = data['requestTime'] ?? data['parkingRequestedAt'];
          final selectedByValue = isSelected ? selectedBy?.trim() : null;

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
                  'isSelected': isSelected,
                  'selectedBy': selectedByValue == null || selectedByValue.isEmpty
                      ? null
                      : selectedByValue,
                  'updatedAt': FieldValue.serverTimestamp(),
                }
              }
            },
            SetOptions(merge: true),
          );
        }
      });
    } on FirebaseException catch (e, st) {
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'plateWrite.recordWhoPlateClick',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'plateId': id,
            'isSelected': isSelected,
            'selectedBy': selectedBy,
            'areaArgument': area,
          },
        ),
      );
      rethrow;
    } catch (e, st) {
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'plateWrite.recordWhoPlateClick',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'plateId': id,
            'isSelected': isSelected,
            'selectedBy': selectedBy,
            'areaArgument': area,
          },
        ),
      );
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

    if (a is Map && b is Map) {
      final am = Map<String, dynamic>.from(a);
      final bm = Map<String, dynamic>.from(b);
      if (am.length != bm.length) return false;
      for (final k in am.keys) {
        if (!bm.containsKey(k)) return false;
        if (!_deepEquals(am[k], bm[k])) return false;
      }
      return true;
    }

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
