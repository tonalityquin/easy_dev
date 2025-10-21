import '../repositories/parking_completed_repository.dart';
import '../models/parking_completed_record.dart';

/// 상태 텍스트 상수
const kStatusEntryRequest  = '입차 요청';
const kStatusEntryDone     = '입차 완료';
const kStatusExitRequest   = '출차 요청';
const kStatusExitDone      = '출차 완료'; // (참고: 지금 요구조건에서는 사용 안 함)

class ParkingCompletedLogger {
  ParkingCompletedLogger._();
  static final ParkingCompletedLogger instance = ParkingCompletedLogger._();

  final _repo = ParkingCompletedRepository();

  /// 입차요청→입차완료, 출차요청→입차완료 인 경우만 기록
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
      createdAt: DateTime.now(), // 가능하면 서버 타임스탬프로 대체 권장
    ));
  }
}
