import 'package:flutter/material.dart';

enum AttendanceSubmissionKind {
  commute,
  restTime,
}

extension AttendanceSubmissionKindUi on AttendanceSubmissionKind {
  String get title {
    switch (this) {
      case AttendanceSubmissionKind.commute:
        return '출퇴근 기록 제출';
      case AttendanceSubmissionKind.restTime:
        return '휴게시간 기록 제출';
    }
  }

  String get shortLabel {
    switch (this) {
      case AttendanceSubmissionKind.commute:
        return '출퇴근';
      case AttendanceSubmissionKind.restTime:
        return '휴게시간';
    }
  }

  IconData get icon {
    switch (this) {
      case AttendanceSubmissionKind.commute:
        return Icons.cloud_upload_outlined;
      case AttendanceSubmissionKind.restTime:
        return Icons.coffee_rounded;
    }
  }

  List<String> get statuses {
    switch (this) {
      case AttendanceSubmissionKind.commute:
        return const <String>['출근', '퇴근'];
      case AttendanceSubmissionKind.restTime:
        return const <String>['휴게'];
    }
  }
}

enum AttendanceReviewDayState {
  complete,
  missing,
  empty,
}

extension AttendanceReviewDayStateUi on AttendanceReviewDayState {
  String get label {
    switch (this) {
      case AttendanceReviewDayState.complete:
        return '정상';
      case AttendanceReviewDayState.missing:
        return '누락';
      case AttendanceReviewDayState.empty:
        return '미기록';
    }
  }
}

class AttendanceSubmissionRecord {
  const AttendanceSubmissionRecord({
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

class AttendanceReviewDay {
  const AttendanceReviewDay({
    required this.date,
    this.workIn,
    this.workOut,
    this.breakTime,
    this.draft = false,
  });

  final DateTime date;
  final String? workIn;
  final String? workOut;
  final String? breakTime;
  final bool draft;

  AttendanceReviewDayState stateFor(AttendanceSubmissionKind kind) {
    switch (kind) {
      case AttendanceSubmissionKind.commute:
        final hasIn = workIn != null && workIn!.trim().isNotEmpty;
        final hasOut = workOut != null && workOut!.trim().isNotEmpty;
        if (hasIn && hasOut) return AttendanceReviewDayState.complete;
        if (hasIn || hasOut) return AttendanceReviewDayState.missing;
        return AttendanceReviewDayState.empty;
      case AttendanceSubmissionKind.restTime:
        final hasBreak = breakTime != null && breakTime!.trim().isNotEmpty;
        return hasBreak
            ? AttendanceReviewDayState.complete
            : AttendanceReviewDayState.empty;
    }
  }

  AttendanceReviewDay copyWith({
    String? workIn,
    String? workOut,
    String? breakTime,
    bool? draft,
    bool clearWorkIn = false,
    bool clearWorkOut = false,
    bool clearBreakTime = false,
  }) {
    return AttendanceReviewDay(
      date: date,
      workIn: clearWorkIn ? null : workIn ?? this.workIn,
      workOut: clearWorkOut ? null : workOut ?? this.workOut,
      breakTime: clearBreakTime ? null : breakTime ?? this.breakTime,
      draft: draft ?? this.draft,
    );
  }
}

class AttendanceSubmissionReviewSnapshot {
  const AttendanceSubmissionReviewSnapshot({
    required this.kind,
    required this.localRecords,
    required this.uploadTargets,
    required this.days,
    required this.latestLocalDay,
    required this.cutoffDay,
  });

  final AttendanceSubmissionKind kind;
  final List<AttendanceSubmissionRecord> localRecords;
  final List<AttendanceSubmissionRecord> uploadTargets;
  final List<AttendanceReviewDay> days;
  final DateTime? latestLocalDay;
  final DateTime cutoffDay;

  int get localRecordCount => localRecords.length;
  int get eligibleRecordCount => uploadTargets.length;
  int get completeDayCount => days
      .where((day) =>
          day.stateFor(kind) == AttendanceReviewDayState.complete)
      .length;
  int get missingDayCount => days
      .where((day) => day.stateFor(kind) == AttendanceReviewDayState.missing)
      .length;
}

class AttendanceSubmissionResult {
  const AttendanceSubmissionResult({
    required this.confirmed,
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    required this.deletedCount,
    this.message,
  });

  const AttendanceSubmissionResult.cancelled()
      : confirmed = false,
        successCount = 0,
        skippedCount = 0,
        failedCount = 0,
        deletedCount = 0,
        message = null;

  final bool confirmed;
  final int successCount;
  final int skippedCount;
  final int failedCount;
  final int deletedCount;
  final String? message;

  bool get succeeded => confirmed && failedCount == 0;
}
