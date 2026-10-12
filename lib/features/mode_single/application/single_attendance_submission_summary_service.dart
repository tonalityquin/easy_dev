import '../../../shared/attendance_submission/attendance_submission_repository.dart';
import '../../../shared/attendance_submission/attendance_submission_review_model.dart';
import 'att_brk_mode_db.dart';
import 'single_inside_diagnostics.dart';

enum SingleAttendanceSubmissionKind { commute, restTime }

extension SingleAttendanceSubmissionKindData on SingleAttendanceSubmissionKind {
  List<String> get statuses {
    switch (this) {
      case SingleAttendanceSubmissionKind.commute:
        return const <String>['출근', '퇴근'];
      case SingleAttendanceSubmissionKind.restTime:
        return const <String>['휴게'];
    }
  }

  AttendanceSubmissionKind get reviewKind {
    switch (this) {
      case SingleAttendanceSubmissionKind.commute:
        return AttendanceSubmissionKind.commute;
      case SingleAttendanceSubmissionKind.restTime:
        return AttendanceSubmissionKind.restTime;
    }
  }
}

class SingleAttendanceSubmissionRecord {
  const SingleAttendanceSubmissionRecord({
    required this.status,
    required this.dateTime,
    required this.localTable,
    required this.localDate,
    required this.localType,
  });

  final String status;
  final DateTime dateTime;
  final String localTable;
  final String localDate;
  final String localType;
}

class SingleAttendanceSubmissionSummary {
  const SingleAttendanceSubmissionSummary({
    required this.statuses,
    required this.localRecords,
    required this.uploadTargets,
    required this.latestDay,
    required this.cutoffDay,
  });

  final List<String> statuses;
  final List<SingleAttendanceSubmissionRecord> localRecords;
  final List<SingleAttendanceSubmissionRecord> uploadTargets;
  final DateTime? latestDay;
  final DateTime? cutoffDay;

  int get totalLocalCount => localRecords.length;
  int get eligibleCount => uploadTargets.length;

  int countEligible(String status) =>
      uploadTargets.where((record) => record.status == status).length;
}

class SingleAttendanceSubmissionSummaryService {
  SingleAttendanceSubmissionSummaryService._();

  static Future<SingleAttendanceSubmissionSummary> loadKind(
    SingleAttendanceSubmissionKind kind,
  ) async {
    final snapshot =
        await AttendanceSubmissionReviewRepository.instance.load(kind.reviewKind);
    final summary = _fromSnapshot(snapshot, kind.statuses);
    SingleInsideDiagnostics.log(
      'submission_summary',
      'loaded kind=${kind.name} local=${summary.totalLocalCount} eligible=${summary.eligibleCount} latestLocal=${summary.latestDay?.toIso8601String() ?? '-'} cutoff=${summary.cutoffDay?.toIso8601String() ?? '-'} source=shared_review_repository',
    );
    return summary;
  }

  static Future<SingleAttendanceSubmissionSummary> load({
    required List<String> statuses,
  }) async {
    final kind = statuses.contains('휴게') &&
            !statuses.contains('출근') &&
            !statuses.contains('퇴근')
        ? SingleAttendanceSubmissionKind.restTime
        : SingleAttendanceSubmissionKind.commute;
    return loadKind(kind);
  }

  static Future<int> deleteRecord(
    SingleAttendanceSubmissionRecord record,
  ) async {
    final db = await AttBrkModeDb.instance.database;
    return db.delete(
      record.localTable,
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[record.localDate, record.localType],
    );
  }

  static SingleAttendanceSubmissionSummary _fromSnapshot(
    AttendanceSubmissionReviewSnapshot snapshot,
    List<String> statuses,
  ) {
    SingleAttendanceSubmissionRecord map(AttendanceSubmissionRecord record) {
      return SingleAttendanceSubmissionRecord(
        status: record.status,
        dateTime: record.dateTime,
        localTable: record.localTable,
        localDate: record.localDate,
        localType: record.localType,
      );
    }

    return SingleAttendanceSubmissionSummary(
      statuses: List<String>.unmodifiable(statuses),
      localRecords:
          List<SingleAttendanceSubmissionRecord>.unmodifiable(
        snapshot.localRecords.map(map),
      ),
      uploadTargets:
          List<SingleAttendanceSubmissionRecord>.unmodifiable(
        snapshot.uploadTargets.map(map),
      ),
      latestDay: snapshot.latestLocalDay,
      cutoffDay: snapshot.cutoffDay,
    );
  }
}
