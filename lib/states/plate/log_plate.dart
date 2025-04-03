import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/plate_log_model.dart';
import '../../../repositories/log/plate_log_repository.dart';
import '../../states/area/area_state.dart';

class LogPlateState with ChangeNotifier {
  final PlateLogRepository _repository;
  final AreaState _areaState;

  bool _initialized = false; // ✅ 최초 1회 호출 여부 플래그

  LogPlateState(this._repository, this._areaState) {
    _areaState.addListener(_onAreaChanged); // ✅ 자동 fetch 제거
  }

  List<PlateLogModel> _logs = [];
  List<PlateLogModel> get logs => _logs;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _filterPlateNumber;
  String? get filterPlateNumber => _filterPlateNumber;

  List<PlateLogModel> get filteredLogs {
    final currentArea = _areaState.currentArea;
    var filtered = _logs.where((log) => log.area == currentArea).toList();

    if (_filterPlateNumber != null && _filterPlateNumber!.isNotEmpty) {
      final normalizedFilter = _normalizePlate(_filterPlateNumber!);
      filtered = filtered.where((log) {
        final normalizedPlate = _normalizePlate(log.plateNumber);
        return normalizedPlate == normalizedFilter;
      }).toList();
    }

    debugPrint('[DEBUG] 로그 필터링 결과: ${filtered.length}개 (필터: $_filterPlateNumber)');
    return filtered;
  }

  String _normalizePlate(String input) {
    return input.replaceAll(RegExp(r'[-\s]'), '');
  }

  /// 🔄 단건 조회로 로그 가져오기
  Future<void> _fetchLogs() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('logs')
          .doc('plate_movements')
          .collection('entries')
          .orderBy('timestamp', descending: true)
          .get();

      _logs = snapshot.docs.map((doc) {
        final data = doc.data();
        return PlateLogModel(
          plateNumber: data['plateNumber'] ?? '',
          area: data['area'] ?? '',
          from: data['from'] ?? '',
          to: data['to'] ?? '',
          action: data['action'] ?? '',
          performedBy: data['performedBy'] ?? '',
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      _initialized = true; // ✅ 불러온 적 있음
    } catch (e) {
      debugPrint("❌ 로그 가져오기 실패: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 🔄 외부에서 호출 가능한 새로고침 함수
  Future<void> refreshLogs() async => _fetchLogs();

  bool get isInitialized => _initialized;

  Future<void> saveLog(PlateLogModel log) async {
    try {
      await _repository.savePlateLog(log);
    } catch (e) {
      debugPrint("❌ 로그 저장 실패: $e");
    }
  }

  void _onAreaChanged() {
    notifyListeners();
  }

  void setFilterPlateNumber(String? plateNumber) {
    _filterPlateNumber = plateNumber;
    notifyListeners();
  }

  void clearFilters() {
    _filterPlateNumber = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
