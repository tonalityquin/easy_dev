class BreakRecordResult {
  const BreakRecordResult._({
    required this.success,
    required this.message,
    required this.recordedAt,
  });

  const BreakRecordResult.success({
    required DateTime recordedAt,
    String message = '휴게 기록이 완료되었습니다.',
  }) : this._(
          success: true,
          message: message,
          recordedAt: recordedAt,
        );

  const BreakRecordResult.failure({
    required String message,
  }) : this._(
          success: false,
          message: message,
          recordedAt: null,
        );

  final bool success;
  final String message;
  final DateTime? recordedAt;
}
