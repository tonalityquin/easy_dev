import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/stub_package/debug_package/debug_firestore_logger.dart';

class UserStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---- collections ----
  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  // ---- safe update helper (update → if NOT_FOUND then set(merge)) ----
  Future<void> _safeUpdate(
      CollectionReference<Map<String, dynamic>> col,
      String docId,
      Map<String, dynamic> updates, {
        String opName = '',
      }) async {
    final docRef = col.doc(docId);

    try {
      await docRef.update(updates);
    } on FirebaseException catch (e, st) {
      if (e.code == 'not-found') {
        // 없으면 upsert
        try {
          await docRef.set(updates, SetOptions(merge: true));
        } on FirebaseException catch (e2, st2) {
          // Firestore 실패만 로깅
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
                'message': e2.toString(),
              },
              'stack': st2.toString(),
              'tags': ['userStatus', opName, 'upsert', 'error'],
            }, level: 'error');
          } catch (_) {}
          rethrow;
        }
      } else {
        // update 단계 Firestore 실패 로깅
        try {
          await DebugFirestoreLogger().log({
            'op': 'userStatus.$opName.update',
            'collectionPath': col.path,
            'docId': docId,
            'updateKeys': updates.keys.take(30).toList(),
            'updateLen': updates.length,
            'error': {
              'type': e.runtimeType.toString(),
              'code': e.code,
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['userStatus', opName, 'update', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    } catch (e, st) {
      // 기타 예외 로깅
      try {
        await DebugFirestoreLogger().log({
          'op': 'userStatus.$opName.unknown',
          'collectionPath': col.path,
          'docId': docId,
          'updateKeys': updates.keys.take(30).toList(),
          'updateLen': updates.length,
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['userStatus', opName, 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  // =========================================================
  // =============== user_accounts (phone 기반) ===============
  // =========================================================

  /// 로그아웃 시 사용자 상태 업데이트 (user_accounts)
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

  /// 근무 상태 전용 업데이트 (user_accounts)
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

  /// 앱 로드시 currentArea 설정 (user_accounts)
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

  /// AreaPicker에서 currentArea 설정 (user_accounts)
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

  // =========================================================
  // ============= tablet_accounts (handle 기반) =============
  // =========================================================
  // ⚠️ tablet_accounts 문서 ID 규칙:
  //    `$handle-$areaName(한글 지역명 A안)`

  /// 로그아웃 시 태블릿 계정 상태 업데이트 (tablet_accounts)
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

  /// 근무 상태 전용 업데이트 (tablet_accounts)
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

  /// 앱 로드시 currentArea 설정 (tablet_accounts)
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

  /// AreaPicker에서 currentArea 설정 (tablet_accounts)
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
