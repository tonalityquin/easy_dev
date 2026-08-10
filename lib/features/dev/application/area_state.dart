import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../app/config/email_config.dart';
import '../../../app/models/capability.dart';
import '../domain/repositories/area_repo_package/area_repository.dart';

typedef AreaStateLog = void Function(
  String message, {
  double? progress,
});

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final AreaRepository _repository;

  final Set<String> _availableAreas = {};
  final Map<String, List<String>> _divisionAreaMap = {};
  final Map<String, CapSet> _areaCaps = {};

  String _currentArea = '';
  String _currentDivision = '';
  AreaRecord? _currentRecord;
  int _sessionGeneration = 0;
  Future<void> _recipientSyncQueue = Future<void>.value();

  final String _selectedArea = '';
  final String _selectedDivision = '';
  final bool _isLocked = false;

  String get currentArea => _currentArea;

  String get currentDivision => _currentDivision;

  AreaRecord? get currentRecord => _currentRecord;

  String get selectedArea => _selectedArea;

  String get selectedDivision => _selectedDivision;

  List<String> get availableAreas => _availableAreas.toList();

  bool get isLocked => _isLocked;

  Map<String, List<String>> get divisionAreaMap => _divisionAreaMap;

  CapSet get capabilitiesOfCurrentArea {
    final record = _currentRecord;
    if (record != null && record.name == _currentArea) {
      return record.capabilities;
    }
    return _areaCaps[_currentArea] ?? <Capability>{};
  }

  AreaState(this._repository);

  String _normalizeDivision(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'default' : trimmed;
  }

  void _emit(
    String message, {
    AreaStateLog? onLog,
    double? progress,
  }) {
    if (onLog != null) {
      onLog(message, progress: progress);
      return;
    }
    debugPrint(message);
  }

  bool hasCurrentRecordFor({
    required String division,
    required String area,
  }) {
    final record = _currentRecord;
    if (record == null) return false;
    final normalizedArea = area.trim();
    final normalizedDivision = _normalizeDivision(division);
    return record.name == normalizedArea &&
        _normalizeDivision(record.division) == normalizedDivision;
  }

  AreaRecord? currentRecordFor({
    required String division,
    required String area,
  }) {
    return hasCurrentRecordFor(division: division, area: area)
        ? _currentRecord
        : null;
  }

  void _notifyForegroundWithArea() {
    try {
      FlutterForegroundTask.sendDataToTask({'area': _currentArea});
      debugPrint(
        _currentArea.isEmpty
            ? '[AreaState] FG area clear 전송 완료'
            : '[AreaState] FG area 전송 완료: $_currentArea',
      );
    } catch (error, stackTrace) {
      debugPrint('[AreaState] FG area 전송 실패: $error\n$stackTrace');
    }
  }

  void _applyRecordToState(AreaRecord record) {
    _currentRecord = record;
    _currentArea = record.name;
    _currentDivision = _normalizeDivision(record.division);
    _areaCaps[record.name] = record.capabilities;
    _availableAreas
      ..clear()
      ..add(record.name);
  }

  Future<void> _syncRecipientEmailFromRecord(
    AreaRecord record, {
    required String source,
    required int expectedGeneration,
    AreaStateLog? onLog,
    double? progress,
  }) async {
    final previous = _recipientSyncQueue;
    final next = () async {
      try {
        await previous;
      } catch (_) {}

      if (expectedGeneration != _sessionGeneration) {
        _emit(
          '[AreaState] areas.email 동기화 폐기: source=$source, expectedGeneration=$expectedGeneration, currentGeneration=$_sessionGeneration',
          onLog: onLog,
          progress: progress,
        );
        return;
      }

      final email = record.email.trim();
      if (email.isEmpty) {
        _emit(
          '[AreaState] areas.email 없음: area=${record.name}, division=${record.division}, source=$source',
          onLog: onLog,
          progress: progress,
        );
        await EmailConfig.clear();
        return;
      }

      try {
        _emit(
          '[AreaState] areas.email 수신자 동기화 시작: area=${record.name}, division=${record.division}, email=$email, source=$source',
          onLog: onLog,
          progress: progress,
        );
        await EmailConfig.replaceRecipient(email);
        _emit(
          '[AreaState] areas.email 수신자 동기화 완료: area=${record.name}, email=$email, source=$source',
          onLog: onLog,
          progress: progress,
        );
      } catch (error, stackTrace) {
        _emit(
          '[AreaState] areas.email 수신자 동기화 실패: area=${record.name}, email=$email, source=$source, error=$error',
          onLog: onLog,
          progress: progress,
        );
        _emit(
          '[AreaState] areas.email 스택 추적: $stackTrace',
          onLog: onLog,
          progress: progress,
        );
      }
    }();
    _recipientSyncQueue = next;
    await next;
  }

  Future<void> _clearRecipientEmailForSessionEnd({
    required String source,
    AreaStateLog? onLog,
    double? progress,
  }) async {
    final previous = _recipientSyncQueue;
    final next = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        await EmailConfig.clear();
        _emit(
          '[AreaState] 로그인 세션 이메일 캐시 초기화 완료: source=$source',
          onLog: onLog,
          progress: progress,
        );
      } catch (error, stackTrace) {
        _emit(
          '[AreaState] 로그인 세션 이메일 캐시 초기화 실패: source=$source, error=$error',
          onLog: onLog,
          progress: progress,
        );
        _emit(
          '[AreaState] 로그인 세션 이메일 캐시 초기화 스택 추적: $stackTrace',
          onLog: onLog,
          progress: progress,
        );
      }
    }();
    _recipientSyncQueue = next;
    await next;
  }

  Future<AreaRecord?> _fetchCurrentAreaRecord(
    String area, {
    String? division,
    bool serverOnly = false,
  }) {
    final targetDivision = division?.trim().isNotEmpty == true
        ? division!.trim()
        : _currentDivision.trim();
    return _repository.getAreaByName(
      area,
      division: targetDivision.isEmpty ? null : targetDivision,
      serverOnly: serverOnly,
    );
  }

  bool _hasValidCacheFor(
    String area, {
    String? division,
  }) {
    final trimmed = area.trim();
    if (trimmed.isEmpty) return false;
    final record = _currentRecord;
    if (record == null) return false;
    final targetDivision = division?.trim().isNotEmpty == true
        ? _normalizeDivision(division!)
        : _normalizeDivision(_currentDivision);
    return record.name == trimmed &&
        _normalizeDivision(record.division) == targetDivision;
  }

  Future<void> clearSession({String source = 'logout'}) async {
    _sessionGeneration += 1;
    _currentRecord = null;
    _currentArea = '';
    _currentDivision = '';
    _areaCaps.clear();
    _availableAreas.clear();
    _divisionAreaMap.clear();
    notifyListeners();
    _notifyForegroundWithArea();
    debugPrint(
      '[AreaState] 세션 캐시 초기화 완료: source=$source, generation=$_sessionGeneration',
    );
    await _clearRecipientEmailForSessionEnd(source: source);
  }

  void setAreaLocalOnly(String area, {String? division}) {
    final trimmed = area.trim();
    if (trimmed.isEmpty) {
      debugPrint('[AreaState] setAreaLocalOnly 빈 area 입력');
      return;
    }

    _sessionGeneration += 1;
    _currentRecord = null;
    _currentArea = trimmed;
    _currentDivision = _normalizeDivision(division ?? _currentDivision);
    _availableAreas
      ..clear()
      ..add(trimmed);
    _areaCaps[trimmed] = <Capability>{};

    notifyListeners();
    _notifyForegroundWithArea();
    debugPrint(
      '[AreaState] local only area 적용: $_currentArea / $_currentDivision / generation=$_sessionGeneration',
    );
  }

  Future<AreaRecord> refreshAreaForLogin({
    required String area,
    required String division,
    AreaStateLog? onLog,
  }) async {
    final normalizedArea = area.trim();
    final normalizedDivision = _normalizeDivision(division);
    if (normalizedArea.isEmpty) {
      throw StateError('로그인 지역 정보가 비어 있습니다.');
    }
    if (normalizedDivision == 'default' && division.trim().isEmpty) {
      throw StateError('로그인 회사 정보가 비어 있습니다.');
    }

    final generation = ++_sessionGeneration;
    _currentRecord = null;
    _currentArea = '';
    _currentDivision = '';
    _areaCaps.clear();
    _availableAreas.clear();
    _divisionAreaMap.clear();
    notifyListeners();
    await _clearRecipientEmailForSessionEnd(
      source: 'refreshAreaForLogin.reset',
      onLog: onLog,
      progress: 0.12,
    );
    if (generation != _sessionGeneration) {
      throw StateError('Area 로그인 세션이 변경되어 서버 조회를 시작하지 않습니다.');
    }

    _emit(
      '[AreaState] 로그인 AreaRecord 서버 강제 조회 시작: division=$normalizedDivision, area=$normalizedArea, generation=$generation',
      onLog: onLog,
      progress: 0.18,
    );

    final record = await _repository.getAreaByName(
      normalizedArea,
      division: normalizedDivision,
      serverOnly: true,
    );

    if (generation != _sessionGeneration) {
      throw StateError('Area 로그인 세션이 변경되어 이전 서버 응답을 폐기했습니다.');
    }
    if (record == null) {
      throw StateError(
        '서버에서 로그인 AreaRecord를 찾을 수 없습니다: division=$normalizedDivision, area=$normalizedArea',
      );
    }
    if (record.name != normalizedArea ||
        _normalizeDivision(record.division) != normalizedDivision) {
      throw StateError(
        '서버 AreaRecord가 로그인 대상과 일치하지 않습니다: requested=$normalizedDivision/$normalizedArea, received=${record.division}/${record.name}',
      );
    }

    _applyRecordToState(record);
    _emit(
      '[AreaState] 로그인 AreaRecord 서버 조회 완료: division=${record.division}, area=${record.name}, isHeadquarter=${record.isHeadquarter}, caps=${Cap.human(record.capabilities)}, modes=${record.modes.join(',')}',
      onLog: onLog,
      progress: 0.62,
    );

    await _syncRecipientEmailFromRecord(
      record,
      source: 'refreshAreaForLogin.server',
      expectedGeneration: generation,
      onLog: onLog,
      progress: 0.78,
    );

    if (generation != _sessionGeneration) {
      throw StateError('Area 로그인 세션이 변경되어 동기화 결과를 폐기했습니다.');
    }

    notifyListeners();
    _notifyForegroundWithArea();
    _emit(
      '[AreaState] 로그인 Area 세션 확정 완료: division=$_currentDivision, area=$_currentArea, generation=$generation',
      onLog: onLog,
      progress: 0.92,
    );
    return record;
  }

  Future<bool> resolveIsHeadquarter({
    required String division,
    required String area,
    AreaStateLog? onLog,
  }) async {
    final normalizedArea = area.trim();
    final normalizedDivision = _normalizeDivision(division);
    if (normalizedArea.isEmpty || division.trim().isEmpty) {
      throw StateError('본사 여부 확인에 필요한 division 또는 area가 비어 있습니다.');
    }

    final cached = currentRecordFor(
      division: normalizedDivision,
      area: normalizedArea,
    );
    if (cached != null) {
      _emit(
        '[AreaState] isHeadquarter cache hit: division=$normalizedDivision, area=$normalizedArea, value=${cached.isHeadquarter}',
        onLog: onLog,
        progress: 0.9,
      );
      return cached.isHeadquarter;
    }

    final generation = _sessionGeneration;
    _emit(
      '[AreaState] isHeadquarter cache miss: 서버 fallback 조회 시작: division=$normalizedDivision, area=$normalizedArea',
      onLog: onLog,
      progress: 0.84,
    );

    final record = await _repository.getAreaByName(
      normalizedArea,
      division: normalizedDivision,
      serverOnly: true,
    );
    if (record == null) {
      throw StateError(
        '본사 여부 fallback 조회에서 AreaRecord를 찾을 수 없습니다: division=$normalizedDivision, area=$normalizedArea',
      );
    }
    if (generation != _sessionGeneration) {
      throw StateError('Area 세션이 변경되어 본사 여부 fallback 응답을 폐기했습니다.');
    }
    if (record.name != normalizedArea ||
        _normalizeDivision(record.division) != normalizedDivision) {
      throw StateError('본사 여부 fallback AreaRecord가 현재 사용자와 일치하지 않습니다.');
    }

    _applyRecordToState(record);
    await _syncRecipientEmailFromRecord(
      record,
      source: 'resolveIsHeadquarter.fallback',
      expectedGeneration: generation,
      onLog: onLog,
      progress: 0.9,
    );
    if (generation != _sessionGeneration) {
      throw StateError('Area 세션이 변경되어 본사 여부 fallback 결과를 폐기했습니다.');
    }
    notifyListeners();
    _notifyForegroundWithArea();
    _emit(
      '[AreaState] isHeadquarter 서버 fallback 완료: value=${record.isHeadquarter}',
      onLog: onLog,
      progress: 0.94,
    );
    return record.isHeadquarter;
  }

  Future<void> loadAreasForDivision(String userDivision) async {
    final generation = _sessionGeneration;
    try {
      final records = await _repository.getAreasByDivision(userDivision);
      if (generation != _sessionGeneration) {
        debugPrint('[AreaState] divisionAreaMap 이전 세션 응답 폐기');
        return;
      }

      _divisionAreaMap.clear();

      for (final record in records) {
        _divisionAreaMap.putIfAbsent(record.division, () => <String>[]);
        _divisionAreaMap[record.division]!.add(record.name);
        _areaCaps[record.name] = record.capabilities;
      }

      debugPrint('[AreaState] divisionAreaMap 로딩 완료: $_divisionAreaMap');
      notifyListeners();
    } catch (e) {
      debugPrint('[AreaState] divisionAreaMap 로딩 실패: $e');
    }
  }

  Future<void> initializeArea(
    String userArea, {
    String? division,
    bool forceRefresh = false,
  }) async {
    final area = userArea.trim();
    if (area.isEmpty) {
      debugPrint('[AreaState] initializeArea 빈 area 입력');
      return;
    }

    if (!forceRefresh && _hasValidCacheFor(area, division: division)) {
      debugPrint(
        '[AreaState] initializeArea cache hit: area=$area, division=$_currentDivision',
      );
      notifyListeners();
      _notifyForegroundWithArea();
      return;
    }

    final generation = ++_sessionGeneration;
    try {
      final record = await _fetchCurrentAreaRecord(
        area,
        division: division,
      );
      if (generation != _sessionGeneration) {
        debugPrint('[AreaState] initializeArea 이전 응답 폐기: area=$area');
        return;
      }

      if (record != null) {
        _applyRecordToState(record);
        await _syncRecipientEmailFromRecord(
          record,
          source: 'initializeArea.remote',
          expectedGeneration: generation,
        );
        if (generation != _sessionGeneration) return;
        notifyListeners();
        debugPrint(
          '[AreaState] 사용자 지역 초기화 완료: $_currentArea / $_currentDivision / isHeadquarter=${record.isHeadquarter} / caps=${Cap.human(capabilitiesOfCurrentArea)}',
        );
        _notifyForegroundWithArea();
      } else {
        debugPrint('[AreaState] 저장소에 해당 지역이 존재하지 않음: $area');
        _currentRecord = null;
        _currentArea = '';
        _currentDivision = '';
        notifyListeners();
      }
    } catch (e, st) {
      if (generation == _sessionGeneration) {
        _currentRecord = null;
        _currentArea = '';
        _currentDivision = '';
        notifyListeners();
      }
      debugPrint('[AreaState] 사용자 지역 초기화 실패: $e\n$st');
    }
  }

  Future<bool> refreshCurrentAreaCapabilities() async {
    final area = _currentArea.trim();
    if (area.isEmpty) {
      debugPrint('[AreaState] refreshCurrentAreaCapabilities currentArea 비어 있음');
      return false;
    }

    final generation = _sessionGeneration;
    try {
      final record = await _fetchCurrentAreaRecord(area);

      if (record == null) {
        debugPrint('[AreaState] refreshCurrentAreaCapabilities 지역 정보 없음: $area');
        return false;
      }
      if (generation != _sessionGeneration) {
        debugPrint('[AreaState] refreshCurrentAreaCapabilities 이전 응답 폐기');
        return false;
      }

      final previousCaps = capabilitiesOfCurrentArea;
      _applyRecordToState(record);
      await _syncRecipientEmailFromRecord(
        record,
        source: 'refreshCurrentAreaCapabilities',
        expectedGeneration: generation,
      );
      if (generation != _sessionGeneration) return false;

      notifyListeners();
      final changed = previousCaps.length != record.capabilities.length ||
          !previousCaps.containsAll(record.capabilities);
      debugPrint(
        '[AreaState] currentArea capability 재동기화 완료: $area / caps=${Cap.human(record.capabilities)}',
      );
      return changed;
    } catch (e, st) {
      debugPrint('[AreaState] refreshCurrentAreaCapabilities 실패: $e\n$st');
      return false;
    }
  }

  Future<void> updateAreaPicker(
    String newArea, {
    bool isSyncing = false,
  }) async {
    await _updateAreaCommon(newArea, isSyncing: isSyncing);
  }

  Future<void> updateArea(
    String newArea, {
    bool isSyncing = false,
  }) async {
    await _updateAreaCommon(newArea, isSyncing: isSyncing);
  }

  Future<void> _updateAreaCommon(
    String newArea, {
    required bool isSyncing,
  }) async {
    final normalizedArea = newArea.trim();
    if (normalizedArea.isEmpty) {
      debugPrint('[AreaState] 지역 변경 빈 area 입력');
      return;
    }
    if (_isLocked && !isSyncing) {
      debugPrint('[AreaState] currentArea 보호 중: $newArea');
      return;
    }

    final division = _currentDivision.trim();
    if (hasCurrentRecordFor(division: division, area: normalizedArea)) {
      debugPrint(
        '[AreaState] current AreaRecord 변경 없음: $_currentDivision/$_currentArea',
      );
      return;
    }

    final generation = ++_sessionGeneration;
    try {
      final record = await _repository.getAreaByName(
        normalizedArea,
        division: division.isEmpty ? null : division,
      );
      if (generation != _sessionGeneration) {
        debugPrint('[AreaState] 지역 변경 이전 응답 폐기: $normalizedArea');
        return;
      }

      if (record != null) {
        _applyRecordToState(record);
        await _syncRecipientEmailFromRecord(
          record,
          source: isSyncing ? 'updateArea.sync' : 'updateArea.user',
          expectedGeneration: generation,
        );
        if (generation != _sessionGeneration) return;
        notifyListeners();
        final msg = isSyncing
            ? '[AreaState] 지역 동기화: $_currentArea / division=$_currentDivision'
            : '[AreaState] 지역 변경 완료: $_currentArea / division=$_currentDivision';
        debugPrint('$msg / caps=${Cap.human(capabilitiesOfCurrentArea)}');
        _notifyForegroundWithArea();
      } else {
        debugPrint('[AreaState] 지역 정보 없음: $newArea');
      }
    } catch (e, st) {
      debugPrint('[AreaState] 지역 변경 실패: $e\n$st');
    }
  }
}
