class AttendanceActionResult {
  const AttendanceActionResult._({
    required this.success,
    required this.message,
    required this.recordedAt,
    required this.alreadyRecorded,
  });

  const AttendanceActionResult.success({
    required DateTime recordedAt,
    String message = '출퇴근 기록이 완료되었습니다.',
  }) : this._(
          success: true,
          message: message,
          recordedAt: recordedAt,
          alreadyRecorded: false,
        );

  const AttendanceActionResult.alreadyRecorded({
    required String message,
  }) : this._(
          success: false,
          message: message,
          recordedAt: null,
          alreadyRecorded: true,
        );

  const AttendanceActionResult.failure({
    required String message,
  }) : this._(
          success: false,
          message: message,
          recordedAt: null,
          alreadyRecorded: false,
        );

  final bool success;
  final String message;
  final DateTime? recordedAt;
  final bool alreadyRecorded;
}
