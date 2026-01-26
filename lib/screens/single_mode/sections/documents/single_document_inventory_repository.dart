import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'single_document_item.dart';

class SingleDocumentInventoryRepository {
  SingleDocumentInventoryRepository._();

  static final instance = SingleDocumentInventoryRepository._();

  Stream<List<SingleDocumentItem>> streamForUser(UserState userState) async* {
    yield _buildInitialItems();
  }

  List<SingleDocumentItem> _buildInitialItems() {
    final now = DateTime.now();

    return <SingleDocumentItem>[
      SingleDocumentItem(
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: SingleDocumentType.statementForm,
      ),
      SingleDocumentItem(
        id: 'template-commute-record',
        title: '출퇴근 기록 제출',
        subtitle: '지각 · 조퇴 · 결근 등 출퇴근 관련 사유 보고',
        updatedAt: now,
        type: SingleDocumentType.statementForm,
      ),
      SingleDocumentItem(
        id: 'template-resttime-record',
        title: '휴게시간 기록 제출',
        subtitle: '휴게시간 미사용 · 지연 · 초과 사용 등 휴게시간 관련 보고',
        updatedAt: now,
        type: SingleDocumentType.statementForm,
      ),
      SingleDocumentItem(
        id: 'template-annual-leave-application',
        title: '연차(결근) 지원 신청서',
        subtitle: '연차/결근 사유 및 일정 정리',
        updatedAt: now,
        type: SingleDocumentType.generic,
      ),
    ];
  }
}
