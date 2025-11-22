import 'package:flutter/foundation.dart';

import '../../../../../repositories/plate_repo_services/plate_count_service.dart';

class EndWorkReportController extends ChangeNotifier {
  final PlateCountService _plateCountService;

  int _vehicleInput = 0;
  int _vehicleOutput = 0;
  int _departureExtra = 0;
  bool _isLoading = false;

  EndWorkReportController({
    PlateCountService? plateCountService,
  }) : _plateCountService = plateCountService ?? PlateCountService();

  int get vehicleInput => _vehicleInput;
  int get vehicleOutput => _vehicleOutput;
  int get departureExtra => _departureExtra;
  int get departureTotal => _vehicleOutput + _departureExtra;
  bool get isLoading => _isLoading;

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

  void setVehicleInputFromText(String value) {
    final parsed = int.tryParse(value);
    _vehicleInput = parsed ?? 0;
    notifyListeners();
  }

  void setVehicleOutputFromText(String value) {
    final parsed = int.tryParse(value);
    _vehicleOutput = parsed ?? 0;
    notifyListeners();
  }

  void setDepartureExtraFromText(String value) {
    final parsed = int.tryParse(value);
    _departureExtra = parsed ?? 0;
    notifyListeners();
  }

  void setVehicleCounts({
    required int input,
    required int output,
  }) {
    _vehicleInput = input;
    _vehicleOutput = output;
    notifyListeners();
  }

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'vehicleInput': _vehicleInput,
      'vehicleOutput': _vehicleOutput,
      'departureExtra': _departureExtra,
      'departureTotal': departureTotal,
    };
  }
}
