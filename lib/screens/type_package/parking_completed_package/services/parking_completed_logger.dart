// lib/screens/type_package/parking_completed_package/services/parking_completed_logger.dart

import '../repositories/parking_completed_repository.dart';
import '../models/parking_completed_record.dart';
import 'status_mapping.dart';

class ParkingCompletedLogger {
  ParkingCompletedLogger._();
  static final ParkingCompletedLogger instance = ParkingCompletedLogger._();

  final _repo = ParkingCompletedRepository();

  /// ✅ "입차요청 → 입차완료" 인 경우에만 로컬 테이블에 기록
  /// - 출차요청 → 입차완료(되돌리기)는 이제 기록하지 않음
  Future<void> maybeLogEntryCompleted({
    required String plateNumber, // 전체 번호판
    required String location,    // 주차 구역/위치(표시용 명칭)
    required String oldStatus,
    required String newStatus,
  }) async {
    final entryReqToDone =
    (oldStatus == kStatusEntryRequest && newStatus == kStatusEntryDone);

    if (!entryReqToDone) return;

    await _repo.insert(
      ParkingCompletedRecord(
        plateNumber: plateNumber,
        location: location,
        createdAt: DateTime.now(),        // 가능하면 서버 타임스탬프 사용 권장
        isDepartureCompleted: false,      // 입차 직후에는 출차 완료 아님
      ),
    );
  }

  /// (하위호환) 이전 이름 유지 — 내부적으로 maybeLogEntryCompleted 호출
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

  /// ✅ 출차 완료 전이 시: 로컬 테이블에서 가장 최근 미출차 레코드를 출차 완료로 표시
  ///
  /// - "출차요청 → 출차완료"
  /// - "입차완료 → 출차완료" (직접 수정 케이스)
  ///   등에서 공통으로 사용할 수 있도록 상태는 여기선 체크하지 않고,
  ///   호출 측에서 "출차 완료" 상황에서만 호출해준다.
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
