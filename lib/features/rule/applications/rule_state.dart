import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../dev/application/area_state.dart';
import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../domain/models/rule_model.dart';
import '../domain/repositories/rule_repository.dart';

class RuleState extends ChangeNotifier {
  RuleState(
    this._repository,
    this._localRepository,
    this._areaState,
  ) {
    _areaState.addListener(_handleAreaChanged);
    unawaited(loadFromRuleCache());
  }

  final RuleRepository _repository;
  final OperationalLocalRepository _localRepository;
  final AreaState _areaState;

  RuleModel? _rule;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSaving = false;
  String _previousIdentity = '';
  int _dataToken = 0;

  RuleModel? get rule => _rule;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isSaving => _isSaving;
  bool get hasRule => _rule != null;

  String get _division => _areaState.currentDivision.trim();
  String get _area => _areaState.currentArea.trim();
  String get _identity => '$_division/$_area';

  @override
  void dispose() {
    _areaState.removeListener(_handleAreaChanged);
    super.dispose();
  }

  void _handleAreaChanged() {
    final identity = _identity;
    if (identity == _previousIdentity) return;
    unawaited(loadFromRuleCache());
  }

  Future<void> loadFromRuleCache() async {
    final division = _division;
    final area = _area;
    final identity = '$division/$area';
    final token = ++_dataToken;
    _previousIdentity = identity;
    if (division.isEmpty || area.isEmpty) {
      _rule = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      final stored = await _localRepository.readRule(
        division: division,
        area: area,
      );
      if (token != _dataToken || _identity != identity) return;
      _rule = stored;
      debugPrint(
        '[RuleState] SQLite 로드 완료: division=$division area=$area found=${stored != null} todos=${stored?.todoItems.length ?? 0}',
      );
    } catch (error, stackTrace) {
      debugPrint('[RuleState] SQLite 로드 실패: identity=$identity error=$error');
      debugPrint('[RuleState] stackTrace=$stackTrace');
      if (token == _dataToken && _identity == identity) {
        _rule = null;
      }
    } finally {
      if (token == _dataToken && _identity == identity) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> manualRuleRefresh() async {
    await _refreshRemote(rethrowErrors: false);
  }

  Future<void> manualRuleRefreshStrict() async {
    await _refreshRemote(rethrowErrors: true);
  }

  Future<bool> manualRuleRefreshStrictForArea({
    required String division,
    required String area,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    final result = await _repository.getRule(
      division: normalizedDivision,
      area: normalizedArea,
    );
    _validateRule(result, normalizedDivision, normalizedArea);
    await _localRepository.replaceRule(
      division: normalizedDivision,
      area: normalizedArea,
      rule: result,
    );
    final stored = await _localRepository.readRule(
      division: normalizedDivision,
      area: normalizedArea,
    );
    _ensureStoredMatches(stored, result, normalizedDivision, normalizedArea);
    if (_division == normalizedDivision && _area == normalizedArea) {
      _rule = stored;
      _previousIdentity = '$normalizedDivision/$normalizedArea';
      notifyListeners();
    }
    debugPrint(
      '[RuleState] strict refresh 완료: division=$normalizedDivision area=$normalizedArea found=${stored != null} todos=${stored?.todoItems.length ?? 0}',
    );
    return stored != null;
  }

  Future<void> _refreshRemote({required bool rethrowErrors}) async {
    if (_isSaving || _isRefreshing) {
      if (rethrowErrors) throw StateError('다른 업무 규칙 작업이 진행 중입니다.');
      return;
    }
    final division = _division;
    final area = _area;
    final identity = '$division/$area';
    if (division.isEmpty || area.isEmpty) {
      if (rethrowErrors) throw StateError('현재 지역 정보가 없습니다.');
      return;
    }
    final token = ++_dataToken;
    _isRefreshing = true;
    _isLoading = true;
    notifyListeners();
    try {
      final remote = await _repository.getRule(
        division: division,
        area: area,
      );
      if (token != _dataToken || _identity != identity) {
        throw StateError('업무 규칙 동기화 중 현재 지역이 변경되었습니다.');
      }
      _validateRule(remote, division, area);
      await _localRepository.replaceRule(
        division: division,
        area: area,
        rule: remote,
      );
      final stored = await _localRepository.readRule(
        division: division,
        area: area,
      );
      _ensureStoredMatches(stored, remote, division, area);
      _rule = stored;
      _previousIdentity = identity;
      debugPrint(
        '[RuleState] Firestore 새로고침 완료: identity=$identity found=${stored != null}',
      );
    } catch (error, stackTrace) {
      debugPrint('[RuleState] Firestore 새로고침 실패: identity=$identity error=$error');
      debugPrint('[RuleState] stackTrace=$stackTrace');
      if (rethrowErrors) Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _isRefreshing = false;
      if (token == _dataToken && _identity == identity) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<RuleModel> createRule({
    required List<RuleTodoItem> todoItems,
    required String content,
  }) async {
    if (_isSaving || _isRefreshing || _isLoading) {
      throw StateError('다른 업무 규칙 작업이 진행 중입니다.');
    }
    final division = _division;
    final area = _area;
    if (division.isEmpty || area.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    if (_rule != null) throw const RuleAlreadyExistsException();
    ++_dataToken;
    _isSaving = true;
    notifyListeners();
    try {
      final created = await _repository.createRule(
        division: division,
        area: area,
        todoItems: todoItems,
        content: content,
      );
      _ensureAreaUnchanged(division, area);
      await _localRepository.replaceRule(
        division: division,
        area: area,
        rule: created,
      );
      final stored = await _localRepository.readRule(
        division: division,
        area: area,
      );
      _ensureStoredMatches(stored, created, division, area);
      _rule = stored;
      notifyListeners();
      return stored!;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<RuleModel> updateRule({
    required List<RuleTodoItem> todoItems,
    required String content,
  }) async {
    if (_isSaving || _isRefreshing || _isLoading) {
      throw StateError('다른 업무 규칙 작업이 진행 중입니다.');
    }
    final division = _division;
    final area = _area;
    if (division.isEmpty || area.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    if (_rule == null) throw const RuleNotFoundException();
    ++_dataToken;
    _isSaving = true;
    notifyListeners();
    try {
      final updated = await _repository.updateRule(
        division: division,
        area: area,
        todoItems: todoItems,
        content: content,
      );
      _ensureAreaUnchanged(division, area);
      await _localRepository.replaceRule(
        division: division,
        area: area,
        rule: updated,
      );
      final stored = await _localRepository.readRule(
        division: division,
        area: area,
      );
      _ensureStoredMatches(stored, updated, division, area);
      _rule = stored;
      notifyListeners();
      return stored!;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteRule() async {
    if (_isSaving || _isRefreshing || _isLoading) {
      throw StateError('다른 업무 규칙 작업이 진행 중입니다.');
    }
    final division = _division;
    final area = _area;
    if (division.isEmpty || area.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    if (_rule == null) throw const RuleNotFoundException();
    ++_dataToken;
    _isSaving = true;
    notifyListeners();
    try {
      await _repository.deleteRule(division: division, area: area);
      _ensureAreaUnchanged(division, area);
      await _localRepository.clearRule(
        division: division,
        area: area,
      );
      if (await _localRepository.countRules(
            division: division,
            area: area,
          ) !=
          0) {
        throw StateError('업무 규칙 SQLite 삭제 검증 실패');
      }
      _rule = null;
      notifyListeners();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> clearCurrentAreaCache() {
    return clearAreaCache(division: _division, area: _area);
  }

  Future<void> clearAreaCache({
    required String division,
    required String area,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    final affectsCurrent =
        _division == normalizedDivision && _area == normalizedArea;
    if (affectsCurrent) ++_dataToken;
    await _localRepository.clearRule(
      division: normalizedDivision,
      area: normalizedArea,
    );
    final remaining = await _localRepository.countRules(
      division: normalizedDivision,
      area: normalizedArea,
    );
    if (remaining != 0) throw StateError('업무 규칙 SQLite 삭제 검증 실패');
    if (affectsCurrent && _division == normalizedDivision && _area == normalizedArea) {
      _rule = null;
      _isLoading = false;
      notifyListeners();
    }
    debugPrint(
      '[RuleState] SQLite 삭제 완료: division=$normalizedDivision area=$normalizedArea',
    );
  }

  void _ensureAreaUnchanged(String division, String area) {
    if (_division != division || _area != area) {
      throw StateError('업무 규칙 작업 중 현재 지역이 변경되었습니다.');
    }
  }

  void _validateRule(RuleModel? rule, String division, String area) {
    if (rule == null) return;
    if (rule.id != buildRuleDocumentId(division: division, area: area) ||
        rule.division != division ||
        rule.area != area) {
      throw const RuleAreaMismatchException();
    }
    if (rule.todoItems.isEmpty && rule.content.trim().isEmpty) {
      throw StateError('업무 규칙 내용이 없습니다.');
    }
    final ids = <String>{};
    for (var index = 0; index < rule.todoItems.length; index += 1) {
      final item = rule.todoItems[index];
      if (item.id.trim().isEmpty || item.text.trim().isEmpty || item.order != index) {
        throw StateError('업무 규칙 Todo 데이터가 올바르지 않습니다.');
      }
      if (!ids.add(item.id)) throw StateError('업무 규칙 Todo ID가 중복됩니다.');
    }
  }

  void _ensureStoredMatches(
    RuleModel? stored,
    RuleModel? expected,
    String division,
    String area,
  ) {
    _validateRule(stored, division, area);
    _validateRule(expected, division, area);
    if (stored == null || expected == null) {
      if (stored != null || expected != null) {
        throw StateError('업무 규칙 SQLite 존재 여부가 Firestore와 다릅니다.');
      }
      return;
    }
    if (stored.id != expected.id ||
        stored.division != expected.division ||
        stored.area != expected.area ||
        stored.content != expected.content ||
        stored.todoItems.length != expected.todoItems.length) {
      throw StateError('업무 규칙 SQLite 저장 값이 Firestore 값과 다릅니다.');
    }
    for (var index = 0; index < expected.todoItems.length; index += 1) {
      final local = stored.todoItems[index];
      final remote = expected.todoItems[index];
      if (local.id != remote.id ||
          local.text != remote.text ||
          local.order != remote.order) {
        throw StateError('업무 규칙 SQLite Todo 값이 Firestore 값과 다릅니다.');
      }
    }
  }
}
