import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/sensor_trigger_point_store.dart';
import 'sensor_debug_trace.dart';
import 'sensor_trigger_zone.dart';

class SensorTriggerPointState extends ChangeNotifier {
  SensorTriggerPointState(this._store);

  final SensorTriggerPointStore _store;

  String _area = '';
  SensorTriggerZone? _savedCameraZone;
  SensorTriggerZone? _draftCameraZone;
  SensorTriggerZone? _legacyCameraZone;
  Offset? _legacyCameraPoint;
  List<Offset> _draftCameraCorners = const <Offset>[];
  bool _isReady = false;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _lastError;
  String? _lastEditInitialSource;
  int _loadGeneration = 0;

  String get area => _area;
  SensorTriggerZone? get savedCameraZone => _savedCameraZone;
  SensorTriggerZone? get draftCameraZone => _draftCameraZone;
  SensorTriggerZone? get legacyCameraZone => _legacyCameraZone;
  List<Offset> get draftCameraCorners => List<Offset>.unmodifiable(_draftCameraCorners);
  int get placementCount => _draftCameraCorners.length;
  bool get placementComplete => _draftCameraZone != null;
  SensorTriggerZone? get displayCameraZone =>
      _isEditing ? _draftCameraZone : _savedCameraZone;
  Offset? get savedCameraPoint => _savedCameraZone?.center;
  Offset? get draftCameraPoint => _draftCameraZone?.center;
  Offset? get displayCameraPoint => displayCameraZone?.center;
  Offset? get legacyCameraPoint => _legacyCameraPoint;
  bool get isReady => _isReady;
  bool get isEditing => _isEditing;
  bool get isSaving => _isSaving;
  bool get isConfigured => _savedCameraZone != null;
  String? get lastError => _lastError;
  String? get lastEditInitialSource => _lastEditInitialSource;

  Future<void> loadForArea(String area) async {
    final normalized = area.trim();
    if (_isReady && normalized == _area) return;
    final generation = ++_loadGeneration;
    _area = normalized;
    _isReady = false;
    _isEditing = false;
    _isSaving = false;
    _savedCameraZone = null;
    _draftCameraZone = null;
    _legacyCameraZone = null;
    _legacyCameraPoint = null;
    _draftCameraCorners = const <Offset>[];
    _lastError = null;
    _lastEditInitialSource = null;
    notifyListeners();
    SensorDebugTrace.record(
      'SensorTrigger',
      'load_requested',
      <String, Object?>{
        'area': normalized,
        'coordinateSpace': 'camera_image_normalized_polygon_v5',
      },
    );
    try {
      final zone = await _store.loadZone(normalized);
      final legacyZone = zone == null ? await _store.loadLegacyZone(normalized) : null;
      final legacyPoint = zone == null && legacyZone == null
          ? await _store.loadLegacyPoint(normalized)
          : null;
      if (generation != _loadGeneration) return;
      _savedCameraZone = zone;
      _draftCameraZone = zone;
      _legacyCameraZone = legacyZone;
      _legacyCameraPoint = legacyPoint;
      _draftCameraCorners = zone?.points ?? const <Offset>[];
      SensorDebugTrace.record(
        'SensorTrigger',
        'loaded',
        <String, Object?>{
          'area': normalized,
          'configured': zone != null,
          'legacyZoneAvailable': legacyZone != null,
          'legacyPointAvailable': legacyPoint != null,
          ..._zoneDetails(zone),
          'coordinateSpace': 'camera_image_normalized_polygon_v5',
        },
      );
    } catch (error) {
      if (generation != _loadGeneration) return;
      _lastError = error.toString();
      SensorDebugTrace.record(
        'SensorTrigger',
        'load_failed',
        <String, Object?>{'area': normalized, 'error': error},
      );
    } finally {
      if (generation == _loadGeneration) {
        _isReady = true;
        notifyListeners();
      }
    }
  }

  bool beginEdit({
    SensorTriggerZone? initialCameraZone,
    required String initialSource,
  }) {
    if (!_isReady || _isSaving || _area.isEmpty) {
      SensorDebugTrace.record(
        'SensorTrigger',
        'edit_rejected',
        <String, Object?>{
          'ready': _isReady,
          'saving': _isSaving,
          'area': _area,
          'initialSource': initialSource,
        },
      );
      return false;
    }
    _draftCameraZone = initialCameraZone;
    _draftCameraCorners = initialCameraZone?.points ?? const <Offset>[];
    _isEditing = true;
    _lastError = null;
    _lastEditInitialSource = initialSource;
    SensorDebugTrace.record(
      'SensorTrigger',
      'edit_started',
      <String, Object?>{
        'area': _area,
        'configured': _savedCameraZone != null,
        'initialSource': initialSource,
        'placementCount': placementCount,
        ..._zoneDetails(_draftCameraZone),
      },
    );
    notifyListeners();
    return true;
  }

