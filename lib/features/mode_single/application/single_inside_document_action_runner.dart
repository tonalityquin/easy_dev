import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/area_context_debug_trace.dart';
import '../../../app/utils/block_dialog/break_duration_blocking_dialog.dart';
import '../../account/applications/user_state.dart';
import '../../commute/domain/repositories/commute_log_repository.dart';
import '../../dev/application/area_state.dart';
import 'single_attendance_submission_summary_service.dart';
import 'single_inside_diagnostics.dart';

enum SingleInsideDocumentAction {
  commuteSubmit,
  restTimeSubmit,
}

class SingleInsideDocumentActionRunner {
  static Future<void> run(
    BuildContext context,
    SingleInsideDocumentAction action,
  ) async {
    SingleInsideDiagnostics.log(
      'document',
      'action_start action=${action.name}',
    );
    try {
      switch (action) {
        case SingleInsideDocumentAction.commuteSubmit:
          await _runCommuteSubmit(context);
          break;
        case SingleInsideDocumentAction.restTimeSubmit:
          await _runRestTimeSubmit(context);
          break;
      }
      SingleInsideDiagnostics.log(
        'document',
        'action_complete action=${action.name}',
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'document',
        'action_failure action=${action.name} error=$error stack=$stackTrace',
      );
      rethrow;
    }
  }

  static Future<void> _runCommuteSubmit(BuildContext context) async {
    final proceed = await showBreakDurationBlockingDialog(
      context,
      message:
          '단말기에 저장된 출퇴근 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
      duration: const Duration(seconds: 5),
    );
    SingleInsideDiagnostics.log(
      'document',
      'commute_submit_confirmed=$proceed',
    );
    if (!proceed || !context.mounted) return;
    await _submitLocalAttendanceRecordsToFirestore(
      context,
      statuses: const <String>['출근', '퇴근'],
      validationFailMessage: '출퇴근 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.\n'
          '관리자에게 계정 및 근무지 설정을 확인해 달라고 요청해 주세요.',
      noLocalRecordsMessage: '제출할 출퇴근 기록이 없습니다.',
      noUploadTargetsMessage: '업로드할 출퇴근 기록이 없습니다. (가장 최근 날짜 기록은 제외합니다.)',
      resultPrefix: '출퇴근 기록 제출 완료',
      debugTag: 'SingleDocumentActionRunner/CommuteSubmit',
    );
  }

  static Future<void> _runRestTimeSubmit(BuildContext context) async {
    final proceed = await showBreakDurationBlockingDialog(
      context,
      message:
          '단말기에 저장된 휴게시간 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
      duration: const Duration(seconds: 5),
    );
    SingleInsideDiagnostics.log(
      'document',
      'rest_submit_confirmed=$proceed',
    );
    if (!proceed || !context.mounted) return;
    await _submitLocalAttendanceRecordsToFirestore(
      context,
      statuses: const <String>['휴게'],
      validationFailMessage: '휴게시간 기록 제출 실패: 사용자/근무지 정보가 비어 있습니다.\n'
          '관리자에게 계정 및 근무지 설정을 확인해 달라고 요청해 주세요.',
      noLocalRecordsMessage: '제출할 휴게시간 기록이 없습니다.',
      noUploadTargetsMessage: '업로드할 휴게시간 기록이 없습니다. (가장 최근 날짜 기록은 제외합니다.)',
      resultPrefix: '휴게시간 기록 제출 완료',
      debugTag: 'SingleDocumentActionRunner/BreakSubmit',
    );
  }

  static Future<void> _submitLocalAttendanceRecordsToFirestore(
    BuildContext context, {
    required List<String> statuses,
    required String validationFailMessage,
    required String noLocalRecordsMessage,
    required String noUploadTargetsMessage,
    required String resultPrefix,
    required String debugTag,
  }) async {
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final userId = (userState.session?.id ?? '').trim();
    final userName = userState.name.trim();
    final selectedArea = (userState.session?.selectedArea ?? '').trim();
    final area = userState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    AreaContextDebugTrace.record(
      debugTag,
      'attendance_upload_started',
      fields: <String, Object?>{
        'selectedArea': selectedArea,
        'currentArea': area,
        'currentDivision': division,
        'statuses': statuses.join(','),
      },
    );

    if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
      debugPrint(validationFailMessage);
      SingleInsideDiagnostics.log(
        'document',
        'validation_failure tag=$debugTag userIdPresent=${userId.isNotEmpty} userNamePresent=${userName.isNotEmpty} areaPresent=${area.isNotEmpty} divisionPresent=${division.isNotEmpty}',
      );
      return;
    }

