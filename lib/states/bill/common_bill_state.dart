import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../models/bill_model.dart';
import '../../repositories/bill_repo/bill_repository.dart';
import '../../states/area/area_state.dart';

class CommonBillState extends ChangeNotifier {
  final BillRepository _repository;
  final AreaState _areaState;

  CommonBillState(this._repository, this._areaState) {
    loadFromCache(); // ✅ 캐시 먼저 로딩
    syncWithBillState(); // ✅ 이후 Firestore 최신화
  }

  List<BillModel> _bills = [];
  Map<String, bool> _selectedbill = {};
  bool _isLoading = true;

  String _previousArea = '';

  List<BillModel> get bills => _bills;
  Map<String, bool> get selectebill => _selectedbill;
  bool get isLoading => _isLoading;

  BillModel get emptyModel => BillModel(
    id: '',
    countType: '',
    area: '',
    basicStandard: 0,
    basicAmount: 0,
    addStandard: 0,
    addAmount: 0,
  );

  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();
    final cachedJson = prefs.getString('cached_bills_$currentArea');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _bills = decoded
            .map((e) => BillModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();
        _selectedbill = {for (var bill in _bills) bill.id: false};
        _previousArea = currentArea;
        _isLoading = false;
        notifyListeners();
        debugPrint('✅ Bill 캐시 로드 성공 (area: $currentArea)');
      } catch (e) {
        debugPrint('⚠️ Bill 캐시 파싱 실패: $e');
      }
    }
  }

  /// 🔄 지역 상태 변경 감지 및 Firestore 동기화
  Future<void> syncWithBillState() async {
    final currentArea = _areaState.currentArea.trim();

    if (currentArea.isEmpty || _previousArea == currentArea) {
      debugPrint('✅ Bill 재조회 생략: 동일 지역 ($currentArea)');
      return;
    }

    debugPrint('🔥 Bill 지역 변경 감지: $_previousArea → $currentArea');
    _previousArea = currentArea;

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getBillOnce(currentArea);

      _bills = data;
      _selectedbill = {for (var adj in _bills) adj.id: false};

      // ✅ 캐시 저장
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
      await prefs.setString('cached_bills_$currentArea', jsonData);

      debugPrint("✅ Firestore에서 Bill 데이터 새로 불러옴");
    } catch (e) {
      debugPrint("🔥 Bill Firestore 동기화 실패: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✅ 조정 데이터 추가 (문자열 기반)
  Future<void> addBill(
      String countType,
      String area,
      String basicStandard,
      String basicAmount,
      String addStandard,
      String addAmount,
      ) async {
    try {
      final bill = BillModel(
        id: '${countType}_$area',
        countType: countType,
        area: area,
        basicStandard: int.tryParse(basicStandard) ?? 0,
        basicAmount: int.tryParse(basicAmount) ?? 0,
        addStandard: int.tryParse(addStandard) ?? 0,
        addAmount: int.tryParse(addAmount) ?? 0,
      );

      await _repository.addBill(bill);
      await syncWithBillState();
    } catch (e) {
      debugPrint('🔥 Bill 추가 실패: $e');
      rethrow;
    }
  }

  /// ✅ 삭제
  Future<void> deleteBill(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteBill(ids);
      await syncWithBillState();
    } catch (e) {
      onError?.call('🚨 조정 데이터 삭제 실패: $e');
    }
  }

  void toggleSelection(String id) {
    _selectedbill[id] = !(_selectedbill[id] ?? false);
    notifyListeners();
  }
}
