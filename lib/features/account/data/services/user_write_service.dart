import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../utils/usage/usage_reporter.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';
class UserWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() {
    return _firestore.collection('user_accounts');
  }

  CollectionReference<Map<String, dynamic>> _getUserShowCollectionRef() {
    return _firestore.collection('user_accounts_show');
  }

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() {
    return _firestore.collection('tablet_accounts');
  }

  String _inferAreaFromHyphenId(String id) {
    final idx = id.lastIndexOf('-');
    if (idx <= 0 || idx >= id.length - 1) return 'unknown';
    return id.substring(idx + 1);
  }

  
  String _showDocId(String? division, String? area) {
    final d = (division ?? '').trim().isEmpty ? 'unknownDivision' : (division ?? '').trim();
    final a = (area ?? '').trim().isEmpty ? 'unknownArea' : (area ?? '').trim();
    return '$d-$a';
  }

  String _divisionOfUser(UserModel u) {
    final d = (u.divisions.isNotEmpty ? u.divisions.first : '').trim();
    return d.isNotEmpty ? d : 'unknownDivision';
  }

  String _areaOfUser(UserModel u) {
    final ca = (u.currentArea ?? '').trim();
    if (ca.isNotEmpty) return ca;

    final sa = (u.selectedArea ?? '').trim();
    if (sa.isNotEmpty) return sa;

    final a0 = (u.areas.isNotEmpty ? u.areas.first : '').trim();
    if (a0.isNotEmpty) return a0;

    return _inferAreaFromHyphenId(u.id);
  }

  
  
  Map<String, dynamic> _toUserAccountsMap(UserModel user) {
    final map = Map<String, dynamic>.from(user.toMap());
    map.remove('isActive');
    map.remove('disabledAt');
    
    map.remove('updatedAt');
    return map;
  }

  
  int _normalizeLimit(dynamic v) {
    if (v is int && v > 0) return v;
    
    return 1 << 30;
  }

  int? _asInt(dynamic v) => (v is int) ? v : null;

  
  
  
  
  
  
  
  
  
  Future<int> _ensureOrSyncActiveCount({
    required DocumentReference<Map<String, dynamic>> showDocRef,
    required String division,
    required String area,
    required bool strict,
  }) async {
    try {
      final metaSnap = await showDocRef.get();
      final meta = metaSnap.data() ?? <String, dynamic>{};
      final metaCount = _asInt(meta['activeCount']);

      final bool needCompute = strict || metaCount == null || metaCount < 0;
      if (!needCompute) return metaCount;

      
      final qSnap = await showDocRef.collection('users').where('isActive', isEqualTo: true).get();
      final actual = qSnap.docs.length;

      
      if (metaCount == null || metaCount < 0 || metaCount != actual) {
        await showDocRef.set(
          {
            'division': division,
            'area': area,
            'activeCount': actual,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      return actual;
    } catch (_) {
      
      return 0;
    }
  }

  
  
  
  
  
  
  
  
  Future<void> addUserCard(UserModel user) async {
    final userDocRef = _getUserCollectionRef().doc(user.id);

    final division = _divisionOfUser(user);
    final area = _areaOfUser(user);
    final showId = _showDocId(division, area);

    final showDocRef = _getUserShowCollectionRef().doc(showId);
    final showUserDocRef = showDocRef.collection('users').doc(user.id);

    final bool wantActive = user.isActive;

    
    await _ensureOrSyncActiveCount(
      showDocRef: showDocRef,
      division: division,
      area: area,
      strict: wantActive,
    );

    try {
      await _firestore.runTransaction((tx) async {
        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};

        final limit = _normalizeLimit(showData['activeLimit']);
        final activeCount0Raw = _asInt(showData['activeCount']) ?? 0;
        final activeCount0 = activeCount0Raw < 0 ? 0 : activeCount0Raw;

        
        final existingSnap = await tx.get(showUserDocRef);
        final existingData = existingSnap.data() ?? <String, dynamic>{};
        final bool existed = existingSnap.exists;
        final bool existingActive = (existingData['isActive'] as bool?) ?? false;

        int delta = 0;
        if (!existed) {
          
          delta = wantActive ? 1 : 0;
        } else {
          
          if (!existingActive && wantActive) delta = 1;
          if (existingActive && !wantActive) delta = -1;
        }

        
        if (delta > 0) {
          if (activeCount0 >= limit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$limit');
          }
          if ((activeCount0 + delta) > limit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$limit');
          }
        }

        
        tx.set(userDocRef, _toUserAccountsMap(user));

        
        tx.set(
          showDocRef,
          {
            'division': division,
            'area': area,
            'updatedAt': FieldValue.serverTimestamp(),
            'activeCount': activeCount0 + delta,
          },
          SetOptions(merge: true),
        );

        
        final userMap = Map<String, dynamic>.from(user.toMap());
        userMap['updatedAt'] = FieldValue.serverTimestamp();
        userMap['isActive'] = wantActive;
        if (!wantActive) {
          userMap['disabledAt'] = FieldValue.serverTimestamp();
        } else {
          userMap['disabledAt'] = FieldValue.delete();
        }

        tx.set(showUserDocRef, userMap, SetOptions(merge: true));
      });

      
    } on FirebaseException {
      
      rethrow;
    } catch (_) {
      
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
    } on FirebaseException {
      
      rethrow;
    } catch (_) {
      
      rethrow;
    }
  }

  
  
  
  
  
  
  
  
  
  Future<void> updateUser(UserModel user) async {
    final userDocRef = _getUserCollectionRef().doc(user.id);

    
    UserModel? prevUser;
    try {
      final prevSnap = await userDocRef.get();
      if (prevSnap.exists && prevSnap.data() != null) {
        prevUser = UserModel.fromMap(prevSnap.id, prevSnap.data()!);
      }
    } catch (_) {}

    final newDivision = _divisionOfUser(user);
    final newArea = _areaOfUser(user);
    final newShowId = _showDocId(newDivision, newArea);

    final oldDivision = prevUser != null ? _divisionOfUser(prevUser) : newDivision;
    final oldArea = prevUser != null ? _areaOfUser(prevUser) : newArea;
    final oldShowId = _showDocId(oldDivision, oldArea);

    final moved = prevUser != null && oldShowId != newShowId;

    final newShowDocRef = _getUserShowCollectionRef().doc(newShowId);
    final newShowUserDocRef = newShowDocRef.collection('users').doc(user.id);

    final oldShowDocRef = _getUserShowCollectionRef().doc(oldShowId);
    final oldShowUserDocRef = oldShowDocRef.collection('users').doc(user.id);

    
    await _ensureOrSyncActiveCount(
      showDocRef: newShowDocRef,
      division: newDivision,
      area: newArea,
      strict: moved,
    );
    if (moved) {
      await _ensureOrSyncActiveCount(
        showDocRef: oldShowDocRef,
        division: oldDivision,
        area: oldArea,
        strict: false,
      );
    }

    try {
      await _firestore.runTransaction((tx) async {
        final newShowSnap = await tx.get(newShowDocRef);
        final newShowData = newShowSnap.data() ?? <String, dynamic>{};
        final newLimit = _normalizeLimit(newShowData['activeLimit']);
        final newCount0Raw = _asInt(newShowData['activeCount']) ?? 0;
        final newCount0 = newCount0Raw < 0 ? 0 : newCount0Raw;

        
        bool wasActive = false;
        dynamic disabledAtValue;
        if (moved) {
          final oldUserSnap = await tx.get(oldShowUserDocRef);
          if (oldUserSnap.exists) {
            final d = oldUserSnap.data() ?? <String, dynamic>{};
            wasActive = (d['isActive'] as bool?) ?? false;
            disabledAtValue = d['disabledAt'];
          } else {
            wasActive = false;
          }
        }

        int oldCount0 = 0;
        if (moved) {
          final oldShowSnap = await tx.get(oldShowDocRef);
          final oldShowData = oldShowSnap.data() ?? <String, dynamic>{};
          final oldCount0Raw = _asInt(oldShowData['activeCount']) ?? 0;
          oldCount0 = oldCount0Raw < 0 ? 0 : oldCount0Raw;
        }

        
        if (moved && wasActive) {
          if (newCount0 >= newLimit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$newLimit');
          }
          if ((newCount0 + 1) > newLimit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$newLimit');
          }
        }

        
        tx.set(userDocRef, _toUserAccountsMap(user));

        
        final userMap = Map<String, dynamic>.from(user.toMap());
        userMap.remove('isActive');
        userMap.remove('disabledAt');
        userMap['updatedAt'] = FieldValue.serverTimestamp();

        if (!moved) {
          
          tx.set(
            newShowDocRef,
            {
              'division': newDivision,
              'area': newArea,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(newShowUserDocRef, userMap, SetOptions(merge: true));
          return;
        }

        
        tx.delete(oldShowUserDocRef);

        final movedUserMap = <String, dynamic>{
          ...userMap,
          'isActive': wasActive,
          if (wasActive) 'disabledAt': FieldValue.delete(),
          if (!wasActive) 'disabledAt': (disabledAtValue != null) ? disabledAtValue : FieldValue.serverTimestamp(),
        };
        tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true));

        
        final newCount = wasActive ? (newCount0 + 1) : newCount0;
        var oldCount = oldCount0;
        if (wasActive) {
          oldCount = oldCount - 1;
          if (oldCount < 0) oldCount = 0;
        }

        tx.set(
          newShowDocRef,
          {
            'division': newDivision,
            'area': newArea,
            'activeCount': newCount,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(
          oldShowDocRef,
          {
            'division': oldDivision,
            'area': oldArea,
            'activeCount': oldCount,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      
    } on FirebaseException {
      
      rethrow;
    } catch (_) {
      
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
    } on FirebaseException {
      
      rethrow;
    } catch (_) {
      
      rethrow;
    }
  }

  
  
  
  
  
  
  
  
  Future<void> setUserActiveStatus(
      String userId, {
        required bool isActive,
      }) async {
    final userDocRef = _getUserCollectionRef().doc(userId);

    try {
      
      final snap = await userDocRef.get();
      if (!snap.exists || snap.data() == null) {
        throw Exception('setUserActiveStatus 실패: user_accounts 문서가 없습니다. (userId=$userId)');
      }

      final current = UserModel.fromMap(snap.id, snap.data()!);

      final division = _divisionOfUser(current);
      final area = _areaOfUser(current);
      final showId = _showDocId(division, area);

      final showDocRef = _getUserShowCollectionRef().doc(showId);
      final showUserDocRef = showDocRef.collection('users').doc(userId);

      
      await _ensureOrSyncActiveCount(
        showDocRef: showDocRef,
        division: division,
        area: area,
        strict: isActive,
      );

      await _firestore.runTransaction((tx) async {
        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};

        final int limit = _normalizeLimit(showData['activeLimit']);
        int activeCountRaw = _asInt(showData['activeCount']) ?? 0;
        int activeCount = activeCountRaw < 0 ? 0 : activeCountRaw;

        final userSnap = await tx.get(showUserDocRef);
        if (!userSnap.exists) {
          throw StateError('SHOW_USER_DOC_MISSING:showId=$showId userId=$userId');
        }

        final userData = userSnap.data() ?? <String, dynamic>{};
        final bool currentActive = (userData['isActive'] as bool?) ?? true;

        
        if (currentActive == isActive) {
          tx.set(
            showDocRef,
            {
              'division': division,
              'area': area,
              'activeCount': activeCount,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          return;
        }

        if (isActive) {
          if (activeCount >= limit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$limit');
          }
          if ((activeCount + 1) > limit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$limit');
          }

          tx.set(
            showUserDocRef,
            {
              'isActive': true,
              'updatedAt': FieldValue.serverTimestamp(),
              'disabledAt': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );

          activeCount = activeCount + 1;
        } else {
          tx.set(
            showUserDocRef,
            {
              'isActive': false,
              'updatedAt': FieldValue.serverTimestamp(),
              'disabledAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          activeCount = activeCount - 1;
          if (activeCount < 0) activeCount = 0;
        }

        tx.set(
          showDocRef,
          {
            'division': division,
            'area': area,
            'activeCount': activeCount,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } on FirebaseException {
      
      rethrow;
    } catch (_) {
      
      rethrow;
    }
  }

  
  
  
  
  
  
  
  Future<void> deleteUsers(List<String> ids) async {
    final buckets = <String, int>{};

    for (final id in ids) {
      final userDocRef = _getUserCollectionRef().doc(id);

      try {
        
        UserModel? prevUser;
        try {
          final snap = await userDocRef.get();
          if (snap.exists && snap.data() != null) {
            prevUser = UserModel.fromMap(snap.id, snap.data()!);
          }
        } catch (_) {}

        if (prevUser == null) {
          await userDocRef.delete();
          final area = _inferAreaFromHyphenId(id);
          buckets.update(area, (v) => v + 1, ifAbsent: () => 1);
          continue;
        }

        final division = _divisionOfUser(prevUser);
        final area = _areaOfUser(prevUser);
        final showId = _showDocId(division, area);

        final showDocRef = _getUserShowCollectionRef().doc(showId);
        final showUserDocRef = showDocRef.collection('users').doc(id);

        
        await _ensureOrSyncActiveCount(
          showDocRef: showDocRef,
          division: division,
          area: area,
          strict: false,
        );

        await _firestore.runTransaction((tx) async {
          final showSnap = await tx.get(showDocRef);
          final showData = showSnap.data() ?? <String, dynamic>{};
          int activeCountRaw = _asInt(showData['activeCount']) ?? 0;
          int activeCount = activeCountRaw < 0 ? 0 : activeCountRaw;

          bool wasActive = false;
          final showUserSnap = await tx.get(showUserDocRef);
          if (showUserSnap.exists) {
            final d = showUserSnap.data() ?? <String, dynamic>{};
            wasActive = (d['isActive'] as bool?) ?? false;
          }

          if (wasActive) {
            activeCount = activeCount - 1;
            if (activeCount < 0) activeCount = 0;
          }

          
          tx.delete(showUserDocRef);
          
          tx.delete(userDocRef);

          
          tx.set(
            showDocRef,
            {
              'division': division,
              'area': area,
              'activeCount': activeCount,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });

        final infer = _inferAreaFromHyphenId(id);
        buckets.update(infer, (v) => v + 1, ifAbsent: () => 1);
      } on FirebaseException {
        
        rethrow;
      } catch (_) {
        
        rethrow;
      }
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
      } on FirebaseException {
        
        rethrow;
      } catch (_) {
        
        rethrow;
      }
    }

    for (final entry in buckets.entries) {
      await UsageReporter.instance.report(
        area: entry.key,
        action: 'delete',
        n: entry.value,
        source: 'UserWriteService.deleteTablets',
      );
    }
  }
}
