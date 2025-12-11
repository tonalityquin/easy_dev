import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'simple_document_item.dart';

class SimpleDocumentInventoryRepository {
  SimpleDocumentInventoryRepository._();

  static final instance = SimpleDocumentInventoryRepository._();

  Stream<List<SimpleDocumentItem>> streamForUser(UserState userState) async* {
    yield _buildInitialItems();
  }

  List<SimpleDocumentItem> _buildInitialItems() {
    final now = DateTime.now();

    // 🔹 여기서 실제로 사용할 문서만 노출합니다.
    //  - 업무 시작/퇴근/업무 종료/인수인계 양식은 제거
    //  - 경위서 / 출퇴근 기록 / 휴게시간 기록 / 연차(결근) 신청서만 유지
    //
    //  ⚠️ 라우팅 레벨에서 각 id(template-*)에 따라
    //     적절한 페이지(UserStatementFormPage(kind: ...))로
    //     분기해 주어야 합니다.
    return <SimpleDocumentItem>[
      // 1) 경위서
      SimpleDocumentItem(
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: SimpleDocumentType.statementForm,
      ),

      // 2) 출퇴근 기록 제출
      SimpleDocumentItem(
        id: 'template-commute-record',
        title: '출퇴근 기록 제출',
        subtitle: '지각 · 조퇴 · 결근 등 출퇴근 관련 사유 보고',
        updatedAt: now,
        // 기존 경위서와 동일한 statementForm 타입을 사용하고,
        // id로 세부 종류를 구분합니다.
        type: SimpleDocumentType.statementForm,
      ),

      // 3) 휴게시간 기록 제출
      SimpleDocumentItem(
        id: 'template-resttime-record',
        title: '휴게시간 기록 제출',
        subtitle: '휴게시간 미사용 · 지연 · 초과 사용 등 휴게시간 관련 보고',
        updatedAt: now,
        type: SimpleDocumentType.statementForm,
      ),

      // 4) 연차(결근) 지원 신청서
      SimpleDocumentItem(
        id: 'template-annual-leave-application',
        title: '연차(결근) 지원 신청서',
        subtitle: '연차/결근 사유 및 일정 정리',
        updatedAt: now,
        type: SimpleDocumentType.generic,
      ),
    ];
  }
}
