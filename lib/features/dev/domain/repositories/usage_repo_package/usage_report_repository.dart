class UsageCounterDocUpdate {
  final String documentPath;
  final String date;
  final String area;
  final String userKey;
  final int reads;
  final int writes;
  final int deletes;
  final bool hasTrace;
  final String? lastTraceSource;
  final Map<String, dynamic>? lastTraceExtra;

  const UsageCounterDocUpdate({
    required this.documentPath,
    required this.date,
    required this.area,
    required this.userKey,
    this.reads = 0,
    this.writes = 0,
    this.deletes = 0,
    this.hasTrace = false,
    this.lastTraceSource,
    this.lastTraceExtra,
  });
}

abstract interface class UsageReportRepository {
  Future<void> flushDocUpdates(List<UsageCounterDocUpdate> updates);
}
