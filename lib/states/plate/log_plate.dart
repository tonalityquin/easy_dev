import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/plate_log_model.dart';
import '../../../repositories/log/plate_log_repository.dart';
import '../../states/area/area_state.dart';

class LogPlateState with ChangeNotifier {
  final PlateLogRepository _repository;
  final AreaState _areaState;

  LogPlateState(this._repository, this._areaState) {
    _listenToLogs(); // ✅ 앱 실행 시 로그 실시간 수신
    _areaState.addListener(_onAreaChanged); // ✅ 지역 변경 감지
  }

  // 🔹 전체 로그 리스트
  List<PlateLogModel> _logs = [];

  // 🔹 외부에서 접근 가능한 전체 로그 (필터 X)
  List<PlateLogModel> get logs => _logs;

  // 🔹 로딩 여부
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // 🔹 필터 값 (번호판)
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


  /// 🔧 번호판 문자열을 정규화 (공백/하이픈 제거)
  String _normalizePlate(String input) {
    return input.replaceAll(RegExp(r'[-\s]'), '');
  }


  /// ✅ Firestore 실시간 로그 수신
  void _listenToLogs() {
    FirebaseFirestore.instance
        .collection('logs')
        .doc('plate_movements')
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
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

      _isLoading = false;
      notifyListeners(); // 데이터 수신 → UI 갱신
    }, onError: (error) {
      debugPrint("❌ 로그 스트림 오류: $error");
    });
  }

  /// ✅ 로그 저장
  Future<void> saveLog(PlateLogModel log) async {
    try {
      await _repository.savePlateLog(log);
    } catch (e) {
      debugPrint("❌ 로그 저장 실패: $e");
    }
  }

  /// 🔄 지역 변경 시 UI 갱신
  void _onAreaChanged() {
    notifyListeners(); // 필터 적용 갱신
  }

  /// 🔍 번호판 필터 적용
  void setFilterPlateNumber(String? plateNumber) {
    _filterPlateNumber = plateNumber;
    debugPrint('[DEBUG] setFilterPlateNumber 호출됨: $plateNumber');
    notifyListeners();
  }



  /// 🔄 필터 초기화
  void clearFilters() {
    _filterPlateNumber = null;
    notifyListeners();
  }

  /// 🧹 리스너 제거
  @override
  void dispose() {
    _areaState.removeListener(_onAreaChanged);
    super.dispose();
  }
}
