import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../account/applications/user_state.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_model.dart';
import '../../domain/repositories/plate_repository.dart';

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
  }) {
    debugPrint(
      '🧾 [MovementPlate] $action plate=$plateNumber area=$area id=$plateDocId '
      '| 예상 ops: TX_READ=$txReads, TX_WRITE=$txWrites, VIEW_WRITES=$viewWritesMin..$viewWritesMax'
      '${gateReason != null ? " | gate($gateReason)" : ""}',
    );
  }

  Future<void> _upsertParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    bool forceViewSync = false,
  }) async {
    final should = forceViewSync ? true : await _pcGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint(
            '🚫 [MovementPlate] skip parking_completed_view upsert (${await _pcGate.debugReason()})');
      }
      return;
    }

    try {
      await _repository.upsertViewItem(
        collection: _parkingCompletedViewCollection,
        area: area,
        plateDocId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAtField: 'parkingCompletedAt',
      );
    } catch (e) {
      debugPrint('⚠️ parking_completed_view upsert 실패: $e');
    }
  }

  Future<void> _removeParkingCompletedViewItem({
    required String area,
    required String plateDocId,
    bool forceViewSync = false,
  }) async {
    final should = forceViewSync ? true : await _pcGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint(
            '🚫 [MovementPlate] skip parking_completed_view remove (${await _pcGate.debugReason()})');
      }
      return;
    }

    try {
      await _repository.removeViewItem(
        collection: _parkingCompletedViewCollection,
        area: area,
        plateDocId: plateDocId,
      );
    } catch (e) {
      debugPrint('⚠️ parking_completed_view remove 실패: $e');
    }
  }

  Future<void> _upsertDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    bool forceViewSync = false,
  }) async {
    final should = forceViewSync ? true : await _depGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint(
            '🚫 [MovementPlate] skip departure_requests_view upsert (${await _depGate.debugReason()})');
      }
      return;
    }

    try {
      await _repository.upsertViewItem(
        collection: _departureRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAtField: 'departureRequestedAt',
      );
    } catch (e) {
      debugPrint('⚠️ departure_requests_view upsert 실패: $e');
    }
  }

  Future<void> _removeDepartureRequestsViewItem({
    required String area,
    required String plateDocId,
    bool forceViewSync = false,
  }) async {
    final should = forceViewSync ? true : await _depGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint(
            '🚫 [MovementPlate] skip departure_requests_view remove (${await _depGate.debugReason()})');
      }
      return;
    }

    try {
      await _repository.removeViewItem(
        collection: _departureRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
      );
    } catch (e) {
      debugPrint('⚠️ departure_requests_view remove 실패: $e');
    }
  }

  Future<void> _upsertParkingRequestsViewItem({
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    bool forceViewSync = false,
  }) async {
    final should = forceViewSync ? true : await _reqGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint(
            '🚫 [MovementPlate] skip parking_requests_view upsert (${await _reqGate.debugReason()})');
      }
      return;
    }

    try {
      await _repository.upsertViewItem(
        collection: _parkingRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAtField: 'parkingRequestedAt',
      );
    } catch (e) {
      debugPrint('⚠️ parking_requests_view upsert 실패: $e');
    }
  }

  Future<void> _removeParkingRequestsViewItem({
    required String area,
    required String plateDocId,
    bool forceViewSync = false,
  }) async {
    final should = forceViewSync ? true : await _reqGate.shouldSync();
    if (!should) {
      if (kDebugMode) {
        debugPrint(
            '🚫 [MovementPlate] skip parking_requests_view remove (${await _reqGate.debugReason()})');
      }
      return;
    }

    try {
      await _repository.removeViewItem(
        collection: _parkingRequestsViewCollection,
        area: area,
        plateDocId: plateDocId,
      );
    } catch (e) {
      debugPrint('⚠️ parking_requests_view remove 실패: $e');
    }
  }

  Future<void> setParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
  }) async {
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
      gateReason:
          'pc(${await _pcGate.debugReason()}), req(${await _reqGate.debugReason()})',
    );

    await _repository.transitionPlateType(
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
    );
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
      forceViewSync: forceViewSync,
    );
  }

  Future<void> setDepartureRequested(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
  }) async {
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
      gateReason:
          'pc(${await _pcGate.debugReason()}), dep(${await _depGate.debugReason()})',
    );

    await _repository.transitionPlateType(
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
    );
    await _upsertDepartureRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
      forceViewSync: forceViewSync,
    );
  }

  Future<void> setDepartureCompletedDirectFromParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
  }) async {
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
    );
  }

  Future<void> setDepartureCompleted(
    PlateModel selectedPlate, {
    bool forceOverride = true,
    bool forceViewSync = false,
  }) async {
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
    );
  }

  Future<void> goBackToParkingCompleted(
    String plateNumber,
    String area,
    String location, {
    bool forceOverride = true,
    bool forceViewSync = false,
  }) async {
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
      gateReason:
          'dep(${await _depGate.debugReason()}), pc(${await _pcGate.debugReason()})',
    );

    await _repository.transitionPlateType(
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
    );
    await _upsertParkingCompletedViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: location,
      forceViewSync: forceViewSync,
    );
  }

  Future<void> goBackToParkingRequest({
    required PlateType fromType,
    required String plateNumber,
    required String area,
    required String newLocation,
    bool forceOverride = true,
    bool forceViewSync = false,
  }) async {
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
      gateReason:
          'req(${await _reqGate.debugReason()}), pc/dep gates apply if removing',
    );

    await _repository.transitionPlateType(
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
      );
    } else if (fromType == PlateType.departureRequests) {
      await _removeDepartureRequestsViewItem(
        area: area,
        plateDocId: plateDocId,
        forceViewSync: forceViewSync,
      );
    }

    await _upsertParkingRequestsViewItem(
      area: area,
      plateDocId: plateDocId,
      plateNumber: plateNumber,
      location: newLocation,
      forceViewSync: forceViewSync,
    );
  }
}
