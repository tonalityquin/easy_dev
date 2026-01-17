import '../models/double_parking_completed_record.dart';
import '../repositories/double_parking_completed_repository.dart';
import 'double_status_mapping.dart';

class DoubleParkingCompletedLogger {
  DoubleParkingCompletedLogger._();

  static final DoubleParkingCompletedLogger instance = DoubleParkingCompletedLogger._();

  final _repo = DoubleParkingCompletedRepository();

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
      DoubleParkingCompletedRecord(
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
