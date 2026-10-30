import '../../../../app/firebase_activity/firebase_activity_monitor.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';


class UserStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  
  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  

  Future<void> _safeUpdate(
      CollectionReference<Map<String, dynamic>> col,
      String docId,
      Map<String, dynamic> updates, {
        required String opName,
        bool createIfMissing = true,
      }) async {
    final normalizedId = docId.trim();
    if (normalizedId.isEmpty || normalizedId.contains('/')) {
      throw ArgumentError.value(docId, 'docId');
    }
    final docRef = col.doc(normalizedId);
    debugPrint('[USER-STATUS] operation=$opName document=${docRef.path} action=update fields=${updates.keys.join(',')}');

    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.update, () => docRef.update(updates), source: 'user_status_service.update');
      debugPrint('[USER-STATUS] operation=$opName document=${docRef.path} update_applied=true');

      
    } on FirebaseException catch (e) {
      
      if (e.code == 'not-found' && createIfMissing) {
        try {
          await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => docRef.set(updates, SetOptions(merge: true)), source: 'user_status_service.set');

          
        } on FirebaseException {
          rethrow;
        }
      } else {
        debugPrint('[USER-STATUS] operation=$opName document=${docRef.path} failed code=${e.code}');
        rethrow;
      }
    } catch (error, stackTrace) {
      debugPrint('[USER-STATUS] operation=$opName document=${docRef.path} exception=$error\n$stackTrace');
      rethrow;
    }
  }

  
  Future<void> updateLogOutUserStatus(
      String userId, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      updates,
      opName: 'updateLogOutUserStatus',
      createIfMissing: false,
    );
  }

  Future<void> updateWorkingUserStatus(
      String userId, {
        bool? isWorking,
        bool? isSaved,
      }) async {
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;

    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      updates,
      opName: 'updateWorkingUserStatus',
      createIfMissing: false,
    );
  }

  Future<void> updateLoginSession({
    required String userId,
    required bool isSaved,
    String? currentArea,
    String? selectedArea,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId');
    }

    final updates = <String, dynamic>{
      'isSaved': isSaved,
    };
    final normalizedCurrentArea = (currentArea ?? '').trim();
    final normalizedSelectedArea = (selectedArea ?? '').trim();
    if (normalizedCurrentArea.isNotEmpty) {
      updates['currentArea'] = normalizedCurrentArea;
    }
    if (normalizedSelectedArea.isNotEmpty) {
      updates['selectedArea'] = normalizedSelectedArea;
    }

    final fields = updates.keys.join(',');
    final startedAt = DateTime.now();
    debugPrint(
      '[USER-STATUS][${startedAt.toIso8601String()}] loginSession update start document=user_accounts/$normalizedUserId fields=$fields firebaseRead=0 firebaseWrite=1 userAccountsShowRead=0 userAccountsShowWrite=0',
    );

    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.update, () => _getUserCollectionRef().doc(normalizedUserId).update(updates), source: 'user_status_service.update');
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        '[USER-STATUS][${DateTime.now().toIso8601String()}] loginSession update success document=user_accounts/$normalizedUserId fields=$fields elapsedMs=$elapsedMs firebaseRead=0 firebaseWrite=1 userAccountsShowRead=0 userAccountsShowWrite=0',
      );
    } catch (error, stackTrace) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        '[USER-STATUS][${DateTime.now().toIso8601String()}] loginSession update failed document=user_accounts/$normalizedUserId fields=$fields elapsedMs=$elapsedMs error=$error\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> updateLoadCurrentArea(
      String codeNumber,
      String area,
      String currentArea,
      ) async {
    final userId = '$codeNumber-$area';
    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      {'currentArea': currentArea},
      opName: 'updateLoadCurrentArea',
    );
  }

  Future<void> areaPickerCurrentArea(
      String codeNumber,
      String area,
      String currentArea,
      ) async {
    final userId = '$codeNumber-$area';
    await _safeUpdate(
      _getUserCollectionRef(),
      userId,
      {'currentArea': currentArea},
      opName: 'areaPickerCurrentArea',
    );
  }

  
  Future<void> updateLogOutTabletStatus(
    String tabletId, {
    bool? isWorking,
    bool? isSaved,
  }) async {
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
    String tabletId, {
    bool? isWorking,
    bool? isSaved,
  }) async {
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
    String tabletId,
    String currentArea,
  ) async {
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      <String, dynamic>{'currentArea': currentArea},
      opName: 'updateLoadCurrentAreaTablet',
    );
  }

  Future<void> areaPickerCurrentAreaTablet(
    String tabletId,
    String currentArea,
  ) async {
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      <String, dynamic>{'currentArea': currentArea},
      opName: 'areaPickerCurrentAreaTablet',
    );
  }
}
