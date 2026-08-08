import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../app/config/email_config.dart';
import '../../../app/models/capability.dart';
import '../domain/repositories/area_repo_package/area_repository.dart';

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final AreaRepository _repository;

  final Set<String> _availableAreas = {};
  final Map<String, List<String>> _divisionAreaMap = {};

  String _currentArea = '';
  String _currentDivision = '';

  final String _selectedArea = '';
  final String _selectedDivision = '';
  final bool _isLocked = false;

  final Map<String, CapSet> _areaCaps = {};

  String get currentArea => _currentArea;

  String get currentDivision => _currentDivision;

  String get selectedArea => _selectedArea;

  String get selectedDivision => _selectedDivision;

  List<String> get availableAreas => _availableAreas.toList();

  bool get isLocked => _isLocked;

  Map<String, List<String>> get divisionAreaMap => _divisionAreaMap;

  CapSet get capabilitiesOfCurrentArea =>
      _areaCaps[_currentArea] ?? <Capability>{};

  AreaState(this._repository);

  void _notifyForegroundWithArea() {
    if (_currentArea.isNotEmpty) {
      FlutterForegroundTask.sendDataToTask({'area': _currentArea});
      debugPrint('📤 FG로 area 전송: $_currentArea');
    } else {
      debugPrint('⚠️ currentArea 가 비어 있어 FG 전송 스킵');
    }
  }

  void _applyRecordToState(AreaRecord record) {
    _currentArea = record.name;
    _currentDivision =
        record.division.trim().isEmpty ? 'default' : record.division.trim();
    _areaCaps[record.name] = record.capabilities;

    _availableAreas
      ..clear()
      ..add(record.name);
  }

  Future<void> _syncRecipientEmailFromRecord(
    AreaRecord record, {
    required String source,
  }) async {
    final email = record.email.trim();
    if (email.isEmpty) {
      debugPrint(
        '[AreaState] areas.email 없음 또는 빈 값: area=${record.name}, division=${record.division}, source=$source → 기존 mail.to 유지',
      );
      return;
    }

    try {
      debugPrint(
        '[AreaState] areas.email 수신자 동기화 시작: area=${record.name}, division=${record.division}, email=$email, source=$source',
      );
      await EmailConfig.replaceRecipient(email);
      debugPrint(
        '[AreaState] areas.email 수신자 동기화 완료: area=${record.name}, email=$email, source=$source',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[AreaState] areas.email 수신자 동기화 실패: area=${record.name}, email=$email, source=$source, error=$error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<AreaRecord?> _fetchCurrentAreaRecord(String area) {
    final division = _currentDivision.trim();
    return _repository.getAreaByName(
      area,
      division: division.isEmpty ? null : division,
    );
  }

  bool _hasValidCacheFor(String area) {
    final trimmed = area.trim();
    if (trimmed.isEmpty) return false;

    final sameArea = (_currentArea == trimmed);
    final caps = _areaCaps[trimmed];
    final hasCaps = caps != null && caps.isNotEmpty;
    final hasDivision = _currentDivision.trim().isNotEmpty;

    if (sameArea && (hasCaps || hasDivision)) return true;
    if (_availableAreas.contains(trimmed) && hasCaps) return true;

    return false;
  }

  void setAreaLocalOnly(String area, {String? division}) {
    final trimmed = area.trim();
    if (trimmed.isEmpty) {
      debugPrint('⚠️ setAreaLocalOnly: 빈 area 입력 → 스킵');
      return;
    }

    _currentArea = trimmed;

    if (division != null && division.trim().isNotEmpty) {
      _currentDivision = division.trim();
    } else if (_currentDivision.trim().isEmpty) {
      _currentDivision = 'default';
    }

    _availableAreas
      ..clear()
      ..add(trimmed);

    _areaCaps.putIfAbsent(trimmed, () => <Capability>{});

    notifyListeners();
    _notifyForegroundWithArea();
    debugPrint(
      'ℹ️ setAreaLocalOnly: $_currentArea / $_currentDivision (no Firestore)',
    );
  }

  Future<void> loadAreasForDivision(String userDivision) async {
    try {
      final records = await _repository.getAreasByDivision(userDivision);

      _divisionAreaMap.clear();

      for (final record in records) {
        _divisionAreaMap.putIfAbsent(record.division, () => <String>[]);
        _divisionAreaMap[record.division]!.add(record.name);
        _areaCaps[record.name] = record.capabilities;
      }

      debugPrint('✅ divisionAreaMap 로딩 완료: $_divisionAreaMap');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ divisionAreaMap 로딩 실패: $e');
    }
  }

  Future<void> initializeArea(String userArea,
      {bool forceRefresh = false}) async {
    final area = userArea.trim();
    if (area.isEmpty) {
      debugPrint('⚠️ initializeArea: 빈 area 입력 → 스킵');
      return;
    }

    if (!forceRefresh && _hasValidCacheFor(area)) {
      debugPrint('ℹ️ initializeArea: cache hit → 지역 상태 캐시 사용: "$area"');
      _currentArea = area;
      if (_currentDivision.trim().isEmpty) {
        _currentDivision = 'default';
      }
      notifyListeners();
      _notifyForegroundWithArea();

      try {
        final record = await _fetchCurrentAreaRecord(area);
        if (record != null) {
          await _syncRecipientEmailFromRecord(
            record,
            source: 'initializeArea.cacheHit',
          );
        } else {
          debugPrint(
            '[AreaState] currentArea 문서 조회 실패: area=$area, division=$_currentDivision, source=initializeArea.cacheHit',
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[AreaState] currentArea 이메일 조회 실패: area=$area, division=$_currentDivision, error=$error',
        );
        debugPrint('$stackTrace');
      }
      return;
    }

    try {
      final record = await _fetchCurrentAreaRecord(area);

      if (record != null) {
        _applyRecordToState(record);
        await _syncRecipientEmailFromRecord(
          record,
          source: 'initializeArea.remote',
        );

        notifyListeners();
        debugPrint(
          '✅ 사용자 지역 초기화 완료 → $_currentArea / $_currentDivision'
          ' / caps: ${Cap.human(capabilitiesOfCurrentArea)}',
        );

        _notifyForegroundWithArea();
      } else {
        debugPrint('⚠️ 저장소에 해당 지역이 존재하지 않음: $area');
        _currentArea = '';
        _currentDivision = '';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ 사용자 지역 초기화 실패: $e');
      _currentArea = '';
      _currentDivision = '';
      notifyListeners();
    }
  }

  Future<bool> refreshCurrentAreaCapabilities() async {
    final area = _currentArea.trim();
    if (area.isEmpty) {
      debugPrint('⚠️ refreshCurrentAreaCapabilities: currentArea 비어 있음');
      return false;
    }

    try {
      final record = await _fetchCurrentAreaRecord(area);

      if (record == null) {
        debugPrint('⚠️ refreshCurrentAreaCapabilities: 지역 정보 없음: $area');
        return false;
      }

      final previousCaps = _areaCaps[area] ?? <Capability>{};
      _areaCaps[area] = record.capabilities;
      await _syncRecipientEmailFromRecord(
        record,
        source: 'refreshCurrentAreaCapabilities',
      );
      _currentDivision = record.division.trim().isEmpty
          ? (_currentDivision.trim().isEmpty ? 'default' : _currentDivision)
          : record.division.trim();

      _availableAreas
        ..clear()
        ..add(area);

      notifyListeners();
      final changed = previousCaps.length != record.capabilities.length ||
          !previousCaps.containsAll(record.capabilities);
      debugPrint(
          '✅ currentArea capability 재동기화 완료: $area / caps: ${Cap.human(record.capabilities)}');
      return changed;
    } catch (e) {
      debugPrint('❌ refreshCurrentAreaCapabilities 실패: $e');
      return false;
    }
  }

  Future<void> updateAreaPicker(String newArea,
      {bool isSyncing = false}) async {
    await _updateAreaCommon(newArea, isSyncing: isSyncing);
  }

  Future<void> updateArea(String newArea, {bool isSyncing = false}) async {
    await _updateAreaCommon(newArea, isSyncing: isSyncing);
  }

  Future<void> _updateAreaCommon(String newArea,
      {required bool isSyncing}) async {
    if (_isLocked && !isSyncing) {
      debugPrint('⛔ currentArea는 보호 중 → 변경 무시됨 (입력: $newArea)');
      return;
    }

    if (_currentArea == newArea) {
      debugPrint('ℹ️ currentArea 변경 없음: $_currentArea 그대로 유지됨');
      return;
    }

    try {
      final division = _currentDivision.trim();
      final record = await _repository.getAreaByName(
        newArea,
        division: division.isEmpty ? null : division,
      );

      if (record != null) {
        _applyRecordToState(record);
        await _syncRecipientEmailFromRecord(
          record,
          source: isSyncing ? 'updateArea.sync' : 'updateArea.user',
        );

        notifyListeners();
        final msg = isSyncing
            ? '🔄 지역 동기화: $_currentArea / division: $_currentDivision'
            : '✅ 지역 변경됨: $_currentArea / division: $_currentDivision';
        debugPrint('$msg / caps: ${Cap.human(capabilitiesOfCurrentArea)}');

        _notifyForegroundWithArea();
      } else {
        debugPrint('⚠️ 지역 정보 없음 - 변경 무시됨: $newArea');
      }
    } catch (e) {
      debugPrint('❌ 지역 변경 실패: $e');
    }
  }
}
