import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class UserStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  /// 앱 로드 시 사용자 상태 업데이트
  Future<void> updateLoadUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final userId = '$phone-$area';
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await FirestoreLogger().log('updateLoadUserStatus called: $userId → $updates');
    await _getUserCollectionRef().doc(userId).update(updates);
    await FirestoreLogger().log('updateLoadUserStatus success: $userId');
  }

  /// 로그아웃 시 사용자 상태 업데이트
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

  /// 근무 상태 전용 업데이트
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

  /// 앱 로드시 currentArea 설정
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

  /// AreaPicker에서 currentArea 설정
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
}
