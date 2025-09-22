// lib/repositories/user_repo_services/user_status_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart';

class UserStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---- collections ----
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

  // ---- safe update helper (update → if NOT_FOUND then set(merge)) ----
  Future<void> _safeUpdate(
      CollectionReference<Map<String, dynamic>> col,
      String docId,
      Map<String, dynamic> updates, {
        required String opName,
      }) async {
    final docRef = col.doc(docId);
    final area = _inferAreaFromHyphenId(docId);

    try {
      await docRef.update(updates);

      // write 1
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'UserStatusService.$opName.update',
      );
    } on FirebaseException catch (e, st) {
      if (e.code == 'not-found') {
        try {
          await docRef.set(updates, SetOptions(merge: true));

          // write 1 (upsert)
          await UsageReporter.instance.report(
            area: area,
            action: 'write',
            n: 1,
            source: 'UserStatusService.$opName.upsert',
          );
        } on FirebaseException catch (e2, st2) {
          try {
            await DebugFirestoreLogger().log({
              'op': 'userStatus.$opName.upsert',
              'collectionPath': col.path,
              'docId': docId,
              'updateKeys': updates.keys.take(30).toList(),
              'updateLen': updates.length,
              'error': {
                'type': e2.runtimeType.toString(),
                'code': e2.code,
                'message': e2.toString()
              },
              'stack': st2.toString(),
              'tags': ['userStatus', opName, 'upsert', 'error'],
            }, level: 'error');
          } catch (_) {}
          rethrow;
        }
      } else {
        try {
          await DebugFirestoreLogger().log({
            'op': 'userStatus.$opName.update',
            'collectionPath': col.path,
            'docId': docId,
            'updateKeys': updates.keys.take(30).toList(),
            'updateLen': updates.length,
            'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['userStatus', opName, 'update', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'userStatus.$opName.unknown',
          'collectionPath': col.path,
          'docId': docId,
          'updateKeys': updates.keys.take(30).toList(),
          'updateLen': updates.length,
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['userStatus', opName, 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  // =============== user_accounts (phone 기반) ===============
  Future<void> updateLogOutUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final userId = '$phone-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      updates,
      opName: 'updateLogOutUserStatus',
    );
  }

  Future<void> updateWorkingUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final userId = '$phone-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      updates,
      opName: 'updateWorkingUserStatus',
    );
  }

  Future<void> updateLoadCurrentArea(
      String phone,
      String area,
      String currentArea,
      ) async {
    final userId = '$phone-$area';
    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      {'currentArea': currentArea},
      opName: 'updateLoadCurrentArea',
    );
  }

  Future<void> areaPickerCurrentArea(
      String phone,
      String area,
      String currentArea,
      ) async {
    final userId = '$phone-$area';
    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      {'currentArea': currentArea},
      opName: 'areaPickerCurrentArea',
    );
  }

  // ============= tablet_accounts (handle 기반) =============
  Future<void> updateLogOutTabletStatus(
      String handle,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final tabletId = '$handle-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      updates,
      opName: 'updateLogOutTabletStatus',
    );
  }

  Future<void> updateWorkingTabletStatus(
      String handle,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final tabletId = '$handle-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      updates,
      opName: 'updateWorkingTabletStatus',
    );
  }

  Future<void> updateLoadCurrentAreaTablet(
      String handle,
      String area,
      String currentArea,
      ) async {
    final tabletId = '$handle-$area';
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      {'currentArea': currentArea},
      opName: 'updateLoadCurrentAreaTablet',
    );
  }

  Future<void> areaPickerCurrentAreaTablet(
      String handle,
      String area,
      String currentArea,
      ) async {
    final tabletId = '$handle-$area';
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      {'currentArea': currentArea},
      opName: 'areaPickerCurrentAreaTablet',
    );
  }
}
