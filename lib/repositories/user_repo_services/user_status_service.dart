import 'package:cloud_firestore/cloud_firestore.dart';

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
    try {
      await col.doc(docId).update(updates);
    } on FirebaseException catch (e) {
      // 문서가 없으면 set(merge)로 업서트 처리
      if (e.code == 'not-found') {
        await col.doc(docId).set(updates, SetOptions(merge: true));
      } else {
        rethrow;
      }
    } catch (e) {
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
