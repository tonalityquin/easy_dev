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
        id: 'template-statement',
        title: '경위서 양식',
        subtitle: '작성 및 메일 제출',
        updatedAt: now,
        type: DocumentType.statementForm,
      ),
    ];
  }
}
