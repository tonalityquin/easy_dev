import 'dart:async';
import '../../../../app/diagnostics/firebase_activity_meter.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_model.dart';
import '../../domain/repositories/plate_repository.dart';

typedef MovementPlateTraceLog = void Function(String message);

class _ViewSyncGate {
  final String name;
  final String writePrefsKey;
  final String? tabPrefsKey;

  const _ViewSyncGate({
    required this.name,
    required this.writePrefsKey,
    this.tabPrefsKey,
  });

  static SharedPreferences? _prefs;
  static Future<void>? _loading;

  static Future<SharedPreferences> _ensurePrefs() async {
    _loading ??= SharedPreferences.getInstance().then((p) => _prefs = p);
    await _loading;
    return _prefs!;
  }

  Future<bool> _getBool(String key) async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(key, true);
    return true;
  }

  Future<bool> shouldSync() async {
    final writeOn = await _getBool(writePrefsKey);
    if (writeOn) return true;
    if (tabPrefsKey == null) return false;
    return _getBool(tabPrefsKey!);
  }

  Future<String> debugReason() async {
    final writeOn = await _getBool(writePrefsKey);
    final tabOn = tabPrefsKey == null ? false : await _getBool(tabPrefsKey!);
    return 'write=${writeOn ? "ON" : "OFF"}, tab=${tabOn ? "ON" : "OFF"}';
  }
}

class MovementPlate extends ChangeNotifier {
  final PlateRepository _repository;
  final UserState _user;

  MovementPlate(this._repository, this._user);

  static const String _parkingCompletedViewCollection =
      'parking_completed_view';

  static const String _departureRequestsViewCollection =
      'departure_requests_view';

  static const String _parkingRequestsViewCollection = 'parking_requests_view';

  static const String _kPcWrite = 'parking_completed_realtime_write_enabled_v1';
  static const String _kDepWrite =
      'departure_requests_realtime_write_enabled_v1';
  static const String _kReqWrite = 'parking_requests_realtime_write_enabled_v1';

  static const String _kPcTab = 'parking_completed_realtime_tab_enabled_v1';
  static const String _kDepTab = 'departure_requests_realtime_tab_enabled_v1';

  static const String _kReqTab = 'parking_requests_realtime_tab_enabled_v1';

  final _ViewSyncGate _pcGate = const _ViewSyncGate(
    name: 'parking_completed_view',
    writePrefsKey: _kPcWrite,
    tabPrefsKey: _kPcTab,
  );

  final _ViewSyncGate _depGate = const _ViewSyncGate(
    name: 'departure_requests_view',
    writePrefsKey: _kDepWrite,
    tabPrefsKey: _kDepTab,
  );

  final _ViewSyncGate _reqGate = const _ViewSyncGate(
    name: 'parking_requests_view',
    writePrefsKey: _kReqWrite,
    tabPrefsKey: _kReqTab,
  );

  String _plateDocId(String plateNumber, String area) => '${plateNumber}_$area';

  void _emitTrace(String message, MovementPlateTraceLog? traceLog) {
    if (traceLog != null) {
      traceLog(message);
      return;
    }
    debugPrint(message);
  }

  void _debugOps({
    required String action,
    required String plateNumber,
    required String area,
    required String plateDocId,
    required int txReads,
    required int txWrites,
    required int viewWritesMin,
    required int viewWritesMax,
    String? gateReason,
    MovementPlateTraceLog? traceLog,
  }) {
    _emitTrace(
      '🧾 [MovementPlate] $action plate=$plateNumber area=$area id=$plateDocId '
      '| 예상 ops: TX_READ=$txReads, TX_WRITE=$txWrites, VIEW_WRITES=$viewWritesMin..$viewWritesMax'
      '${gateReason != null ? " | gate($gateReason)" : ""}',
      traceLog,
    );
  }

