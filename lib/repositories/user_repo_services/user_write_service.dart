import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tablet_model.dart';
import '../../models/user_model.dart';
import '../../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';
import '../../utils/usage/usage_reporter.dart';

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

  // ✅ null-safe: division/area가 null일 가능성까지 방어
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

  /// ✅ user_accounts에는 "활성/비활성(soft disable)" 필드를 저장하지 않기 위한 전용 맵
  /// - isActive / disabledAt 등은 user_accounts_show에만 둔다
  Map<String, dynamic> _toUserAccountsMap(UserModel user) {
    final map = Map<String, dynamic>.from(user.toMap());
    map.remove('isActive');
    map.remove('disabledAt');
    // 원본에 updatedAt을 저장하지 않으려면 제거 (show 메타에서만 관리)
    map.remove('updatedAt');
    return map;
  }

  /// ✅ show 메타에서 limit 정규화
  int _normalizeLimit(dynamic v) {
    if (v is int && v > 0) return v;
    // limit 미설정/비정상 값이면 사실상 무제한으로 취급(정책에 맞게 조정 가능)
    return 1 << 30;
  }

  int? _asInt(dynamic v) => (v is int) ? v : null;

  /// ✅ (중요) Transaction 내부에서 Query get이 불가하므로,
  /// - activeCount 미존재(레거시) 또는
  /// - (strict 모드에서) activeCount 정합성 검증이 필요한 경우
  /// 트랜잭션 밖에서 show/users(isActive==true) 재집계를 수행하고 meta에 반영한다.
  ///
  /// strict=true:
  ///   - 항상 실제 개수를 계산하여 meta.activeCount와 비교(불일치면 갱신)
  /// strict=false:
  ///   - meta.activeCount가 없거나 비정상(<0)일 때만 1회 계산/저장
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

      // ✅ show/users에서 isActive==true 개수를 계산(트랜잭션 밖)
      final qSnap = await showDocRef.collection('users').where('isActive', isEqualTo: true).get();
      final actual = qSnap.docs.length;

      // metaCount가 없거나, 불일치하거나, 음수였으면 갱신
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
      // 정합성 보정 실패는 치명적으로 만들지 않음(이후 트랜잭션에서 0 fallback)
      return 0;
    }
  }

  /// 사용자 추가
  /// - user_accounts/{userId} 저장  (✅ isActive 미저장)
  /// - user_accounts_show/{division-area} 메타 upsert (+ activeCount 유지)
  /// - user_accounts_show/{division-area}/users/{userId} 저장 (✅ isActive 저장)
  ///
  /// ✅ activeLimit 초과 방지(엄격):
  /// - (활성 생성 시) 트랜잭션 전에 show/users를 재집계하여 activeCount 정합성 보정(strict)
  /// - 트랜잭션에서는 meta.activeCount 기준으로 delta(상태 변화량) 계산 후 제한 검사
  Future<void> addUserCard(UserModel user) async {
    final userDocRef = _getUserCollectionRef().doc(user.id);

    final division = _divisionOfUser(user);
    final area = _areaOfUser(user);
    final showId = _showDocId(division, area);

    final showDocRef = _getUserShowCollectionRef().doc(showId);
    final showUserDocRef = showDocRef.collection('users').doc(user.id);

    final bool wantActive = user.isActive;

    // ✅ 레거시/정합성 보정:
    // - 활성 생성이면 strict=true로 실제 activeCount 재집계
    // - 비활성 생성이면 activeCount가 없을 때만 초기화
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

        // 기존 유저 문서가 있으면 delta 계산(재실행/중복 호출 안전)
        final existingSnap = await tx.get(showUserDocRef);
        final existingData = existingSnap.data() ?? <String, dynamic>{};
        final bool existed = existingSnap.exists;
        final bool existingActive = (existingData['isActive'] as bool?) ?? false;

        int delta = 0;
        if (!existed) {
          // 신규 생성
          delta = wantActive ? 1 : 0;
        } else {
          // 기존 문서가 있으면 상태 변화량만 반영
          if (!existingActive && wantActive) delta = 1;
          if (existingActive && !wantActive) delta = -1;
        }

        // ✅ 엄격 제한 검사
        if (delta > 0) {
          // 이미 limit 이상이면 어떤 경우에도 증가 불가
          if (activeCount0 >= limit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$limit');
          }
          if ((activeCount0 + delta) > limit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$limit');
          }
        }

        // 1) 원본 user_accounts 저장(✅ isActive/disabledAt 제거)
        tx.set(userDocRef, _toUserAccountsMap(user));

        // 2) show 메타 갱신
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

        // 3) show/users 저장(✅ isActive 포함)
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

      /*await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(user.id),
        action: 'write',
        n: 1,
        source: 'UserWriteService.addUserCard',
      );*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'users.add',
          'collection': 'user_accounts',
          'docPath': userDocRef.path,
          'docId': user.id,
          'mirror': {
            'collection': 'user_accounts_show',
            'docId': showId,
            'subcollection': 'users',
            'mirrorDocPath': showUserDocRef.path,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'add', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'users.add.unknown',
          'collection': 'user_accounts',
          'docPath': userDocRef.path,
          'docId': user.id,
          'mirror': {
            'collection': 'user_accounts_show',
            'docId': showId,
            'subcollection': 'users',
            'mirrorDocPath': showUserDocRef.path,
          },
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
        await DebugDatabaseLogger().log({
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
        await DebugDatabaseLogger().log({
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
  /// - user_accounts/{userId} set (✅ isActive 미저장)
  /// - user_accounts_show/{division-area}/users/{userId} set (✅ isActive는 "유지"가 기본)
  /// - division/area 이동이 감지되면 이전 show/users 문서를 삭제
  ///
  /// ✅ 중요:
  /// - updateUser는 "활성 상태 변경"이 목적이 아니므로 isActive/disabledAt은 기본적으로 건드리지 않는다.
  /// - 이동 시에는 old show/users의 isActive를 읽어 activeCount를 정확히 -1/+1 보정한다.
  /// - 이동 + 활성 계정이면 destination activeLimit을 엄격히 적용(정합성 보정 후 트랜잭션)
  Future<void> updateUser(UserModel user) async {
    final userDocRef = _getUserCollectionRef().doc(user.id);

    // 이전 user_accounts로 old division/area 추정
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

    // ✅ 레거시 activeCount 초기화/정합성:
    // - 이동이 없으면 strict 불필요(활성 제한이 변하지 않음)
    // - 이동이 있으면 "활성 계정 이동"은 사실상 destination에서 +1이 될 수 있으므로 strict로 보정
    await _ensureOrSyncActiveCount(
      showDocRef: newShowDocRef,
      division: newDivision,
      area: newArea,
      strict: moved, // 이동 시 destination은 정합성 강화
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

        // old show/users에서 실제 활성 상태를 읽어서 이동 count 보정에 사용
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

        // ✅ 이동 + 활성 계정이면 destination 제한 체크(엄격)
        if (moved && wasActive) {
          if (newCount0 >= newLimit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$newLimit');
          }
          if ((newCount0 + 1) > newLimit) {
            throw StateError('ACTIVE_LIMIT_REACHED:$newLimit');
          }
        }

        // 1) 원본 user_accounts 갱신(✅ isActive/disabledAt 제거)
        tx.set(userDocRef, _toUserAccountsMap(user));

        // 2) show/users 갱신(기본적으로 isActive/disabledAt은 건드리지 않음)
        final userMap = Map<String, dynamic>.from(user.toMap());
        userMap.remove('isActive');
        userMap.remove('disabledAt');
        userMap['updatedAt'] = FieldValue.serverTimestamp();

        if (!moved) {
          // 같은 bucket 내 업데이트
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

        // moved=true:
        tx.delete(oldShowUserDocRef);

        final movedUserMap = <String, dynamic>{
          ...userMap,
          'isActive': wasActive,
          if (wasActive) 'disabledAt': FieldValue.delete(),
          if (!wasActive) 'disabledAt': (disabledAtValue != null) ? disabledAtValue : FieldValue.serverTimestamp(),
        };
        tx.set(newShowUserDocRef, movedUserMap, SetOptions(merge: true));

        // meta count 보정
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

      /*await UsageReporter.instance.report(
        area: _inferAreaFromHyphenId(user.id),
        action: 'write',
        n: 1,
        source: 'UserWriteService.updateUser',
      );*/
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'users.update',
          'collection': 'user_accounts',
          'docPath': userDocRef.path,
          'docId': user.id,
          'mirror': {
            'collection': 'user_accounts_show',
            'docId': newShowId,
            'subcollection': 'users',
            'mirrorDocPath': newShowUserDocRef.path,
          },
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'users.update.unknown',
          'collection': 'user_accounts',
          'docPath': userDocRef.path,
          'docId': user.id,
          'mirror': {
            'collection': 'user_accounts_show',
            'docId': newShowId,
            'subcollection': 'users',
            'mirrorDocPath': newShowUserDocRef.path,
          },
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
        await DebugDatabaseLogger().log({
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
        await DebugDatabaseLogger().log({
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

  /// ✅ 사용자 활성/비활성(soft disable)
  /// - ✅ user_accounts는 "절대" 업데이트하지 않음
  /// - isActive는 user_accounts_show/{division-area}/users/{userId} 에만 저장
  /// - activeLimit/activeCount는 user_accounts_show/{division-area} 메타에서 관리
  ///
  /// ✅ 엄격 제한:
  /// - 활성화(isActive=true) 시에는 트랜잭션 전에 show/users 재집계(strict)로 activeCount를 동기화한 뒤 진행
  /// - 트랜잭션 내부에서는 meta.activeCount 기준으로 제한 체크 및 +1 반영(동시성 안전)
  Future<void> setUserActiveStatus(
    String userId, {
    required bool isActive,
  }) async {
    final userDocRef = _getUserCollectionRef().doc(userId);

    try {
      // show 경로 계산을 위해 현재 user 문서 1회 조회(읽기만)
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

      // ✅ 레거시/정합성 보정:
      // - 활성화라면 strict=true로 실제 activeCount 재집계
      // - 비활성화라면 activeCount 없을 때만 초기화
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
          // 운영상 안전을 위해: show/users가 없으면 에러로 처리(=데이터 정합성 깨짐)
          throw StateError('SHOW_USER_DOC_MISSING:showId=$showId userId=$userId');
        }

        final userData = userSnap.data() ?? <String, dynamic>{};
        final bool currentActive = (userData['isActive'] as bool?) ?? true;

        // 변화 없으면 메타만 터치하고 종료
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
          // ✅ 활성화 제한 체크(엄격)
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

        // show 메타 갱신(division/area도 같이 유지)
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
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'users.setActiveStatus',
          'collection': 'user_accounts_show',
          'docId': userId,
          'inputs': {'isActive': isActive},
          'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'activeStatus', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'op': 'users.setActiveStatus.unknown',
          'collection': 'user_accounts_show',
          'docId': userId,
          'inputs': {'isActive': isActive},
          'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
          'stack': st.toString(),
          'tags': ['users', 'activeStatus', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// 사용자 삭제 (ID 목록 기준)
  /// - user_accounts/{userId} delete
  /// - user_accounts_show/{division-area}/users/{userId} delete
  ///
  /// ✅ count 보정:
  /// - show/users 문서가 존재하고 isActive=true면 activeCount -1
  /// - activeCount가 없으면(레거시) 1회 초기화 후 트랜잭션에서 보정
  Future<void> deleteUsers(List<String> ids) async {
    final buckets = <String, int>{};

    for (final id in ids) {
      final userDocRef = _getUserCollectionRef().doc(id);

      try {
        // show 경로 파악을 위해 user_accounts 문서를 가능한 한 읽음
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

        // ✅ 레거시 activeCount 초기화(필요 시)
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

          // show/users 삭제
          tx.delete(showUserDocRef);
          // 원본 삭제
          tx.delete(userDocRef);

          // 메타 갱신
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
      } on FirebaseException catch (e, st) {
        try {
          await DebugDatabaseLogger().log({
            'op': 'users.delete',
            'collection': 'user_accounts',
            'docPath': userDocRef.path,
            'docId': id,
            'error': {'type': e.runtimeType.toString(), 'code': e.code, 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['users', 'delete', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      } catch (e, st) {
        try {
          await DebugDatabaseLogger().log({
            'op': 'users.delete.unknown',
            'collection': 'user_accounts',
            'docPath': userDocRef.path,
            'docId': id,
            'error': {'type': e.runtimeType.toString(), 'message': e.toString()},
            'stack': st.toString(),
            'tags': ['users', 'delete', 'error'],
          }, level: 'error');
        } catch (_) {}
        rethrow;
      }
    }

    // (기존 코드의 delete 집계 UsageReporter가 주석 처리되어 unused 경고가 나던 부분은 제거 유지)
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
          await DebugDatabaseLogger().log({
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
          await DebugDatabaseLogger().log({
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