    try {
      final summary = await SingleAttendanceSubmissionSummaryService.load(
        statuses: statuses,
      );
      SingleInsideDiagnostics.log(
        'document',
        'local_records_loaded tag=$debugTag count=${summary.totalLocalCount} eligible=${summary.eligibleCount} statuses=${statuses.join(',')}',
      );

      if (summary.totalLocalCount == 0) {
        debugPrint(noLocalRecordsMessage);
        SingleInsideDiagnostics.log(
          'document',
          'no_local_records tag=$debugTag',
        );
        return;
      }

      final dateFormatter = DateFormat('yyyy-MM-dd');
      final timeFormatter = DateFormat('HH:mm');
      final latestDay = summary.latestDay;
      final cutoffDay = summary.cutoffDay;
      final latestDayStr = latestDay == null ? '-' : dateFormatter.format(latestDay);
      final cutoffDayStr = cutoffDay == null ? '-' : dateFormatter.format(cutoffDay);

      if (summary.uploadTargets.isEmpty) {
        final message = '$noUploadTargetsMessage\n'
            '가장 최근 날짜: $latestDayStr\n'
            '업로드 범위: $cutoffDayStr(포함) 이전';
        debugPrint(message);
        SingleInsideDiagnostics.log(
          'document',
          'no_upload_targets tag=$debugTag latest=$latestDayStr cutoff=$cutoffDayStr',
        );
        return;
      }

      final repo = CommuteLogRepository();
      var successCount = 0;
      var skippedCount = 0;
      var failedCount = 0;
      var deletedCount = 0;

      for (final record in summary.uploadTargets) {
        final status = record.status;
        final eventDateTime = record.dateTime;
        final dateStr = dateFormatter.format(eventDateTime);
        final recordedTime = timeFormatter.format(eventDateTime);
        final alreadyExists = await repo.hasLogForDate(
          status: status,
          userId: userId,
          dateStr: dateStr,
        );

        if (alreadyExists) {
          skippedCount++;
          deletedCount +=
              await SingleAttendanceSubmissionSummaryService.deleteRecord(record);
          continue;
        }

        await repo.addLog(
          status: status,
          userId: userId,
          userName: userName,
          area: area,
          division: division,
          dateStr: dateStr,
          recordedTime: recordedTime,
          dateTime: eventDateTime,
        );

        final nowExists = await repo.hasLogForDate(
          status: status,
          userId: userId,
          dateStr: dateStr,
        );

        if (nowExists) {
          successCount++;
          deletedCount +=
              await SingleAttendanceSubmissionSummaryService.deleteRecord(record);
        } else {
          failedCount++;
        }
      }

      final result = '$resultPrefix: '
          '$successCount건 업로드, '
          '중복 $skippedCount건, '
          '실패 $failedCount건, '
          '로컬 삭제 $deletedCount건.\n'
          '(최신일 $latestDayStr 제외, $cutoffDayStr까지 업로드)';
      debugPrint(result);
      SingleInsideDiagnostics.log(
        'document',
        'submit_result tag=$debugTag success=$successCount skipped=$skippedCount failed=$failedCount deleted=$deletedCount latest=$latestDayStr cutoff=$cutoffDayStr',
      );
      AreaContextDebugTrace.record(
        debugTag,
        'attendance_upload_completed',
        fields: <String, Object?>{
          'selectedArea': selectedArea,
          'currentArea': area,
          'success': successCount,
          'skipped': skippedCount,
          'failed': failedCount,
        },
      );
    } catch (error, stackTrace) {
      debugPrint('[$debugTag] 제출 중 오류: $error');
      debugPrint('stack: $stackTrace');
      debugPrint(
        '기록 제출 중 오류가 발생했습니다.\n네트워크 또는 Firebase 설정을 확인해 주세요.',
      );
      SingleInsideDiagnostics.log(
        'document',
        'submit_failure tag=$debugTag error=$error stack=$stackTrace',
      );
      AreaContextDebugTrace.record(
        debugTag,
        'attendance_upload_failed',
        fields: <String, Object?>{
          'selectedArea': selectedArea,
          'currentArea': area,
          'error': '$error',
        },
      );
    }
  }
}
