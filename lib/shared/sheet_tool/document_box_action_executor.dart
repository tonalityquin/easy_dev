import 'package:flutter/material.dart';
import '../../../app/utils/block_dialog/break_duration_blocking_dialog.dart';
import '../../../app/utils/block_dialog/work_end_duration_blocking_dialog.dart';
import '../document/backup/backup_form_page.dart';
import '../document/user_statement/user_statement_form_page.dart';
import '../document/work_end_report/dashboard_end_report_form_page.dart';
import '../document/work_start_report/dashboard_start_report_form_page.dart';
import 'document_box_action.dart';
import 'fielder_document_box_sheet.dart';
import 'leader_document_box_sheet.dart';

Future<void> executeDocumentBoxAction(
  BuildContext context,
  DocumentBoxAction action,
) async {
  switch (action) {
    case DocumentBoxAction.openUserStatementForm:
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const UserStatementFormPage(),
          fullscreenDialog: true,
        ),
      );
      return;
    case DocumentBoxAction.openWorkEndReportForm:
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const DashboardEndReportFormPage(),
          fullscreenDialog: true,
        ),
      );
      return;
    case DocumentBoxAction.openWorkStartReportForm:
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const DashboardStartReportFormPage(),
          fullscreenDialog: true,
        ),
      );
      return;
    case DocumentBoxAction.openBackupForm:
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const BackupFormPage(),
          fullscreenDialog: true,
        ),
      );
      return;
    case DocumentBoxAction.submitLeaderCommuteRecords:
      final proceed = await showWorkEndDurationBlockingDialog(
        context,
        message: '단말기에 저장된 출퇴근 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
        duration: const Duration(seconds: 5),
      );
      if (!proceed) return;
      await submitLeaderCommuteRecordsFromSqlite(context);
      return;
    case DocumentBoxAction.submitLeaderRestTimeRecords:
      final proceed = await showBreakDurationBlockingDialog(
        context,
        message: '단말기에 저장된 휴게시간 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
        duration: const Duration(seconds: 5),
      );
      if (!proceed) return;
      await submitLeaderRestTimeRecordsFromSqlite(context);
      return;
    case DocumentBoxAction.submitFielderCommuteRecords:
      final proceed = await showWorkEndDurationBlockingDialog(
        context,
        message: '단말기에 저장된 출퇴근 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
        duration: const Duration(seconds: 5),
      );
      if (!proceed) return;
      await submitFielderCommuteRecordsFromSqlite(context);
      return;
    case DocumentBoxAction.submitFielderRestTimeRecords:
      final proceed = await showBreakDurationBlockingDialog(
        context,
        message: '단말기에 저장된 휴게시간 기록을\n서버에 제출합니다.\n\n제출을 원치 않으면 아래 [취소] 버튼을 눌러 주세요.',
        duration: const Duration(seconds: 5),
      );
      if (!proceed) return;
      await submitFielderRestTimeRecordsFromSqlite(context);
      return;
  }
}
