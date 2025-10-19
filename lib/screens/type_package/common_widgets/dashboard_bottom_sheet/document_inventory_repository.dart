// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/document_inventory_repository.dart
import 'dart:async';

import '../../../../../../states/user/user_state.dart';
import 'widgets/document_item.dart';

/// 사용자 전용 인벤토리 스트림을 제공하는 Repository
/// - 현재는 샘플 스트림(한 번 emit)으로 구성
/// - 실제 연동 시, Firestore/REST/SQLite 등으로 대체
class DocumentInventoryRepository {
  DocumentInventoryRepository._();
  static final instance = DocumentInventoryRepository._();

  Stream<List<DocumentItem>> streamForUser(UserState userState) async* {
    final now = DateTime.now();
    yield <DocumentItem>[
      DocumentItem(
        id: 'doc-001',
        title: '근로계약서',
        subtitle: '내 역할: ${userState.role}',
        updatedAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
      DocumentItem(
        id: 'doc-002',
        title: '보안 서약서',
        subtitle: '전자서명 필요',
        updatedAt: now.subtract(const Duration(days: 7, hours: 2)),
      ),
      DocumentItem(
        id: 'doc-003',
        title: '개인정보 처리 동의서',
        subtitle: '열람 전용',
        updatedAt: now.subtract(const Duration(days: 30)),
      ),

      // ✅ 신규: 경위서 양식 (선택 시 StatementFormPage 진입)
      DocumentItem(
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),
    ];
  }
}