  bool addDraftCameraCorner(Offset point) {
    if (!_isEditing || _isSaving || placementComplete || placementCount >= 4) {
      return false;
    }
    final next = List<Offset>.from(_draftCameraCorners)
      ..add(
        Offset(
          point.dx.clamp(0.0, 1.0).toDouble(),
          point.dy.clamp(0.0, 1.0).toDouble(),
        ),
      );
    if (next.length == 4) {
      final zone = SensorTriggerZone.tryFromPoints(next);
      if (zone == null) {
        SensorDebugTrace.record(
          'SensorTrigger',
          'corner_rejected_invalid_polygon',
          <String, Object?>{
            'corner': 4,
            'cameraX': point.dx.toStringAsFixed(4),
            'cameraY': point.dy.toStringAsFixed(4),
          },
        );
        return false;
      }
      _draftCameraZone = zone;
      _draftCameraCorners = zone.points;
    } else {
      _draftCameraCorners = List<Offset>.unmodifiable(next);
    }
    SensorDebugTrace.record(
      'SensorTrigger',
      'corner_set',
      <String, Object?>{
        'corner': _draftCameraCorners.length,
        'cameraX': point.dx.toStringAsFixed(4),
        'cameraY': point.dy.toStringAsFixed(4),
        'placementComplete': placementComplete,
      },
    );
    notifyListeners();
    return true;
  }

  void updateDraftCameraZone(SensorTriggerZone zone) {
    if (!_isEditing || _isSaving || !zone.isValid) return;
    _draftCameraZone = zone;
    _draftCameraCorners = zone.points;
    notifyListeners();
  }

  bool selectDraftEntryEdge(SensorTriggerZoneEdge edge) {
    final current = _draftCameraZone;
    if (!_isEditing || _isSaving || current == null || !current.isValid) {
      return false;
    }
    if (current.entryEdgeType == edge) return false;
    final next = current.withEntryEdge(edge);
    _draftCameraZone = next;
    _draftCameraCorners = next.points;
    SensorDebugTrace.record(
      'SensorTrigger',
      'entry_edge_selected',
      <String, Object?>{
        'area': _area,
        'entryEdge': edge.name,
        ..._zoneDetails(next),
      },
    );
    notifyListeners();
    return true;
  }

  void cancelEdit() {
    if (!_isEditing || _isSaving) return;
    _draftCameraZone = _savedCameraZone;
    _draftCameraCorners = _savedCameraZone?.points ?? const <Offset>[];
    _isEditing = false;
    _lastError = null;
    SensorDebugTrace.record(
      'SensorTrigger',
      'edit_cancelled',
      <String, Object?>{
        'area': _area,
        ..._zoneDetails(_savedCameraZone),
      },
    );
    notifyListeners();
  }

  Future<bool> saveDraft() async {
    final zone = _draftCameraZone;
    if (!_isEditing || _isSaving || zone == null || !zone.isValid || _area.isEmpty) {
      return false;
    }
    _isSaving = true;
    _lastError = null;
    notifyListeners();
    SensorDebugTrace.record(
      'SensorTrigger',
      'save_requested',
      <String, Object?>{
        'area': _area,
        ..._zoneDetails(zone),
        'coordinateSpace': 'camera_image_normalized_polygon_v5',
      },
    );
    try {
      final saved = await _store.saveZone(_area, zone);
      if (!saved) throw StateError('Sensor trigger polygon persistence failed.');
      _savedCameraZone = zone;
      _draftCameraZone = zone;
      _draftCameraCorners = zone.points;
      _legacyCameraZone = null;
      _legacyCameraPoint = null;
      _isEditing = false;
      SensorDebugTrace.record(
        'SensorTrigger',
        'saved',
        <String, Object?>{
          'area': _area,
          ..._zoneDetails(zone),
          'coordinateSpace': 'camera_image_normalized_polygon_v5',
        },
      );
      return true;
    } catch (error) {
      _lastError = error.toString();
      SensorDebugTrace.record(
        'SensorTrigger',
        'save_failed',
        <String, Object?>{'area': _area, ..._zoneDetails(zone), 'error': error},
      );
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Map<String, Object?> _zoneDetails(SensorTriggerZone? zone) {
    if (zone == null) return const <String, Object?>{};
    return <String, Object?>{
      'p1x': zone.point1.dx.toStringAsFixed(4),
      'p1y': zone.point1.dy.toStringAsFixed(4),
      'p2x': zone.point2.dx.toStringAsFixed(4),
      'p2y': zone.point2.dy.toStringAsFixed(4),
      'p3x': zone.point3.dx.toStringAsFixed(4),
      'p3y': zone.point3.dy.toStringAsFixed(4),
      'p4x': zone.point4.dx.toStringAsFixed(4),
      'p4y': zone.point4.dy.toStringAsFixed(4),
      'polygonArea': zone.area.toStringAsFixed(4),
      'polygonMinEdge': zone.minEdge.toStringAsFixed(4),
      'polygonValid': zone.isValid,
      'entryEdge': zone.entryEdgeType.name,
    };
  }
}
