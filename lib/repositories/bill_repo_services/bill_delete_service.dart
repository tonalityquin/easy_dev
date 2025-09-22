import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart';

class BillDeleteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ⚠️ 현재는 ids 배열의 첫 번째 문서만 삭제합니다(안전모드).
  /// 여러 개를 한 번에 지우려면 for 문으로 확장하세요.
  Future<void> deleteBill(List<String> ids) async {
    if (ids.isEmpty) return;

    final String targetId = ids.first;
    final docRef = _firestore.collection('bill').doc(targetId);

    try {
      // ── 정확한 area 집계를 위해 프리페치 1회 ──────────────
      final snap = await docRef.get();
      final area = (snap.data()?['area'] as String?) ?? 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'BillDeleteService.deleteBill.prefetch',
      );

      // ── 실제 삭제 ───────────────────────────────────────
      await docRef.delete();

      await UsageReporter.instance.report(
        area: area,
        action: 'delete',
        n: 1,
        source: 'BillDeleteService.deleteBill.delete',
      );
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
      } catch (_) {}
      rethrow;
    }
  }
}
