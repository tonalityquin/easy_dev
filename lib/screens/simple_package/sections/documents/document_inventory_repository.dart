// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/document_inventory_repository.dart
import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'document_item.dart';

class DocumentInventoryRepository {
  DocumentInventoryRepository._();

  static final instance = DocumentInventoryRepository._();

  Stream<List<DocumentItem>> streamForUser(UserState userState) async* {
    // TODO: userState 를 활용한 사용자별/서버 연동 로직은 이후 확장
    yield _buildInitialItems();
  }

  List<DocumentItem> _buildInitialItems() {
    final now = DateTime.now();

    // 🔹 여기서 실제로 사용할 문서만 노출합니다.
    //  - 업무 시작/퇴근/업무 종료/인수인계 양식은 제거
    return <DocumentItem>[
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
