import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../models/bill_model.dart';
import '../../repositories/bill_repo/bill_repository.dart';
import '../area/area_state.dart';

class BillState extends ChangeNotifier {
  // 🔹 1. 필드
  final BillRepository _repository;
  final AreaState _areaState;

  List<BillModel> _bills = [];
  String? _selectedBillId;
  bool _isLoading = true;
  String _previousArea = '';

  // 🔹 2. 생성자
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

  // 🔹 3. 게터
  List<BillModel> get bills => _bills;

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
      );

  // 🔹 4. Public 메서드

  /// ✅ SharedPreferences 캐시 우선 로드
  Future<void> loadFromBillCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();
    final cachedJson = prefs.getString('cached_bills_$currentArea');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _bills = decoded.map((e) => BillModel.fromCacheMap(Map<String, dynamic>.from(e))).toList();
        _selectedBillId = null;
        _previousArea = currentArea;
        _isLoading = false;
        notifyListeners();
        debugPrint('✅ Bill 캐시 로드 성공 (area: $currentArea)');
      } catch (e) {
        debugPrint('⚠️ Bill 캐시 파싱 실패: $e');
      }
    } else {
      debugPrint('⚠️ 캐시에 정산 데이터 없음 → Firestore 호출 없음');
      _bills = [];
      _selectedBillId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 🔄 수동 새로고침 Firestore 호출 → 캐시 비교 후 갱신
  Future<void> manualBillRefresh() async {
    final currentArea = _areaState.currentArea.trim();
    debugPrint('🔥 수동 새로고침 Firestore 호출 → $currentArea');

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getBillOnce(currentArea);

      final currentIds = _bills.map((e) => e.id).toSet();
      final newIds = data.map((e) => e.id).toSet();

      final isIdentical = currentIds.length == newIds.length && currentIds.containsAll(newIds);

      if (isIdentical) {
        debugPrint('✅ Firestore 데이터가 캐시와 동일 → 갱신 없음');
      } else {
        _bills = data;
        _selectedBillId = null;

        final prefs = await SharedPreferences.getInstance();
        final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
        await prefs.setString('cached_bills_$currentArea', jsonData);

        debugPrint('✅ Firestore 정산 데이터 캐시에 갱신됨 (area: $currentArea)');
      }
    } catch (e) {
      debugPrint('🔥 Firestore 정산 데이터 조회 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✅ 정산 데이터 추가
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
      // ✅ 추가 후 수동 새로고침 호출
      await manualBillRefresh();
    } catch (e) {
      debugPrint('🔥 Bill 추가 실패: $e');
      rethrow;
    }
  }

  /// ✅ 정산 데이터 삭제
  Future<void> deleteBill(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.deleteBill(ids);
      // ✅ 삭제 후 수동 새로고침 호출
      await manualBillRefresh();
    } catch (e) {
      onError?.call('🚨 정산 데이터 삭제 실패: $e');
    }
  }

  /// ✅ 단일 선택 상태 토글
  void toggleBillSelection(String id) {
    if (_selectedBillId == id) {
      _selectedBillId = null; // 같은 거 누르면 해제
    } else {
      _selectedBillId = id; // 새로 선택
    }
    notifyListeners();
  }
}
