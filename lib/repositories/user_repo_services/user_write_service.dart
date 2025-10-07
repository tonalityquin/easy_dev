// lib/repositories/user_repo_services/user_write_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easydev/models/tablet_model.dart';
import '../../models/user_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart';

class UserWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  String _inferAreaFromHyphenId(String id) {
    final idx = id.lastIndexOf('-');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }

  /// 사용자 추가
  Future<void> addUserCard(UserModel user) async {
    final docRef = _getUserCollectionRef().doc(user.id);
    try {
      await docRef.set(user.toMap());

      // write 1
      /*await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(user.id),
        action: 'write',
        n: 1,
        source: 'UserWriteService.addUserCard',
      );*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.add',
          'collection': 'user_accounts',
          'docPath': docRef.path,
          'docId': user.id,
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'add', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.add.unknown',
          'collection': 'user_accounts',
          'docPath': docRef.path,
          'docId': user.id,
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'add', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> addTabletCard(TabletModel tablet) async {
    final docRef = _getTabletCollectionRef().doc(tablet.id);
    try {
      await docRef.set(tablet.toMap());

      await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(tablet.id),
        action: 'write',
        n: 1,
        source: 'UserWriteService.addTabletCard',
      );
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.add',
          'collection': 'tablet_accounts',
          'docPath': docRef.path,
          'docId': tablet.id,
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'add', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.add.unknown',
          'collection': 'tablet_accounts',
          'docPath': docRef.path,
          'docId': tablet.id,
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'add', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// 사용자 전체 업데이트
  Future<void> updateUser(UserModel user) async {
    final docRef = _getUserCollectionRef().doc(user.id);
    try {
      await docRef.set(user.toMap());

      /*await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(user.id),
        action: 'write',
        n: 1,
        source: 'UserWriteService.updateUser',
      );*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.update',
          'collection': 'user_accounts',
          'docPath': docRef.path,
          'docId': user.id,
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'users.update.unknown',
          'collection': 'user_accounts',
          'docPath': docRef.path,
          'docId': user.id,
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> updateTablet(TabletModel tablet) async {
    final docRef = _getTabletCollectionRef().doc(tablet.id);
    try {
      await docRef.set(tablet.toMap());

      await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(tablet.id),
        action: 'write',
        n: 1,
        source: 'UserWriteService.updateTablet',
      );
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.update',
          'collection': 'tablet_accounts',
          'docPath': docRef.path,
          'docId': tablet.id,
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'tablets.update.unknown',
          'collection': 'tablet_accounts',
          'docPath': docRef.path,
          'docId': tablet.id,
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['tablets', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// 사용자 삭제 (ID 목록 기준)
  Future<void> deleteUsers(List<String> ids) async {
    // area별 버킷으로 delete 집계
    final buckets = <String, int>{};

    for (final id in ids) {
      final docRef = _getUserCollectionRef().doc(id);
      try {
        await docRef.delete();

        final area = _inferAreaFromHyphenId(id);
        buckets.update(area, (v) => v + 1, ifAbsent: () => 1);
      } on FirebaseException catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'users.delete',
            'collection': 'user_accounts',
            'docPath': docRef.path,
            'docId': id,
            'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['users', 'delete', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      } catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'users.delete.unknown',
            'collection': 'user_accounts',
            'docPath': docRef.path,
            'docId': id,
            'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['users', 'delete', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    }

    // delete 집계 보고
    // ignore: unused_local_variable
    for (final e in buckets.entries) {
      /*await UsageReporter.instance.report(
        area: e.key,
        action: 'delete',
        n: e.value,
        source: 'UserWriteService.deleteUsers',
      );*/
    }
  }

  Future<void> deleteTablets(List<String> ids) async {
    final buckets = <String, int>{};

    for (final id in ids) {
      final docRef = _getTabletCollectionRef().doc(id);
      try {
        await docRef.delete();

        final area = _inferAreaFromHyphenId(id);
        buckets.update(area, (v) => v + 1, ifAbsent: () => 1);
      } on FirebaseException catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'tablets.delete',
            'collection': 'tablet_accounts',
            'docPath': docRef.path,
            'docId': id,
            'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['tablets', 'delete', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      } catch (e, st) {
        try {
          await DebugFirestoreLogger().log({
            'op': 'tablets.delete.unknown',
            'collection': 'tablet_accounts',
            'docPath': docRef.path,
            'docId': id,
            'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['tablets', 'delete', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    }

    for (final e in buckets.entries) {
      await UsageReporter.instance.report(
        area: e.key,
        action: 'delete',
        n: e.value,
        source: 'UserWriteService.deleteTablets',
      );
    }
  }
}
