import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/community_package/debug_package/debug_firestore_logger.dart';

class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final String targetId = ids.first;
    final docRef = _firestore.collection('bill').doc(targetId);

    try {
      await docRef.delete();
    } catch (e, st) {
      // --- 실패 시 Firestore 로거에만 error 레벨 기록 ---
      try {
        final payload = {
          'op': 'bill.delete',
          'docPath': docRef.path,
          'docId': targetId,
          'args': {
            'idsLen': ids.length,
            'idsSample': ids.take(5).toList(),
          },
          'error': {
            'type': e.runtimeType.toString(),
            if (e is FirebaseException) 'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['bill', 'delete', 'error'],
        };

        await DebugFirestoreLogger().log(payload, level: 'error');
      } catch (_) {
        // 로깅 실패는 무시하고 원래 예외 흐름 유지
      }

      rethrow;
    }
  }
}
