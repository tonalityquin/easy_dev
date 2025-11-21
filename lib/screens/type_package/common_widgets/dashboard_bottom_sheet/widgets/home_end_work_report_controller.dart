// lib/controllers/home_end_work_report_controller.dart
import 'package:flutter/foundation.dart';

import '../../../../../repositories/plate_repo_services/plate_count_service.dart';

/// 업무 종료 보고 화면에서
/// - 입차/출차 집계 가져오기
/// - 현재 입력 값 상태 관리
/// 를 담당하는 Controller (ViewModel 느낌)
class HomeEndWorkReportController extends ChangeNotifier {
  final PlateCountService _plateCountService;

  int _vehicleInput = 0;

  /// 출차 agg (plates 기준)
  int _vehicleOutput = 0;

  /// 출차 보정치 (plate_counters 기준)
  int _departureExtra = 0;

  bool _isLoading = false;

  HomeEndWorkReportController({
    PlateCountService? plateCountService,
  }) : _plateCountService = plateCountService ?? PlateCountService();

  int get vehicleInput => _vehicleInput;

  /// 출차 agg (plates 컬렉션 집계 값)
  int get vehicleOutput => _vehicleOutput;

  /// 출차 보정치 (plate_counters/area_<area>.departureCompletedEvents)
  int get departureExtra => _departureExtra;

  /// 출차 합계 (agg + 보정치)
  int get departureTotal => _vehicleOutput + _departureExtra;

  bool get isLoading => _isLoading;

  /// 현재 area 기준으로 입차/출차 집계 초기값 로드
  Future<void> loadInitialCounts(String area) async {
    if (area.isEmpty) {
      _vehicleInput = 0;
      _vehicleOutput = 0;
      _departureExtra = 0;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait<int>([
        _plateCountService.getParkingCompletedAggCount(area),
        _plateCountService.getDepartureCompletedAggCount(area),
        _plateCountService.getDepartureCompletedExtraCount(area),
      ]);

      _vehicleInput = results[0];
      _vehicleOutput = results[1];
      _departureExtra = results[2];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// TextField 입력값을 반영 (입차)
  void setVehicleInputFromText(String value) {
    final parsed = int.tryParse(value);
    _vehicleInput = parsed ?? 0;
    notifyListeners();
  }

  /// TextField 입력값을 반영 (출차 agg)
  void setVehicleOutputFromText(String value) {
    final parsed = int.tryParse(value);
    _vehicleOutput = parsed ?? 0;
    notifyListeners();
  }

  /// TextField 입력값을 반영 (출차 보정치)
  void setDepartureExtraFromText(String value) {
    final parsed = int.tryParse(value);
    _departureExtra = parsed ?? 0;
    notifyListeners();
  }

  /// 직접 값 세팅하고 싶을 때 (예: 제출 직전 동기화)
  /// - extra는 그대로 유지
  void setVehicleCounts({
    required int input,
    required int output,
  }) {
    _vehicleInput = input;
    _vehicleOutput = output;
    notifyListeners();
  }

  /// EndWorkReportService에 넘길 payload 형태로 변환
  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'vehicleInput': _vehicleInput,
      'vehicleOutput': _vehicleOutput,
      'departureExtra': _departureExtra,
      'departureTotal': departureTotal,
    };
  }
}
