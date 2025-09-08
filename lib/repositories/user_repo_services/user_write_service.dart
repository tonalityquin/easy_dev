import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easydev/models/tablet_model.dart';
import '../../models/user_model.dart';

class UserWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  /// 사용자 추가
  Future<void> addUserCard(UserModel user) async {
    await _getUserCollectionRef().doc(user.id).set(user.toMap());
  }

  Future<void> addTabletCard(TabletModel tablet) async {
    await _getTabletCollectionRef().doc(tablet.id).set(tablet.toMap());
  }

  /// 사용자 전체 업데이트
  Future<void> updateUser(UserModel user) async {
    await _getUserCollectionRef().doc(user.id).set(user.toMap());
  }

  Future<void> updateTablet(TabletModel tablet) async {
    await _getTabletCollectionRef().doc(tablet.id).set(tablet.toMap());
  }

  /// 사용자 삭제 (ID 목록 기준)
  Future<void> deleteUsers(List<String> ids) async {
    for (final id in ids) {
      await _getUserCollectionRef().doc(id).delete();
    }
  }

  Future<void> deleteTablets(List<String> ids) async {
    for (final id in ids) {
      await _getTabletCollectionRef().doc(id).delete();
    }
  }
}
