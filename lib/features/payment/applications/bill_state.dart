import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../dev/application/area_state.dart';
import '../domain/models/bill_model.dart';
import '../domain/models/regular_bill_model.dart';
import '../domain/repositories/bill_repository.dart';

class BillState extends ChangeNotifier {
  final BillRepository _repository;
  final AreaState _areaState;

  List<BillModel> _generalBills = [];
  List<RegularBillModel> _regularBills = [];
  String? _selectedBillId;
  bool _isLoading = true;
  String _previousArea = '';

  List<BillModel> get generalBills => _generalBills;

  List<RegularBillModel> get regularBills => _regularBills;

  String? get selectedBillId => _selectedBillId;

  bool get isLoading => _isLoading;

  BillState(this._repository, this._areaState) {
    loadFromBillCache();

    _areaState.addListener(() async {
      final currentArea = _areaState.currentArea.trim();
      if (currentArea != _previousArea) {
        _previousArea = currentArea;
        await loadFromBillCache();
      }
    });
  }

  Future<void> _saveCacheForArea(String area) async {
    final prefs = await SharedPreferences.getInstance();
    final generalKey = 'cached_general_bills_$area';
    final regularKey = 'cached_regular_bills_$area';
    final generalJson =
        json.encode(_generalBills.map((e) => e.toCacheMap()).toList());
    final regularJson =
        json.encode(_regularBills.map((e) => e.toCacheMap()).toList());
    final generalSaved = await prefs.setString(generalKey, generalJson);
    final regularSaved = await prefs.setString(regularKey, regularJson);
    if (!generalSaved || !regularSaved) {
      throw StateError('정산 데이터 로컬 저장 실패');
    }
    await prefs.reload();
    if (prefs.getString(generalKey) != generalJson ||
        prefs.getString(regularKey) != regularJson) {
      throw StateError('정산 데이터 로컬 저장 검증 실패');
    }
  }

  void _upsertGeneral(BillModel bill) {
    final idx = _generalBills.indexWhere((e) => e.id == bill.id);
    if (idx >= 0) {
      _generalBills = List.of(_generalBills)..[idx] = bill;
    } else {
      _generalBills = [..._generalBills, bill];
    }
  }

  void _upsertRegular(RegularBillModel bill) {
    final idx = _regularBills.indexWhere((e) => e.id == bill.id);
    if (idx >= 0) {
      _regularBills = List.of(_regularBills)..[idx] = bill;
    } else {
      _regularBills = [..._regularBills, bill];
    }
  }

  Future<void> loadFromBillCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();

    final generalJson = prefs.getString('cached_general_bills_$currentArea');
    final regularJson = prefs.getString('cached_regular_bills_$currentArea');

    try {
      if (generalJson != null) {
        final decoded = json.decode(generalJson) as List;
        _generalBills = decoded
            .map((e) => BillModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        _generalBills = [];
      }

      if (regularJson != null) {
        final decoded = json.decode(regularJson) as List;
        _regularBills = decoded
            .map((e) =>
                RegularBillModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        _regularBills = [];
      }

      _selectedBillId = null;
      _previousArea = currentArea;
      _isLoading = false;
      notifyListeners();
      debugPrint('✅ Bill 캐시 로드 완료');
    } catch (e) {
      debugPrint('⚠️ 캐시 파싱 오류: $e');
      _generalBills = [];
      _regularBills = [];
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> manualBillRefresh() async {
    await _refreshBills(rethrowErrors: false);
  }

  Future<void> clearCurrentAreaCache() async {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }

    final prefs = await SharedPreferences.getInstance();
    final generalKey = 'cached_general_bills_$currentArea';
    final regularKey = 'cached_regular_bills_$currentArea';
    await prefs.remove(generalKey);
    await prefs.remove(regularKey);
    await prefs.reload();
    if (prefs.containsKey(generalKey) || prefs.containsKey(regularKey)) {
      throw StateError('기존 정산 로컬 데이터 삭제 검증 실패');
    }

    _generalBills = [];
    _regularBills = [];
    _selectedBillId = null;
    _previousArea = currentArea;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> manualBillRefreshStrict() async {
    await _refreshBills(rethrowErrors: true);

    final currentArea = _areaState.currentArea.trim();
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('cached_general_bills_$currentArea') ||
        !prefs.containsKey('cached_regular_bills_$currentArea')) {
      throw StateError('정산 로컬 데이터 저장 결과가 없습니다.');
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

    debugPrint('🔥 Firestore 새로고침 시작 → $currentArea');
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _repository.getAllBills(currentArea);
      _generalBills = result.generalBills;
      _regularBills = result.regularBills;
      _selectedBillId = null;
      await _saveCacheForArea(currentArea);
      debugPrint('✅ Firestore 데이터 캐시 갱신 완료');
    } catch (e) {
      debugPrint('🔥 데이터 로드 실패: $e');
      if (rethrowErrors) rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteBill(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    final currentArea = _areaState.currentArea.trim();

    final prevGeneral = List<BillModel>.from(_generalBills);
    final prevRegular = List<RegularBillModel>.from(_regularBills);
    final prevSelected = _selectedBillId;

    try {
      final removeSet = ids.toSet();
      _generalBills =
          _generalBills.where((e) => !removeSet.contains(e.id)).toList();
      _regularBills =
          _regularBills.where((e) => !removeSet.contains(e.id)).toList();

      if (_selectedBillId != null && removeSet.contains(_selectedBillId)) {
        _selectedBillId = null;
      }

      await _saveCacheForArea(currentArea);

      notifyListeners();

      await _repository.deleteBill(ids);
    } catch (e) {
      _generalBills = prevGeneral;
      _regularBills = prevRegular;
      _selectedBillId = prevSelected;
      await _saveCacheForArea(currentArea);
      notifyListeners();

      onError?.call('🚨 정산 데이터 삭제 실패: $e');
    }
  }

  void toggleBillSelection(String id) {
    _selectedBillId = (_selectedBillId == id) ? null : id;
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
          regularDurationValue: billData['regularDurationValue'] ?? billData['regularDurationHours'],
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
      debugPrint('🔥 addBillFromMap 실패: $e');
      rethrow;
    }
  }
}
