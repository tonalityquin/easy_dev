import '../models/normal_parking_completed_record.dart';
import '../repositories/normal_parking_completed_repository.dart';
import 'normal_status_mapping.dart';

class NormalParkingCompletedLogger {
  NormalParkingCompletedLogger._();

  static final NormalParkingCompletedLogger instance = NormalParkingCompletedLogger._();

  final _repo = NormalParkingCompletedRepository();

  Future<void> maybeLogEntryCompleted({
    required String plateNumber,
    required String location,
    required String oldStatus,
    required String newStatus,
  }) async {
    final entryReqToDone =
    (oldStatus == kStatusEntryRequest && newStatus == kStatusEntryDone);

    if (!entryReqToDone) return;

    await _repo.insert(
      NormalParkingCompletedRecord(
        plateNumber: plateNumber,
        location: location,
        createdAt: DateTime.now(),
        isDepartureCompleted: false,
      ),
    );
  }

  Future<void> maybeLogCompleted({
    required String plateNumber,
    required String location,
    required String oldStatus,
    required String newStatus,
  }) async {
    await maybeLogEntryCompleted(
      plateNumber: plateNumber,
      location: location,
      oldStatus: oldStatus,
      newStatus: newStatus,
    );
  }

  Future<void> markDepartureCompleted({
    required String plateNumber,
    required String location,
  }) async {
    await _repo.markLatestDepartureCompleted(
      plateNumber: plateNumber,
      location: location,
    );
  }
}
