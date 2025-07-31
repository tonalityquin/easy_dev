import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import '../../repositories/bill_repo/bill_repository.dart';
import '../area/area_state.dart';

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

  BillModel get emptyModel => BillModel(
        id: '',
        countType: '',
        area: '',
        basicStandard: 0,
        basicAmount: 0,
        addStandard: 0,
        addAmount: 0,
        type: '일반',
      );

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

  Future<void> loadFromBillCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();

    final generalJson = prefs.getString('cached_general_bills_$currentArea');
    final regularJson = prefs.getString('cached_regular_bills_$currentArea');

    try {
      if (generalJson != null) {
        final decoded = json.decode(generalJson) as List;
        _generalBills = decoded.map((e) => BillModel.fromCacheMap(Map<String, dynamic>.from(e))).toList();
      } else {
        _generalBills = [];
      }

      if (regularJson != null) {
        final decoded = json.decode(regularJson) as List;
        _regularBills = decoded.map((e) => RegularBillModel.fromCacheMap(Map<String, dynamic>.from(e))).toList();
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
    final currentArea = _areaState.currentArea.trim();
    debugPrint('🔥 Firestore 새로고침 시작 → $currentArea');

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _repository.getAllBills(currentArea);

      _generalBills = result.generalBills;
      _regularBills = result.regularBills;
      _selectedBillId = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_general_bills_$currentArea',
        json.encode(result.generalBills.map((e) => e.toCacheMap()).toList()),
      );
      await prefs.setString(
        'cached_regular_bills_$currentArea',
        json.encode(result.regularBills.map((e) => e.toCacheMap()).toList()),
      );

      debugPrint('✅ Firestore 데이터 캐시 갱신 완료');
    } catch (e) {
      debugPrint('🔥 데이터 로드 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addBill(BillModel bill) async {
    try {
      await _repository.addBill(bill);
      await manualBillRefresh();
    } catch (e) {
      debugPrint('🔥 일반 정산 추가 실패: $e');
      rethrow;
    }
  }

  Future<void> addRegularBill(RegularBillModel bill) async {
    try {
      await _repository.addRegularBill(bill);
      await manualBillRefresh();
    } catch (e) {
      debugPrint('🔥 정기 정산 추가 실패: $e');
      rethrow;
    }
  }

  Future<void> deleteBill(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteBill(ids);
      await manualBillRefresh();
    } catch (e) {
      onError?.call('🚨 정산 데이터 삭제 실패: $e');
    }
  }

  void toggleBillSelection(String id) {
    _selectedBillId = (_selectedBillId == id) ? null : id;
    notifyListeners();
  }

  Future<void> addBillFromMap(Map<String, dynamic> billData) async {
    final type = billData['type'];

    try {
      if (type == '일반') {
        final bill = BillModel(
          id: '${billData['CountType']}_${billData['area']}',
          countType: billData['CountType'],
          area: billData['area'],
          type: '일반',
          basicStandard: billData['basicStandard'],
          basicAmount: billData['basicAmount'],
          addStandard: billData['addStandard'],
          addAmount: billData['addAmount'],
        );
        await _repository.addBill(bill);
      } else if (type == '정기') {
        final bill = RegularBillModel(
          id: '${billData['CountType']}_${billData['area']}',
          countType: billData['CountType'],
          area: billData['area'],
          type: '정기',
          regularType: billData['regularType'],
          regularAmount: billData['regularAmount'],
          regularDurationHours: billData['regularDurationHours'],
        );
        await _repository.addRegularBill(bill);
      } else {
        throw Exception('알 수 없는 정산 유형입니다: $type');
      }

      await manualBillRefresh(); // 추가 후 갱신
    } catch (e) {
      debugPrint('🔥 addBillFromMap 실패: $e');
      rethrow;
    }
  }
}
