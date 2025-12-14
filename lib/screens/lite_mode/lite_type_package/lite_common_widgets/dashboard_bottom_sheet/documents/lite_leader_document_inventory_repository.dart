// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/document_inventory_repository.dart
import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'lite_document_item.dart';

class LeaderDocumentInventoryRepository {
  LeaderDocumentInventoryRepository._();

  static final instance = LeaderDocumentInventoryRepository._();

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
      // 2) 출퇴근 기록 제출
      DocumentItem(
        id: 'template-commute-record',
        title: '출퇴근 기록 제출',
        subtitle: '지각 · 조퇴 · 결근 등 출퇴근 관련 사유 보고',
        updatedAt: now,
        // 기존 경위서와 동일한 statementForm 타입을 사용하고,
        // id로 세부 종류를 구분합니다.
        type: DocumentType.statementForm,
      ),

      // 3) 휴게시간 기록 제출
      DocumentItem(
        id: 'template-resttime-record',
        title: '휴게시간 기록 제출',
        subtitle: '휴게시간 미사용 · 지연 · 초과 사용 등 휴게시간 관련 보고',
        updatedAt: now,
        type: DocumentType.statementForm,
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
    ];
  }
}
