import 'package:flutter/material.dart';

import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../dev/application/area_state.dart';
import '../domain/models/bill_model.dart';
import '../domain/models/regular_bill_model.dart';
import '../domain/repositories/bill_repository.dart';

class BillState extends ChangeNotifier {
  BillState(this._repository, this._localRepository, this._areaState) {
    _previousArea = _areaState.currentArea.trim();
    loadFromBillCache();
    _areaState.addListener(_handleAreaChanged);
  }

  final BillRepository _repository;
  final OperationalLocalRepository _localRepository;
  final AreaState _areaState;

  List<BillModel> _generalBills = <BillModel>[];
  List<RegularBillModel> _regularBills = <RegularBillModel>[];
  String? _selectedBillId;
  bool _isLoading = true;
  String _previousArea = '';
  int _loadToken = 0;

  List<BillModel> get generalBills => _generalBills;
  List<RegularBillModel> get regularBills => _regularBills;
  String? get selectedBillId => _selectedBillId;
  bool get isLoading => _isLoading;

  void _handleAreaChanged() {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea == _previousArea) return;
    _previousArea = currentArea;
    loadFromBillCache();
  }

  Future<void> _saveCacheForArea(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    await _localRepository.replaceBills(
      area: normalizedArea,
      generalBills: _generalBills,
      regularBills: _regularBills,
    );
    final generalCount = await _localRepository.countGeneralBills(normalizedArea);
    final regularCount = await _localRepository.countRegularBills(normalizedArea);
    if (!await _localRepository.hasBillsSnapshot(normalizedArea) ||
        generalCount != _generalBills.length ||
        regularCount != _regularBills.length) {
      throw StateError('정산 SQLite 저장 검증 실패');
    }
    debugPrint(
      '[BillState] SQLite 저장 완료: area=$normalizedArea general=$generalCount regular=$regularCount',
    );
  }

  void _upsertGeneral(BillModel bill) {
    final idx = _generalBills.indexWhere((e) => e.id == bill.id);
    if (idx >= 0) {
      _generalBills = List<BillModel>.of(_generalBills)..[idx] = bill;
    } else {
      _generalBills = <BillModel>[..._generalBills, bill];
    }
  }

  void _upsertRegular(RegularBillModel bill) {
    final idx = _regularBills.indexWhere((e) => e.id == bill.id);
    if (idx >= 0) {
      _regularBills = List<RegularBillModel>.of(_regularBills)..[idx] = bill;
    } else {
      _regularBills = <RegularBillModel>[..._regularBills, bill];
    }
  }

  Future<void> loadFromBillCache() async {
    final requestedArea = _areaState.currentArea.trim();
    final token = ++_loadToken;
    if (requestedArea.isEmpty) {
      _generalBills = <BillModel>[];
      _regularBills = <RegularBillModel>[];
      _selectedBillId = null;
      _previousArea = '';
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final snapshot = await _localRepository.readBills(requestedArea);
      if (token != _loadToken || _areaState.currentArea.trim() != requestedArea) {
        return;
      }
      _generalBills = List<BillModel>.from(snapshot.generalBills);
      _regularBills = List<RegularBillModel>.from(snapshot.regularBills);
      _selectedBillId = null;
      _previousArea = requestedArea;
      _isLoading = false;
      notifyListeners();
      debugPrint(
        '[BillState] SQLite 로드 완료: area=$requestedArea general=${_generalBills.length} regular=${_regularBills.length}',
      );
    } catch (e, stackTrace) {
      debugPrint('[BillState] SQLite 로드 실패: area=$requestedArea error=$e');
      debugPrint('[BillState] stackTrace=$stackTrace');
      if (token != _loadToken || _areaState.currentArea.trim() != requestedArea) {
        return;
      }
      _generalBills = <BillModel>[];
      _regularBills = <RegularBillModel>[];
      _selectedBillId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> manualBillRefresh() async {
    await _refreshBills(rethrowErrors: false);
  }

  Future<void> clearCurrentAreaCache() {
    return clearAreaCache(_areaState.currentArea.trim());
  }

  Future<void> clearAreaCache(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    final affectsCurrentArea =
        _areaState.currentArea.trim() == normalizedArea;
    if (affectsCurrentArea) {
      ++_loadToken;
    }
    await _localRepository.clearBills(normalizedArea);
    if (await _localRepository.countGeneralBills(normalizedArea) != 0 ||
        await _localRepository.countRegularBills(normalizedArea) != 0 ||
        await _localRepository.hasBillsSnapshot(normalizedArea)) {
      throw StateError('기존 정산 SQLite 데이터 삭제 검증 실패');
    }
    if (affectsCurrentArea &&
        _areaState.currentArea.trim() == normalizedArea) {
      _generalBills = <BillModel>[];
      _regularBills = <RegularBillModel>[];
      _selectedBillId = null;
      _previousArea = normalizedArea;
      _isLoading = false;
      notifyListeners();
    }
    debugPrint('[BillState] 지역 SQLite 삭제 완료: area=$normalizedArea');
  }

  Future<void> manualBillRefreshStrict() {
    return manualBillRefreshStrictForArea(_areaState.currentArea.trim());
  }

  Future<void> manualBillRefreshStrictForArea(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    if (_areaState.currentArea.trim() != normalizedArea) {
      throw StateError('정산 동기화 시작 전에 현재 지역이 변경되었습니다.');
    }

    _isLoading = true;
    notifyListeners();
    try {
      final result = await _repository.getAllBills(normalizedArea);
      if (_areaState.currentArea.trim() != normalizedArea) {
        throw StateError('정산 동기화 중 현재 지역이 변경되었습니다.');
      }

      final generalBills = List<BillModel>.from(result.generalBills);
      final regularBills = List<RegularBillModel>.from(result.regularBills);
      await _localRepository.replaceBills(
        area: normalizedArea,
        generalBills: generalBills,
        regularBills: regularBills,
      );
      if (_areaState.currentArea.trim() != normalizedArea) {
        throw StateError('정산 저장 중 현재 지역이 변경되었습니다.');
      }

      if (!await _localRepository.hasBillsSnapshot(normalizedArea)) {
        throw StateError('정산 SQLite 저장 결과가 없습니다.');
      }
      final generalCount =
          await _localRepository.countGeneralBills(normalizedArea);
      final regularCount =
          await _localRepository.countRegularBills(normalizedArea);
      if (generalCount != generalBills.length ||
          regularCount != regularBills.length) {
        throw StateError(
          '정산 SQLite 저장 개수가 일치하지 않습니다: general=$generalCount/${generalBills.length}, regular=$regularCount/${regularBills.length}',
        );
      }

      _generalBills = generalBills;
      _regularBills = regularBills;
      _selectedBillId = null;
      _previousArea = normalizedArea;
      debugPrint(
        '[BillState] 고정 지역 Firestore 새로고침 완료: area=$normalizedArea general=$generalCount regular=$regularCount',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[BillState] 고정 지역 Firestore 새로고침 실패: area=$normalizedArea error=$error',
      );
      debugPrint('[BillState] stackTrace=$stackTrace');
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (_areaState.currentArea.trim() == normalizedArea) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshBills({required bool rethrowErrors}) async {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea.isEmpty) {
      if (rethrowErrors) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      return;
    }

    debugPrint('[BillState] Firestore 새로고침 시작: area=$currentArea');
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _repository.getAllBills(currentArea);
      if (_areaState.currentArea.trim() != currentArea) {
        throw StateError('정산 동기화 중 현재 지역이 변경되었습니다.');
      }
      _generalBills = List<BillModel>.from(result.generalBills);
      _regularBills = List<RegularBillModel>.from(result.regularBills);
      _selectedBillId = null;
      await _saveCacheForArea(currentArea);
      debugPrint(
        '[BillState] Firestore 새로고침 완료: area=$currentArea general=${_generalBills.length} regular=${_regularBills.length}',
      );
    } catch (e, stackTrace) {
      debugPrint('[BillState] Firestore 새로고침 실패: area=$currentArea error=$e');
      debugPrint('[BillState] stackTrace=$stackTrace');
      if (rethrowErrors) {
        Error.throwWithStackTrace(e, stackTrace);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteBill(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    await _deleteBills(
      ids,
      rethrowErrors: false,
      onError: onError,
    );
  }

  Future<void> deleteBillStrict(List<String> ids) async {
    await _deleteBills(ids, rethrowErrors: true);
  }

  Future<void> _deleteBills(
    List<String> ids, {
    required bool rethrowErrors,
    void Function(String)? onError,
  }) async {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea.isEmpty) {
      final error = StateError('현재 지역 정보가 없습니다.');
      onError?.call('🚨 정산 데이터 삭제 실패: ${error.message}');
      if (rethrowErrors) throw error;
      return;
    }
    if (ids.isEmpty) {
      final error = ArgumentError('삭제할 정산 유형이 없습니다.');
      onError?.call('🚨 정산 데이터 삭제 실패: ${error.message}');
      if (rethrowErrors) throw error;
      return;
    }

    final prevGeneral = List<BillModel>.from(_generalBills);
    final prevRegular = List<RegularBillModel>.from(_regularBills);
    final prevSelected = _selectedBillId;

    try {
      final removeSet = ids.toSet();
      _generalBills = _generalBills.where((e) => !removeSet.contains(e.id)).toList();
      _regularBills = _regularBills.where((e) => !removeSet.contains(e.id)).toList();
      if (_selectedBillId != null && removeSet.contains(_selectedBillId)) {
        _selectedBillId = null;
      }
      await _saveCacheForArea(currentArea);
      notifyListeners();
      await _repository.deleteBill(ids);
      debugPrint('[BillState] 정산 데이터 삭제 완료: area=$currentArea ids=${ids.join(',')}');
    } catch (e, stackTrace) {
      _generalBills = prevGeneral;
      _regularBills = prevRegular;
      _selectedBillId = prevSelected;
      try {
        await _saveCacheForArea(currentArea);
      } catch (rollbackError, rollbackStackTrace) {
        debugPrint('[BillState] 정산 삭제 롤백 SQLite 저장 실패: $rollbackError');
        debugPrint('[BillState] rollbackStackTrace=$rollbackStackTrace');
      }
      notifyListeners();
      final message = '🚨 정산 데이터 삭제 실패: $e';
      debugPrint(message);
      debugPrint('[BillState] stackTrace=$stackTrace');
      onError?.call(message);
      if (rethrowErrors) {
        Error.throwWithStackTrace(e, stackTrace);
      }
    }
  }

  void toggleBillSelection(String id) {
    _selectedBillId = (_selectedBillId == id) ? null : id;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedBillId == null) return;
    _selectedBillId = null;
    notifyListeners();
  }

  Future<void> addBillFromMap(Map<String, dynamic> billData) async {
    final typeStr = billData['type'];
    final billType = billTypeFromString(typeStr);
    final currentArea = _areaState.currentArea.trim();

    try {
      if (billType == BillType.general) {
        final bill = BillModel(
          id: '${billData['CountType']}_${billData['area']}',
          countType: billData['CountType'],
          area: billData['area'],
          type: BillType.general,
          basicStandard: billData['basicStandard'],
          basicAmount: billData['basicAmount'],
          addStandard: billData['addStandard'],
          addAmount: billData['addAmount'],
        );
        await _repository.addNormalBill(bill);
        _upsertGeneral(bill);
      } else if (billType == BillType.regular) {
        final bill = RegularBillModel(
          id: '${billData['CountType']}_${billData['area']}',
          countType: billData['CountType'],
          area: billData['area'],
          type: BillType.regular,
          regularType: billData['regularType'],
          regularAmount: billData['regularAmount'],
          regularDurationValue:
              billData['regularDurationValue'] ?? billData['regularDurationHours'],
        );
        await _repository.addRegularBill(bill);
        _upsertRegular(bill);
      } else {
        throw Exception('알 수 없는 정산 유형입니다: $typeStr');
      }
      _selectedBillId = null;
      await _saveCacheForArea(currentArea);
      notifyListeners();
    } catch (e) {
      debugPrint('[BillState] addBillFromMap 실패: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _areaState.removeListener(_handleAreaChanged);
    super.dispose();
  }
}
