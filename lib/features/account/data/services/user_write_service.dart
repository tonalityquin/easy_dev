import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../app/usage/usage_reporter.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';

class _ShowAccountCounts {
  const _ShowAccountCounts({
    required this.activeCount,
    required this.inactiveCount,
  });

  final int activeCount;
  final int inactiveCount;

  int get totalCount => activeCount + inactiveCount;

  _ShowAccountCounts applyDeltas({
    int activeDelta = 0,
    int inactiveDelta = 0,
  }) {
    var active = activeCount + activeDelta;
    var inactive = inactiveCount + inactiveDelta;
    if (active < 0) active = 0;
    if (inactive < 0) inactive = 0;
    return _ShowAccountCounts(activeCount: active, inactiveCount: inactive);
  }

  Map<String, int> toMap() {
    return <String, int>{
      'activeCount': activeCount,
      'inactiveCount': inactiveCount,
      'totalCount': totalCount,
    };
  }
}

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
    if (v is int && v >= 0) return v;
    return 1 << 30;
  }

  int? _asInt(dynamic v) => (v is int) ? v : null;

  int _nonNegative(dynamic v) {
    final i = _asInt(v);
    if (i == null || i < 0) return 0;
    return i;
  }

  _ShowAccountCounts _countsFromMeta(Map<String, dynamic> data) {
    final active = _nonNegative(data['activeCount']);
    final inactiveRaw = _asInt(data['inactiveCount']);
    final totalRaw = _asInt(data['totalCount']);
    var inactive = inactiveRaw == null || inactiveRaw < 0 ? 0 : inactiveRaw;
    if ((inactiveRaw == null || inactiveRaw < 0) && totalRaw != null && totalRaw >= active) {
      inactive = totalRaw - active;
    }
    return _ShowAccountCounts(activeCount: active, inactiveCount: inactive);
  }

  bool _metaNeedsCountCompute(Map<String, dynamic> data, bool strict) {
    if (strict) return true;
    final active = _asInt(data['activeCount']);
    final inactive = _asInt(data['inactiveCount']);
    final total = _asInt(data['totalCount']);
    if (active == null || active < 0) return true;
    if (inactive == null || inactive < 0) return true;
    if (total == null || total < 0) return true;
    return total != active + inactive;
  }

  Future<_ShowAccountCounts> _ensureOrSyncAccountCounts({
    required DocumentReference<Map<String, dynamic>> showDocRef,
    required String division,
    required String area,
    required bool strict,
  }) async {
    try {
      final metaSnap = await showDocRef.get();
      final meta = metaSnap.data() ?? <String, dynamic>{};
      if (!_metaNeedsCountCompute(meta, strict)) {
        return _countsFromMeta(meta);
      }

      final qSnap = await showDocRef.collection('users').get();
      var active = 0;
      var inactive = 0;
      for (final doc in qSnap.docs) {
        final data = doc.data();
        final isActive = (data['isActive'] as bool?) ?? true;
        if (isActive) {
          active += 1;
        } else {
          inactive += 1;
        }
      }

      final counts = _ShowAccountCounts(activeCount: active, inactiveCount: inactive);
      await showDocRef.set(
        {
          'division': division,
          'area': area,
          ...counts.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return counts;
    } catch (_) {
      return const _ShowAccountCounts(activeCount: 0, inactiveCount: 0);
    }
  }

  void _assertActiveLimit({
    required _ShowAccountCounts counts,
    required int activeDelta,
    required int limit,
  }) {
    if (activeDelta <= 0) return;
    if (counts.activeCount >= limit || counts.activeCount + activeDelta > limit) {
      throw StateError('ACTIVE_LIMIT_REACHED:$limit');
    }
  }

  void _assertTotalLimit({
    required _ShowAccountCounts counts,
    required int totalDelta,
    required int limit,
  }) {
    if (totalDelta <= 0) return;
    if (counts.totalCount >= limit || counts.totalCount + totalDelta > limit) {
      throw StateError('TOTAL_LIMIT_REACHED:$limit');
    }
  }

  Map<String, dynamic> _showMetaPayload({
    required String division,
    required String area,
    required _ShowAccountCounts counts,
  }) {
    return <String, dynamic>{
      'division': division,
      'area': area,
      ...counts.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> addUserCard(UserModel user) async {
    final userDocRef = _getUserCollectionRef().doc(user.id);

    final division = _divisionOfUser(user);
    final area = _areaOfUser(user);
    final showId = _showDocId(division, area);

    final showDocRef = _getUserShowCollectionRef().doc(showId);
    final showUserDocRef = showDocRef.collection('users').doc(user.id);

    final bool wantActive = user.isActive;

    await _ensureOrSyncAccountCounts(
      showDocRef: showDocRef,
      division: division,
      area: area,
      strict: true,
    );

    try {
      await _firestore.runTransaction((tx) async {
        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};

        final activeLimit = _normalizeLimit(showData['activeLimit']);
        final totalLimit = _normalizeLimit(showData['totalLimit']);
        final counts0 = _countsFromMeta(showData);

        final existingSnap = await tx.get(showUserDocRef);
        final existingData = existingSnap.data() ?? <String, dynamic>{};
        final bool existed = existingSnap.exists;
        final bool existingActive = (existingData['isActive'] as bool?) ?? false;

        var activeDelta = 0;
        var inactiveDelta = 0;
        var totalDelta = 0;
        if (!existed) {
          totalDelta = 1;
          if (wantActive) {
            activeDelta = 1;
          } else {
            inactiveDelta = 1;
          }
        } else if (!existingActive && wantActive) {
          activeDelta = 1;
          inactiveDelta = -1;
        } else if (existingActive && !wantActive) {
          activeDelta = -1;
          inactiveDelta = 1;
        }

        _assertTotalLimit(counts: counts0, totalDelta: totalDelta, limit: totalLimit);
        _assertActiveLimit(counts: counts0, activeDelta: activeDelta, limit: activeLimit);

        final counts1 = counts0.applyDeltas(
          activeDelta: activeDelta,
          inactiveDelta: inactiveDelta,
        );

        tx.set(userDocRef, _toUserAccountsMap(user));
        tx.set(
          showDocRef,
          _showMetaPayload(division: division, area: area, counts: counts1),
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

    await _ensureOrSyncAccountCounts(
      showDocRef: newShowDocRef,
      division: newDivision,
      area: newArea,
      strict: true,
    );
    if (moved) {
      await _ensureOrSyncAccountCounts(
        showDocRef: oldShowDocRef,
        division: oldDivision,
        area: oldArea,
        strict: true,
      );
    }

    try {
      await _firestore.runTransaction((tx) async {
        final newShowSnap = await tx.get(newShowDocRef);
        final newShowData = newShowSnap.data() ?? <String, dynamic>{};
        final newActiveLimit = _normalizeLimit(newShowData['activeLimit']);
        final newTotalLimit = _normalizeLimit(newShowData['totalLimit']);
        final newCounts0 = _countsFromMeta(newShowData);

        final userMap = Map<String, dynamic>.from(user.toMap());
        userMap.remove('isActive');
        userMap.remove('disabledAt');
        userMap['updatedAt'] = FieldValue.serverTimestamp();

        if (!moved) {
          final currentShowUserSnap = await tx.get(newShowUserDocRef);
          var counts1 = newCounts0;
          if (!currentShowUserSnap.exists) {
            final wantActive = user.isActive;
            final activeDelta = wantActive ? 1 : 0;
            final inactiveDelta = wantActive ? 0 : 1;
            _assertTotalLimit(counts: newCounts0, totalDelta: 1, limit: newTotalLimit);
            _assertActiveLimit(counts: newCounts0, activeDelta: activeDelta, limit: newActiveLimit);
            counts1 = newCounts0.applyDeltas(
              activeDelta: activeDelta,
              inactiveDelta: inactiveDelta,
            );
            userMap['isActive'] = wantActive;
            userMap['disabledAt'] = wantActive ? FieldValue.delete() : FieldValue.serverTimestamp();
          }

          tx.set(userDocRef, _toUserAccountsMap(user));
          tx.set(
            newShowDocRef,
            _showMetaPayload(division: newDivision, area: newArea, counts: counts1),
            SetOptions(merge: true),
          );
          tx.set(newShowUserDocRef, userMap, SetOptions(merge: true));
          return;
        }

        final oldShowSnap = await tx.get(oldShowDocRef);
        final oldShowData = oldShowSnap.data() ?? <String, dynamic>{};
        final oldCounts0 = _countsFromMeta(oldShowData);

        final oldUserSnap = await tx.get(oldShowUserDocRef);
        final newUserSnap = await tx.get(newShowUserDocRef);

        final oldExists = oldUserSnap.exists;
        final newExists = newUserSnap.exists;
        final oldData = oldUserSnap.data() ?? <String, dynamic>{};
        final newData = newUserSnap.data() ?? <String, dynamic>{};
        final oldActive = (oldData['isActive'] as bool?) ?? false;
        final newActive = (newData['isActive'] as bool?) ?? false;
        final targetActive = oldExists ? oldActive : (newExists ? newActive : user.isActive);
        final disabledAtValue = oldExists ? oldData['disabledAt'] : newData['disabledAt'];

        final oldActiveDelta = oldExists && oldActive ? -1 : 0;
        final oldInactiveDelta = oldExists && !oldActive ? -1 : 0;
        final newActiveDelta = targetActive
            ? (newExists && newActive ? 0 : 1)
            : (newExists && newActive ? -1 : 0);
        final newInactiveDelta = targetActive
            ? (newExists && !newActive ? -1 : 0)
            : (newExists && !newActive ? 0 : 1);
        final newTotalDelta = newExists ? 0 : 1;

        _assertTotalLimit(counts: newCounts0, totalDelta: newTotalDelta, limit: newTotalLimit);
        _assertActiveLimit(counts: newCounts0, activeDelta: newActiveDelta, limit: newActiveLimit);

        final oldCounts1 = oldCounts0.applyDeltas(
          activeDelta: oldActiveDelta,
          inactiveDelta: oldInactiveDelta,
        );
        final newCounts1 = newCounts0.applyDeltas(
          activeDelta: newActiveDelta,
          inactiveDelta: newInactiveDelta,
        );

        tx.set(userDocRef, _toUserAccountsMap(user));
        if (oldExists) {
          tx.delete(oldShowUserDocRef);
        }

        final movedUserMap = <String, dynamic>{
          ...userMap,
          'isActive': targetActive,
          if (targetActive) 'disabledAt': FieldValue.delete(),
          if (!targetActive) 'disabledAt': disabledAtValue ?? FieldValue.serverTimestamp(),
        };
        tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true));

        tx.set(
          newShowDocRef,
          _showMetaPayload(division: newDivision, area: newArea, counts: newCounts1),
          SetOptions(merge: true),
        );
        tx.set(
          oldShowDocRef,
          _showMetaPayload(division: oldDivision, area: oldArea, counts: oldCounts1),
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

      await _ensureOrSyncAccountCounts(
        showDocRef: showDocRef,
        division: division,
        area: area,
        strict: true,
      );

      await _firestore.runTransaction((tx) async {
        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};

        final int activeLimit = _normalizeLimit(showData['activeLimit']);
        final counts0 = _countsFromMeta(showData);

        final userSnap = await tx.get(showUserDocRef);
        if (!userSnap.exists) {
          throw StateError('SHOW_USER_DOC_MISSING:showId=$showId userId=$userId');
        }

        final userData = userSnap.data() ?? <String, dynamic>{};
        final bool currentActive = (userData['isActive'] as bool?) ?? true;

        if (currentActive == isActive) {
          tx.set(
            showDocRef,
            _showMetaPayload(division: division, area: area, counts: counts0),
            SetOptions(merge: true),
          );
          return;
        }

        var activeDelta = 0;
        var inactiveDelta = 0;
        if (isActive) {
          activeDelta = 1;
          inactiveDelta = -1;
          _assertActiveLimit(counts: counts0, activeDelta: activeDelta, limit: activeLimit);

          tx.set(
            showUserDocRef,
            {
              'isActive': true,
              'updatedAt': FieldValue.serverTimestamp(),
              'disabledAt': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );
        } else {
          activeDelta = -1;
          inactiveDelta = 1;
          tx.set(
            showUserDocRef,
            {
              'isActive': false,
              'updatedAt': FieldValue.serverTimestamp(),
              'disabledAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        final counts1 = counts0.applyDeltas(
          activeDelta: activeDelta,
          inactiveDelta: inactiveDelta,
        );
        tx.set(
          showDocRef,
          _showMetaPayload(division: division, area: area, counts: counts1),
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

        await _ensureOrSyncAccountCounts(
          showDocRef: showDocRef,
          division: division,
          area: area,
          strict: true,
        );

        await _firestore.runTransaction((tx) async {
          final showSnap = await tx.get(showDocRef);
          final showData = showSnap.data() ?? <String, dynamic>{};
          final counts0 = _countsFromMeta(showData);

          final showUserSnap = await tx.get(showUserDocRef);
          var counts1 = counts0;
          if (showUserSnap.exists) {
            final d = showUserSnap.data() ?? <String, dynamic>{};
            final wasActive = (d['isActive'] as bool?) ?? false;
            counts1 = counts0.applyDeltas(
              activeDelta: wasActive ? -1 : 0,
              inactiveDelta: wasActive ? 0 : -1,
            );
          }

          tx.delete(showUserDocRef);
          tx.delete(userDocRef);
          tx.set(
            showDocRef,
            _showMetaPayload(division: division, area: area, counts: counts1),
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
