import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/dev_package/debug_package/debug_firestore_logger.dart';

class UserStatus {
  final String name;
  final bool isWorking;
  const UserStatus({required this.name, required this.isWorking});
}

class AreaUserRepository {
  AreaUserRepository({
    FirebaseFirestore? firestore,
    Duration? ttl,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _ttl = ttl ?? const Duration(minutes: 5);

  final FirebaseFirestore _firestore;
  final Duration _ttl;

  final Map<String, _CacheEntry> _cache = {};

  Future<List<UserStatus>> getUsersForArea(String area) async {
    final now = DateTime.now();
    final hit = _cache[area];
    if (hit != null && now.isBefore(hit.expiresAt)) {
      return hit.data;
    }

    try {
      final snapshot = await _firestore
          .collection('user_accounts')
          .where('currentArea', isEqualTo: area)
          .get();

      final result = snapshot.docs.map((doc) {
        final data = doc.data();
        return UserStatus(
          name: (data['name'] as String?) ?? '이름 없음',
          isWorking: data['isWorking'] == true,
        );
      }).toList();

      _cache[area] = _CacheEntry(result, now.add(_ttl));
      return result;
    } on FirebaseException catch (e, st) {
      // 🔴 파이어스토어 실패만 로깅
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.listByCurrentArea',
          'collection': 'user_accounts',
          'filters': {'currentArea': area},
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['users', 'listByCurrentArea', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}

class _CacheEntry {
  _CacheEntry(this.data, this.expiresAt);
  final List<UserStatus> data;
  final DateTime expiresAt;
}