  void _reportViewUpsertSuccess({
    required String collection,
    required String area,
    required String plateDocId,
    required DateTime? createdAt,
    MovementPlateTraceLog? traceLog,
  }) {
    final createdAtAvailable = createdAt != null;
    _emitTrace(
      '✅ [MovementPlate.viewUpsert] collection=$collection area=$area plateId=$plateDocId createdAtSource=transition_snapshot createdAtAvailable=$createdAtAvailable additionalPlateRead=0 runtimeHydration=disabled',
      traceLog,
    );
    unawaited(
      DevFirebaseDebugDialog.show(
        operation: 'MovementPlate.viewUpsert.success',
        details: <String, Object?>{
          'collection': collection,
          'actionId': FirebaseActivityMeter.instance.currentActionId,
          'area': area,
          'plateDocId': plateDocId,
          'createdAtSource': 'transition_snapshot',
          'createdAtAvailable': createdAtAvailable,
          'createdAtValue': createdAt?.toIso8601String(),
          'additionalPlateRead': 0,
          'runtimeHydration': 'disabled',
          'missingCreatedAtDisplay': 'dash',
        },
        title: 'View 동기화 확인',
        useCommonUi: true,
        success: true,
        copyAsDebugPrintCode: true,
        devModeOnly: true,
      ),
    );
  }

