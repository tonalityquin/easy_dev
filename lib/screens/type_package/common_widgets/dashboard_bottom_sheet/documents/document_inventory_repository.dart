import 'dart:async';
import '../../../../../../states/user/user_state.dart';
import 'document_item.dart';

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
