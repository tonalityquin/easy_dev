import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'document_item.dart';

class FielderDocumentInventoryRepository {
  FielderDocumentInventoryRepository._();

  static final instance = FielderDocumentInventoryRepository._();

  Stream<List<DocumentItem>> streamForUser(UserState userState) async* {
    yield _buildInitialItems();
  }

  List<DocumentItem> _buildInitialItems() {
    final now = DateTime.now();

    return <DocumentItem>[
      // 1) 업무 인수인계
      DocumentItem(
        id: 'template-handover',
        title: '업무 인수인계 양식',
        subtitle: '업무 인수 · 인계 시 사용',
        updatedAt: now,
        type: DocumentType.handoverForm,
      ),

      // 2) 경위서 기본 양식
      DocumentItem(
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),

      // 3) 출퇴근 기록 제출
      //
      // - Simple 모드와 동일하게 id 를 'template-commute-record' 로 통일
      // - type 은 statementForm 으로 두고, id 로 세부 종류를 구분
      DocumentItem(
        id: 'template-commute-record',
        title: '출퇴근 기록 제출',
        subtitle: '지각 · 조퇴 · 결근 등 출퇴근 관련 사유 보고',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),

      // 4) 휴게시간 기록 제출
      //
      // - Simple 모드와 동일하게 id 를 'template-resttime-record' 로 통일
      // - type 은 statementForm 으로 두고, id 로 세부 종류를 구분
      DocumentItem(
        id: 'template-resttime-record',
        title: '휴게시간 기록 제출',
        subtitle: '휴게시간 미사용 · 지연 · 초과 사용 등 휴게시간 관련 보고',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),

      // 5) 연차(결근) 지원 신청서
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
