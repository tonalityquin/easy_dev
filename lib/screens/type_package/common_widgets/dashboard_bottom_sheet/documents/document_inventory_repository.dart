// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/document_inventory_repository.dart
import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'document_item.dart';

class DocumentInventoryRepository {
  DocumentInventoryRepository._();

  static final instance = DocumentInventoryRepository._();

  Stream<List<DocumentItem>> streamForUser(UserState userState) async* {
    yield _buildInitialItems();
  }

  List<DocumentItem> _buildInitialItems() {
    final now = DateTime.now();

    return <DocumentItem>[
      DocumentItem(
        id: 'template-work-start-report',
        title: '업무 시작 보고 양식',
        subtitle: '업무 시작 시 보고 내용 정리',
        updatedAt: now,
        type: DocumentType.workStartReportForm,
      ),
      DocumentItem(
        id: 'template-end-work-report',
        title: '업무 종료 보고서',
        subtitle: '차량 집계 및 서버 보고',
        updatedAt: now,
        type: DocumentType.workEndReportForm,
      ),
      DocumentItem(
        id: 'template-handover',
        title: '업무 인수인계 양식',
        subtitle: '업무 인수 · 인계 시 사용',
        updatedAt: now,
        type: DocumentType.handoverForm,
      ),
      DocumentItem(
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),
      DocumentItem(
        id: 'template-annual-leave-application',
        title: '연차(결근) 지원 신청서',
        subtitle: '연차/결근 사유 및 일정 정리',
        updatedAt: now,
        type: DocumentType.generic,
      ),
      DocumentItem(
        id: 'template-resignation-letter',
        title: '사직서',
        subtitle: '퇴사 사유 및 일자 작성',
        updatedAt: now,
        type: DocumentType.generic,
      ),
    ];
  }
}
