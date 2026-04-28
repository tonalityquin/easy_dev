import 'dart:async';
import '../../../features/account/applications/user_state.dart';
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

      
      DocumentItem(
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),

      
      
      
      
      DocumentItem(
        id: 'template-commute-record',
        title: '출퇴근 기록 제출',
        subtitle: '지각 · 조퇴 · 결근 등 출퇴근 관련 사유 보고',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),

      
      
      
      
      DocumentItem(
        id: 'template-resttime-record',
        title: '휴게시간 기록 제출',
        subtitle: '휴게시간 미사용 · 지연 · 초과 사용 등 휴게시간 관련 보고',
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
