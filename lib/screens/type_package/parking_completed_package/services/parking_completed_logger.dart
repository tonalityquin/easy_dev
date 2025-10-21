import '../repositories/parking_completed_repository.dart';
import '../models/parking_completed_record.dart';
import 'status_mapping.dart';

class ParkingCompletedLogger {
  ParkingCompletedLogger._();
  static final ParkingCompletedLogger instance = ParkingCompletedLogger._();

  final _repo = ParkingCompletedRepository();

  /// 기록 조건: 입차요청→입차완료, 출차요청→입차완료
  Future<void> maybeLogCompleted({
    required String plateNumber, // 전체 번호판
    required String area,        // 주차 구역(표시용 명칭)
    required String oldStatus,
    required String newStatus,
  }) async {
    final entryReqToDone =
    (oldStatus == kStatusEntryRequest && newStatus == kStatusEntryDone);
    final exitReqToEntryDone =
    (oldStatus == kStatusExitRequest && newStatus == kStatusEntryDone);

    if (!(entryReqToDone || exitReqToEntryDone)) return;

    await _repo.insert(ParkingCompletedRecord(
      plateNumber: plateNumber,
      area: area,
      createdAt: DateTime.now(), // 가능하면 서버 타임스탬프 사용 권장
    ));
  }
}