  Future<void> _upsertParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    required DateTime? createdAt,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    final should = forceViewSync ? true : await _pcGate.shouldSync();
    if (!should) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SKIPPED', source: 'shared/plate/application/common/movement_plate.dart', detail: 'reason=SYNC_GATE_DISABLED method=_upsertParkingCompletedViewItem');
      if (kDebugMode) {
        _emitTrace(
          '🚫 [MovementPlate] skip parking_completed_view upsert (${await _pcGate.debugReason()})',
          traceLog,
        );
      }
      return;
    }

    try {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_START', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=UPSERT collection=$_parkingCompletedViewCollection');
      await _repository.upsertViewItem(
        collection: _parkingCompletedViewCollection,
        area: area,
        plateDocId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAtField: 'parkingCompletedAt',
        createdAt: createdAt,
      );
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SUCCESS', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=UPSERT collection=$_parkingCompletedViewCollection');
      _reportViewUpsertSuccess(
        collection: _parkingCompletedViewCollection,
        area: area,
        plateDocId: plateDocId,
        createdAt: createdAt,
        traceLog: traceLog,
      );
    } catch (e, st) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_FAILED', source: 'shared/plate/application/common/movement_plate.dart', result: 'error', detail: 'operation=UPSERT collection=$_parkingCompletedViewCollection errorType=${e.runtimeType}');
      _emitTrace('⚠️ parking_completed_view upsert 실패: $e', traceLog);
      await DevFirebaseDebugDialog.show(
        operation: 'movement.parking_completed_view.upsert',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _parkingCompletedViewCollection,
          'area': area,
          'plateDocId': plateDocId,
          'location': location,
          'forceViewSync': forceViewSync,
        },
        useCommonUi: true,
        copyAsDebugPrintCode: true,
        devModeOnly: true,
      );
    }
  }

  Future<void> _removeParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    final should = forceViewSync ? true : await _pcGate.shouldSync();
    if (!should) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SKIPPED', source: 'shared/plate/application/common/movement_plate.dart', detail: 'reason=SYNC_GATE_DISABLED method=_removeParkingCompletedViewItem');
      if (kDebugMode) {
        _emitTrace(
          '🚫 [MovementPlate] skip parking_completed_view remove (${await _pcGate.debugReason()})',
          traceLog,
        );
      }
      return;
    }

    try {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_START', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=REMOVE collection=$_parkingCompletedViewCollection');
      await _repository.removeViewItem(
        collection: _parkingCompletedViewCollection,
        area: area,
        plateDocId: plateDocId,
      );
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SUCCESS', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=REMOVE collection=$_parkingCompletedViewCollection');
    } catch (e, st) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_FAILED', source: 'shared/plate/application/common/movement_plate.dart', result: 'error', detail: 'operation=REMOVE collection=$_parkingCompletedViewCollection errorType=${e.runtimeType}');
      _emitTrace('⚠️ parking_completed_view remove 실패: $e', traceLog);
      await DevFirebaseDebugDialog.show(
        operation: 'movement.parking_completed_view.remove',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _parkingCompletedViewCollection,
          'area': area,
          'plateDocId': plateDocId,
          'forceViewSync': forceViewSync,
        },
      );
    }
  }

  Future<void> _upsertDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    required DateTime? createdAt,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    final should = forceViewSync ? true : await _depGate.shouldSync();
    if (!should) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SKIPPED', source: 'shared/plate/application/common/movement_plate.dart', detail: 'reason=SYNC_GATE_DISABLED method=_upsertDepartureRequestsViewItem');
      if (kDebugMode) {
        _emitTrace(
          '🚫 [MovementPlate] skip departure_requests_view upsert (${await _depGate.debugReason()})',
          traceLog,
        );
      }
      return;
    }

    try {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_START', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=UPSERT collection=$_departureRequestsViewCollection');
      await _repository.upsertViewItem(
        collection: _departureRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAtField: 'departureRequestedAt',
        createdAt: createdAt,
      );
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SUCCESS', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=UPSERT collection=$_departureRequestsViewCollection');
      _reportViewUpsertSuccess(
        collection: _departureRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
        createdAt: createdAt,
        traceLog: traceLog,
      );
    } catch (e, st) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_FAILED', source: 'shared/plate/application/common/movement_plate.dart', result: 'error', detail: 'operation=UPSERT collection=$_departureRequestsViewCollection errorType=${e.runtimeType}');
      _emitTrace('⚠️ departure_requests_view upsert 실패: $e', traceLog);
      await DevFirebaseDebugDialog.show(
        operation: 'movement.departure_requests_view.upsert',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _departureRequestsViewCollection,
          'area': area,
          'plateDocId': plateDocId,
          'location': location,
          'forceViewSync': forceViewSync,
        },
        useCommonUi: true,
        copyAsDebugPrintCode: true,
        devModeOnly: true,
      );
    }
  }

  Future<void> _removeDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    final should = forceViewSync ? true : await _depGate.shouldSync();
    if (!should) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SKIPPED', source: 'shared/plate/application/common/movement_plate.dart', detail: 'reason=SYNC_GATE_DISABLED method=_removeDepartureRequestsViewItem');
      if (kDebugMode) {
        _emitTrace(
          '🚫 [MovementPlate] skip departure_requests_view remove (${await _depGate.debugReason()})',
          traceLog,
        );
      }
      return;
    }

    try {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_START', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=REMOVE collection=$_departureRequestsViewCollection');
      await _repository.removeViewItem(
        collection: _departureRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
      );
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SUCCESS', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=REMOVE collection=$_departureRequestsViewCollection');
    } catch (e, st) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_FAILED', source: 'shared/plate/application/common/movement_plate.dart', result: 'error', detail: 'operation=REMOVE collection=$_departureRequestsViewCollection errorType=${e.runtimeType}');
      _emitTrace('⚠️ departure_requests_view remove 실패: $e', traceLog);
      await DevFirebaseDebugDialog.show(
        operation: 'movement.departure_requests_view.remove',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _departureRequestsViewCollection,
          'area': area,
          'plateDocId': plateDocId,
          'forceViewSync': forceViewSync,
        },
      );
    }
  }

  Future<void> _upsertParkingRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    required DateTime? createdAt,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    final should = forceViewSync ? true : await _reqGate.shouldSync();
    if (!should) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SKIPPED', source: 'shared/plate/application/common/movement_plate.dart', detail: 'reason=SYNC_GATE_DISABLED method=_upsertParkingRequestsViewItem');
      if (kDebugMode) {
        _emitTrace(
          '🚫 [MovementPlate] skip parking_requests_view upsert (${await _reqGate.debugReason()})',
          traceLog,
        );
      }
      return;
    }

    try {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_START', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=UPSERT collection=$_parkingRequestsViewCollection');
      await _repository.upsertViewItem(
        collection: _parkingRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAtField: 'parkingRequestedAt',
        createdAt: createdAt,
      );
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SUCCESS', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=UPSERT collection=$_parkingRequestsViewCollection');
      _reportViewUpsertSuccess(
        collection: _parkingRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
        createdAt: createdAt,
        traceLog: traceLog,
      );
    } catch (e, st) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_FAILED', source: 'shared/plate/application/common/movement_plate.dart', result: 'error', detail: 'operation=UPSERT collection=$_parkingRequestsViewCollection errorType=${e.runtimeType}');
      _emitTrace('⚠️ parking_requests_view upsert 실패: $e', traceLog);
      await DevFirebaseDebugDialog.show(
        operation: 'movement.parking_requests_view.upsert',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _parkingRequestsViewCollection,
          'area': area,
          'plateDocId': plateDocId,
          'location': location,
          'forceViewSync': forceViewSync,
        },
        useCommonUi: true,
        copyAsDebugPrintCode: true,
        devModeOnly: true,
      );
    }
  }

  Future<void> _removeParkingRequestsViewItem({
    required String area,
    required String plateDocId,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    final should = forceViewSync ? true : await _reqGate.shouldSync();
    if (!should) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SKIPPED', source: 'shared/plate/application/common/movement_plate.dart', detail: 'reason=SYNC_GATE_DISABLED method=_removeParkingRequestsViewItem');
      if (kDebugMode) {
        _emitTrace(
          '🚫 [MovementPlate] skip parking_requests_view remove (${await _reqGate.debugReason()})',
          traceLog,
        );
      }
      return;
    }

    try {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_START', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=REMOVE collection=$_parkingRequestsViewCollection');
      await _repository.removeViewItem(
        collection: _parkingRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
      );
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_SUCCESS', source: 'shared/plate/application/common/movement_plate.dart', detail: 'operation=REMOVE collection=$_parkingRequestsViewCollection');
    } catch (e, st) {
      FirebaseActivityMeter.instance.traceStep('VIEW_WRITE_FAILED', source: 'shared/plate/application/common/movement_plate.dart', result: 'error', detail: 'operation=REMOVE collection=$_parkingRequestsViewCollection errorType=${e.runtimeType}');
      _emitTrace('⚠️ parking_requests_view remove 실패: $e', traceLog);
      await DevFirebaseDebugDialog.show(
        operation: 'movement.parking_requests_view.remove',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _parkingRequestsViewCollection,
          'area': area,
          'plateDocId': plateDocId,
          'forceViewSync': forceViewSync,
        },
      );
    }
  }

  Future<void> setParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    await FirebaseActivityMeter.instance.traceAction<void>(
      kind: 'TYPE_CHANGE_REQUESTS_TO_COMPLETED',
      source: 'shared/plate/application/common/movement_plate.dart',
      plateId: _plateDocId(plateNumber, area),
      action: () async {
        final actor = _user.name;
        final plateDocId = _plateDocId(plateNumber, area);

        _debugOps(
          action: 'setParkingCompleted(requests→completed)',
          plateNumber: plateNumber,
          area: area,
          plateDocId: plateDocId,
          txReads: 1,
          txWrites: 1,
          viewWritesMin: 0,
          viewWritesMax: 2,
          traceLog: traceLog,
          gateReason:
              'pc(${await _pcGate.debugReason()}), req(${await _reqGate.debugReason()})',
        );

        final createdAt = await _repository.transitionPlateType(
          plateId: plateDocId,
          actor: actor,
          fromType: PlateType.parkingRequests,
          toType: PlateType.parkingCompleted,
          area: area,
          location: location,
          eventAtField: 'parkingCompletedAt',
          forceOverride: forceOverride,
        );

        await _removeParkingRequestsViewItem(
          area: area,
          plateDocId: plateDocId,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
        await _upsertParkingCompletedViewItem(
          area: area,
          plateDocId: plateDocId,
          plateNumber: plateNumber,
          location: location,
          createdAt: createdAt,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
      },
    );
  }

  Future<void> setDepartureRequested(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    await FirebaseActivityMeter.instance.traceAction<void>(
      kind: 'TYPE_CHANGE_COMPLETED_TO_DEPARTURE_REQUESTS',
      source: 'shared/plate/application/common/movement_plate.dart',
      plateId: _plateDocId(plateNumber, area),
      action: () async {
        final actor = _user.name;
        final plateDocId = _plateDocId(plateNumber, area);

        _debugOps(
          action: 'setDepartureRequested(completed→departure_requests)',
          plateNumber: plateNumber,
          area: area,
          plateDocId: plateDocId,
          txReads: 1,
          txWrites: 1,
          viewWritesMin: 0,
          viewWritesMax: 2,
          traceLog: traceLog,
          gateReason:
              'pc(${await _pcGate.debugReason()}), dep(${await _depGate.debugReason()})',
        );

        final createdAt = await _repository.transitionPlateType(
          plateId: plateDocId,
          actor: actor,
          fromType: PlateType.parkingCompleted,
          toType: PlateType.departureRequests,
          area: area,
          location: location,
          eventAtField: 'departureRequestedAt',
          forceOverride: forceOverride,
        );

        await _removeParkingCompletedViewItem(
          area: area,
          plateDocId: plateDocId,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
        await _upsertDepartureRequestsViewItem(
          area: area,
          plateDocId: plateDocId,
          plateNumber: plateNumber,
          location: location,
          createdAt: createdAt,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
      },
    );
  }

  Future<void> setDepartureCompletedDirectFromParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    await FirebaseActivityMeter.instance.traceAction<void>(
      kind: 'TYPE_CHANGE_COMPLETED_TO_DEPARTURE_COMPLETED',
      source: 'shared/plate/application/common/movement_plate.dart',
      plateId: _plateDocId(plateNumber, area),
      action: () async {
        final actor = _user.name;
        final plateDocId = _plateDocId(plateNumber, area);

        _debugOps(
          action:
              'setDepartureCompletedDirectFromParkingCompleted(completed→departure_completed)',
          plateNumber: plateNumber,
          area: area,
          plateDocId: plateDocId,
          txReads: 1,
          txWrites: 1,
          viewWritesMin: 0,
          viewWritesMax: 1,
          traceLog: traceLog,
          gateReason: 'pc(${await _pcGate.debugReason()})',
        );

        await _repository.transitionPlateType(
          plateId: plateDocId,
          actor: actor,
          fromType: PlateType.parkingCompleted,
          toType: PlateType.departureCompleted,
          area: area,
          location: location,
          eventAtField: 'departureCompletedAt',
          forceOverride: forceOverride,
        );

        await _removeParkingCompletedViewItem(
          area: area,
          plateDocId: plateDocId,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
      },
    );
  }

  Future<void> setDepartureCompleted(
    PlateModel selectedPlate, {
    bool forceOverride = true,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    await FirebaseActivityMeter.instance.traceAction<void>(
      kind: 'TYPE_CHANGE_DEPARTURE_REQUESTS_TO_COMPLETED',
      source: 'shared/plate/application/common/movement_plate.dart',
      plateId: selectedPlate.id.isNotEmpty ? selectedPlate.id : _plateDocId(selectedPlate.plateNumber, selectedPlate.area),
      action: () async {
        final actor = _user.name;

        final plateDocId = (selectedPlate.id.isNotEmpty)
            ? selectedPlate.id
            : _plateDocId(selectedPlate.plateNumber, selectedPlate.area);

        _debugOps(
          action: 'setDepartureCompleted(departure_requests→departure_completed)',
          plateNumber: selectedPlate.plateNumber,
          area: selectedPlate.area,
          plateDocId: plateDocId,
          txReads: 1,
          txWrites: 1,
          viewWritesMin: 0,
          viewWritesMax: 1,
          traceLog: traceLog,
          gateReason: 'dep(${await _depGate.debugReason()})',
        );

        await _repository.transitionPlateType(
          plateId: plateDocId,
          actor: actor,
          fromType: PlateType.departureRequests,
          toType: PlateType.departureCompleted,
          area: selectedPlate.area,
          location: selectedPlate.location,
          eventAtField: 'departureCompletedAt',
          forceOverride: forceOverride,
        );

        await _removeDepartureRequestsViewItem(
          area: selectedPlate.area,
          plateDocId: plateDocId,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
      },
    );
  }

  Future<void> goBackToParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    await FirebaseActivityMeter.instance.traceAction<void>(
      kind: 'TYPE_CHANGE_RETURN_TO_PARKING_COMPLETED',
      source: 'shared/plate/application/common/movement_plate.dart',
      plateId: _plateDocId(plateNumber, area),
      action: () async {
        final actor = _user.name;
        final plateDocId = _plateDocId(plateNumber, area);

        _debugOps(
          action: 'goBackToParkingCompleted(departure_requests→completed)',
          plateNumber: plateNumber,
          area: area,
          plateDocId: plateDocId,
          txReads: 1,
          txWrites: 1,
          viewWritesMin: 0,
          viewWritesMax: 2,
          traceLog: traceLog,
          gateReason:
              'dep(${await _depGate.debugReason()}), pc(${await _pcGate.debugReason()})',
        );

        final createdAt = await _repository.transitionPlateType(
          plateId: plateDocId,
          actor: actor,
          fromType: PlateType.departureRequests,
          toType: PlateType.parkingCompleted,
          area: area,
          location: location,
          eventAtField: 'parkingCompletedAt',
          forceOverride: forceOverride,
        );

        await _removeDepartureRequestsViewItem(
          area: area,
          plateDocId: plateDocId,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
        await _upsertParkingCompletedViewItem(
          area: area,
          plateDocId: plateDocId,
          plateNumber: plateNumber,
          location: location,
          createdAt: createdAt,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
      },
    );
  }

  Future<void> goBackToParkingRequest({
    required PlateType fromType,
    required String plateNumber,
    required String area,
    required String newLocation,
    bool forceOverride = true,
    bool forceViewSync = false,
    MovementPlateTraceLog? traceLog,
  }) async {
    await FirebaseActivityMeter.instance.traceAction<void>(
      kind: 'TYPE_CHANGE_RETURN_TO_PARKING_REQUESTS',
      source: 'shared/plate/application/common/movement_plate.dart',
      plateId: _plateDocId(plateNumber, area),
      action: () async {
        final actor = _user.name;
        final plateDocId = _plateDocId(plateNumber, area);

        _debugOps(
          action:
              'goBackToParkingRequest(${fromType.firestoreValue}→parking_requests)',
          plateNumber: plateNumber,
          area: area,
          plateDocId: plateDocId,
          txReads: 1,
          txWrites: 1,
          viewWritesMin: 0,
          viewWritesMax: 2,
          traceLog: traceLog,
          gateReason:
              'req(${await _reqGate.debugReason()}), pc/dep gates apply if removing',
        );

        final createdAt = await _repository.transitionPlateType(
          plateId: plateDocId,
          actor: actor,
          fromType: fromType,
          toType: PlateType.parkingRequests,
          area: area,
          location: newLocation,
          eventAtField: 'requestTime',
          forceOverride: forceOverride,
        );

        if (fromType == PlateType.parkingCompleted) {
          await _removeParkingCompletedViewItem(
            area: area,
            plateDocId: plateDocId,
            forceViewSync: forceViewSync,
            traceLog: traceLog,
          );
        } else if (fromType == PlateType.departureRequests) {
          await _removeDepartureRequestsViewItem(
            area: area,
            plateDocId: plateDocId,
            forceViewSync: forceViewSync,
            traceLog: traceLog,
          );
        }

        await _upsertParkingRequestsViewItem(
          area: area,
          plateDocId: plateDocId,
          plateNumber: plateNumber,
          location: newLocation,
          createdAt: createdAt,
          forceViewSync: forceViewSync,
          traceLog: traceLog,
        );
      },
    );
  }
}
