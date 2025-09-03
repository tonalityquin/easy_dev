import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class UserStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---- collections ----
  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
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

    await FirestoreLogger().log('updateLogOutUserStatus called: $userId → $updates');
    await _getUserCollectionRef().doc(userId).update(updates);
    await FirestoreLogger().log('updateLogOutUserStatus success: $userId');
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

    await FirestoreLogger().log('updateWorkingUserStatus called: $userId → $updates');
    await _getUserCollectionRef().doc(userId).update(updates);
    await FirestoreLogger().log('updateWorkingUserStatus success: $userId');
  }

  /// 앱 로드시 currentArea 설정 (user_accounts)
  Future<void> updateLoadCurrentArea(
      String phone,
      String area,
      String currentArea,
      ) async {
    final userId = '$phone-$area';
    await FirestoreLogger().log('updateLoadCurrentArea called: $userId → $currentArea');

    await _getUserCollectionRef().doc(userId).update({'currentArea': currentArea});
    await FirestoreLogger().log('updateLoadCurrentArea success: $userId');
  }

  /// AreaPicker에서 currentArea 설정 (user_accounts)
  Future<void> areaPickerCurrentArea(
      String phone,
      String area,
      String currentArea,
      ) async {
    final userId = '$phone-$area';
    await FirestoreLogger().log('areaPickerCurrentArea called: $userId → $currentArea');

    await _getUserCollectionRef().doc(userId).update({'currentArea': currentArea});
    await FirestoreLogger().log('areaPickerCurrentArea success: $userId');
  }

  // =========================================================
  // ============= tablet_accounts (handle 기반) =============
  // =========================================================

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

    await FirestoreLogger().log('updateLogOutTabletStatus called: $tabletId → $updates');
    await _getTabletCollectionRef().doc(tabletId).update(updates);
    await FirestoreLogger().log('updateLogOutTabletStatus success: $tabletId');
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

    await FirestoreLogger().log('updateWorkingTabletStatus called: $tabletId → $updates');
    await _getTabletCollectionRef().doc(tabletId).update(updates);
    await FirestoreLogger().log('updateWorkingTabletStatus success: $tabletId');
  }

  /// 앱 로드시 currentArea 설정 (tablet_accounts)
  Future<void> updateLoadCurrentAreaTablet(
      String handle,
      String area,
      String currentArea,
      ) async {
    final tabletId = '$handle-$area';
    await FirestoreLogger().log('updateLoadCurrentAreaTablet called: $tabletId → $currentArea');

    await _getTabletCollectionRef().doc(tabletId).update({'currentArea': currentArea});
    await FirestoreLogger().log('updateLoadCurrentAreaTablet success: $tabletId');
  }

  /// AreaPicker에서 currentArea 설정 (tablet_accounts)
  Future<void> areaPickerCurrentAreaTablet(
      String handle,
      String area,
      String currentArea,
      ) async {
    final tabletId = '$handle-$area';
    await FirestoreLogger().log('areaPickerCurrentAreaTablet called: $tabletId → $currentArea');

    await _getTabletCollectionRef().doc(tabletId).update({'currentArea': currentArea});
    await FirestoreLogger().log('areaPickerCurrentAreaTablet success: $tabletId');
  }
}
