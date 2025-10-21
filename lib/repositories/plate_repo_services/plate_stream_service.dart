// lib/repositories/plate_repo_services/plate_stream_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';

// ▼ 로컬 로깅 유틸 & 가드 & 상태(경로는 프로젝트 구조에 맞게 유지하세요)
import '../../screens/type_package/parking_completed_package/services/local_transition_guard.dart';
import '../../screens/type_package/parking_completed_package/services/parking_completed_logger.dart';
import '../../screens/type_package/parking_completed_package/services/status_mapping.dart';
// import '../../utils/usage_reporter.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===== modify 기반 캐시(보조), 초기 스냅샷 스킵 플래그, 짧은 디듀프 =====
  final Map<String, String> _lastTypeCache = <String, String>{}; // plateId -> lastType
  final Set<String> _initedQueryKeys = <String>{};               // 초기 스냅샷 스킵
  final Map<String, DateTime> _recentLogged = <String, DateTime>{};
  final Duration _dedupeWindow = const Duration(seconds: 5);

  // ===== removed(쿼리 탈락) 기반 감지를 위한 현재 존재 집합 & 안정화 지연 =====
  final Set<String> _presentEntryReq   = <String>{}; // parking_requests 현재 포함
  final Set<String> _presentExitReq    = <String>{}; // departure_requests 현재 포함
  final Set<String> _presentExitUnpaid = <String>{}; // departure_completed(isLockedFee=false) 현재 포함

  final Map<String, Timer> _pendingCheck = <String, Timer>{};
  final Duration _settleDelay = const Duration(milliseconds: 800);

  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
        bool countInitialSnapshot = false, // ✅ (3)
      }) {
    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    bool _didEmitOnce = false; // ✅ (3) 기존 카운트 플래그
    final initKey = 'type=${type.firestoreValue}|area=$area|loc=${location ?? ""}';

    return query
        .snapshots()
    // Firestore 스트림 실패만 로깅 + 재전파
        .handleError((e, st) {
      // ignore: unawaited_futures
      DebugFirestoreLogger().log({
        'op': 'plates.stream.currentArea',
        'collection': 'plates',
        'filters': {
          'type': type.firestoreValue,
          'area': area,
          if (location != null && location.isNotEmpty) 'location': location,
        },
        'orderBy': {'field': 'request_time', 'descending': descending},
        'error': {
          'type': e.runtimeType.toString(),
          if (e is FirebaseException) 'code': e.code,
          'message': e.toString(),
        },
        'stack': st.toString(),
        'tags': ['plates', 'stream', 'currentArea', 'error'],
      }, level: 'error');

      Error.throwWithStackTrace(e, st);
    }).map((snapshot) {
      // ---------- (원 코드) 사용량 카운트 ----------
      if (!snapshot.metadata.hasPendingWrites) {
        final added = snapshot.docChanges.where((c) => c.type == DocumentChangeType.added).length;
        final modified = snapshot.docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        final n = added + modified;
        if (n > 0) {
          if (!_didEmitOnce) {
            _didEmitOnce = true;
            if (countInitialSnapshot) {
              // ignore: unawaited_futures
              /*UsageReporter.instance.report(
                area: area,
                action: 'read',
                n: n,
                source: 'PlateStreamService.streamToCurrentArea.onData',
              );*/
            }
          } else {
            /*UsageReporter.instance.report(
              area: area,
              action: 'read',
              n: n,
              source: 'PlateStreamService.streamToCurrentArea.onData',
            );*/
          }
        }
      }

      final isFirst = !_initedQueryKeys.contains(initKey);

      // ---------- ✅ modify 기반 전이 감지(보조) + 존재 집합 갱신 ----------
      if (!snapshot.metadata.hasPendingWrites) {
        if (isFirst) {
          // 초기 스냅샷: 캐시만 구축(added 전부) + 전이 로깅 스킵
          for (final c in snapshot.docChanges) {
            final data = c.doc.data();
            if (data == null) continue;
            final id = c.doc.id;
            final newType = (data['type'] ?? '') as String;
            _lastTypeCache[id] = newType;

            // 현재 존재 집합 구축
            if (type == PlateType.parkingRequests) _presentEntryReq.add(id);
            if (type == PlateType.departureRequests) _presentExitReq.add(id);
          }
          _initedQueryKeys.add(initKey);
        } else {
          for (final c in snapshot.docChanges) {
            final id = c.doc.id;
            final data = c.doc.data();

            // ===== 현재 존재 집합 갱신 + removed 처리(핵심) =====
            if (type == PlateType.parkingRequests) {
              if (c.type == DocumentChangeType.added || c.type == DocumentChangeType.modified) {
                _presentEntryReq.add(id);
              } else if (c.type == DocumentChangeType.removed) {
                _presentEntryReq.remove(id);
                _onEntryRequestRemoved(c);
              }
            }
            if (type == PlateType.departureRequests) {
              if (c.type == DocumentChangeType.added || c.type == DocumentChangeType.modified) {
                _presentExitReq.add(id);
              } else if (c.type == DocumentChangeType.removed) {
                _presentExitReq.remove(id);
                _onExitRequestRemoved(c);
              }
            }

            if (data == null) {
              // removed의 경우 data가 null일 수 있으므로 뒤 캐시 갱신은 스킵
              continue;
            }

            // ===== modify 기반 비교(보조) =====
            final newType = (data['type'] ?? '') as String;
            final prevType = _lastTypeCache[id];

            if (prevType == null) {
              _lastTypeCache[id] = newType; // 새로 들어온 문서
            } else {
              if (c.type == DocumentChangeType.modified && prevType != newType) {
                // plate 정보
                final plateNumber = (data['plate_number'] ?? '') as String;
                final areaStr     = (data['area'] ?? '') as String;

                // 내가 방금 만든 건이면(즉시 로컬 기록됨) 스트림 로깅 스킵
                final mine = LocalTransitionGuard.instance.hasRecentUserMark(
                  plateNumber: plateNumber,
                  area: areaStr,
                );

                // 전이 케이스: parking_requests|departure_requests → parking_completed
                final toCompleted  = (newType == PlateType.parkingCompleted.firestoreValue);
                final fromEntryReq = (prevType == PlateType.parkingRequests.firestoreValue);
                final fromExitReq  = (prevType == PlateType.departureRequests.firestoreValue);

                if (toCompleted && (fromEntryReq || fromExitReq) && !mine) {
                  final key = '$plateNumber|$areaStr|$prevType->$newType';
                  final now = DateTime.now();
                  final last = _recentLogged[key];
                  if (last == null || now.difference(last) >= _dedupeWindow) {
                    _recentLogged[key] = now;
                    final oldKo = fromEntryReq ? kStatusEntryRequest : kStatusExitRequest;
                    const newKo = kStatusEntryDone;

                    // Firestore 비용 증가 없음: 로컬(SQLite)만 기록
                    // ignore: unawaited_futures
                    ParkingCompletedLogger.instance.maybeLogCompleted(
                      plateNumber: plateNumber,
                      area: areaStr,
                      oldStatus: oldKo,
                      newStatus: newKo,
                    );
                  }
                }
              }
              // 마지막에 캐시 최신화
              _lastTypeCache[id] = newType;
            }
          }
        }
      }

      // ---------- (원 코드) 결과 파싱 ----------
      final results = snapshot.docs
          .map((doc) {
        try {
          return PlateModel.fromDocument(doc);
        } catch (e, st) {
          // ignore: unawaited_futures
          DebugFirestoreLogger().log({
            'op': 'plates.stream.parse',
            'collection': 'plates',
            'docPath': doc.reference.path,
            'docId': doc.id,
            'error': {
              'type': e.runtimeType.toString(),
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['plates', 'stream', 'parse', 'error'],
            'rawKeys': doc.data().keys.take(30).toList(),
          }, level: 'error');
          return null;
        }
      })
          .whereType<PlateModel>()
          .toList();

      return results;
    });
  }

  Query<Map<String, dynamic>> _buildPlateQuery({
    required PlateType type,
    required String area,
    String? location,
    bool descending = true,
  }) {
    Query<Map<String, dynamic>> query =
    _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    if (type == PlateType.parkingCompleted && location != null && location.isNotEmpty) {
      query = query.where('location', isEqualTo: location);
    }

    query = query.orderBy('request_time', descending: descending);

    return query;
  }

  // ✅ 출차완료(미정산) 스냅샷 스트림: 존재 집합 유지(전이 판정에 사용)
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots({
    required String area,
    bool descending = true,
    bool countInitialSnapshot = false, // ✅ (3)
  }) {
    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: false)
        .orderBy(PlateFields.requestTime, descending: descending);

    bool _didEmitOnceDeparture = false; // ✅ (3)

    return query.snapshots().handleError((e, st) {
      // ignore: unawaited_futures
      DebugFirestoreLogger().log({
        'op': 'plates.stream.departureUnpaid',
        'collection': 'plates',
        'filters': {
          'type': PlateType.departureCompleted.firestoreValue,
          'area': area,
          'isLockedFee': false,
        },
        'orderBy': {'field': PlateFields.requestTime, 'descending': descending},
        'error': {
          'type': e.runtimeType.toString(),
          if (e is FirebaseException) 'code': e.code,
          'message': e.toString(),
        },
        'stack': st.toString(),
        'tags': ['plates', 'stream', 'departureUnpaid', 'error'],
      }, level: 'error');

      Error.throwWithStackTrace(e, st);
    }).map((snapshot) {
      // ✅ 서버 확정 스냅샷만 집계 (로컬 보류 스냅샷 제외)
      if (!snapshot.metadata.hasPendingWrites) {
        for (final c in snapshot.docChanges) {
          final plateId = c.doc.id;
          if (c.type == DocumentChangeType.added || c.type == DocumentChangeType.modified) {
            _presentExitUnpaid.add(plateId);
          } else if (c.type == DocumentChangeType.removed) {
            _presentExitUnpaid.remove(plateId);
          }
        }

        final added = snapshot.docChanges.where((c) => c.type == DocumentChangeType.added).length;
        final modified = snapshot.docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        final n = added + modified;
        if (n > 0) {
          if (!_didEmitOnceDeparture) {
            _didEmitOnceDeparture = true;
            if (countInitialSnapshot) {
              /*UsageReporter.instance.report(
                area: area,
                action: 'read',
                n: n,
                source: 'PlateStreamService.departureUnpaidSnapshots.onData',
              );*/
            }
          } else {
            /*UsageReporter.instance.report(
              area: area,
              action: 'read',
              n: n,
              source: 'PlateStreamService.departureUnpaidSnapshots.onData',
            );*/
          }
        }
      }
      return snapshot;
    });
  }

  // ===== removed 이벤트 기반 전이 판정 =====

  void _onEntryRequestRemoved(DocumentChange<Map<String, dynamic>> c) {
    final id = c.doc.id;
    final data = c.doc.data();
    final parsed = _parsePlateId(id, data);
    final plateNumber = parsed.item1;
    final area = parsed.item2;

    // 내가 방금 만든 건이면(이미 로컬 기록) 스킵
    if (LocalTransitionGuard.instance.hasRecentUserMark(plateNumber: plateNumber, area: area)) return;

    // 잠시 후에도 어느 집합에도 없으면 → 입차완료로 간주
    _scheduleCheck('$id|entry_removed', () async {
      if (!_presentExitReq.contains(id) &&
          !_presentExitUnpaid.contains(id) &&
          !_presentEntryReq.contains(id)) {
        _logOnce(plateNumber, area, oldKo: kStatusEntryRequest, newKo: kStatusEntryDone);
      }
    });
  }

  void _onExitRequestRemoved(DocumentChange<Map<String, dynamic>> c) {
    final id = c.doc.id;
    final data = c.doc.data();
    final parsed = _parsePlateId(id, data);
    final plateNumber = parsed.item1;
    final area = parsed.item2;

    if (LocalTransitionGuard.instance.hasRecentUserMark(plateNumber: plateNumber, area: area)) return;

    // 미정산 출차완료로 가지도 않고, 다시 요청 큐에도 없으면 → 입차완료(회귀) 간주
    _scheduleCheck('$id|exit_removed', () async {
      final wentToUnpaid   = _presentExitUnpaid.contains(id);
      final backToEntryReq = _presentEntryReq.contains(id);
      final stillExitReq   = _presentExitReq.contains(id);

      if (!wentToUnpaid && !backToEntryReq && !stillExitReq) {
        _logOnce(plateNumber, area, oldKo: kStatusExitRequest, newKo: kStatusEntryDone);
      }
    });
  }

  void _scheduleCheck(String key, Future<void> Function() task) {
    _pendingCheck[key]?.cancel();
    _pendingCheck[key] = Timer(_settleDelay, () async {
      try {
        await task();
      } finally {
        _pendingCheck.remove(key);
      }
    });
  }

  // ✅ 여기! 반환타입을 레코드가 아니라 클래스 `_Pair`로.
  _Pair _parsePlateId(String plateId, Map<String, dynamic>? data) {
    // 데이터에 있으면 우선 사용
    if (data != null) {
      final pn = (data['plate_number'] ?? '') as String;
      final ar = (data['area'] ?? '') as String;
      if (pn.isNotEmpty && ar.isNotEmpty) return _Pair(pn, ar);
    }
    // 없으면 id로 분해
    final i = plateId.lastIndexOf('_');
    if (i > 0 && i < plateId.length - 1) {
      return _Pair(plateId.substring(0, i), plateId.substring(i + 1));
    }
    return _Pair(plateId, ''); // fallback
  }

  Future<void> _logOnce(
      String plateNumber,
      String area, {
        required String oldKo,
        required String newKo,
      }) async {
    final rkey = '$plateNumber|$area|$oldKo->$newKo';
    final now = DateTime.now();
    final last = _recentLogged[rkey];
    if (last != null && now.difference(last) < _dedupeWindow) return;
    _recentLogged[rkey] = now;

    // Firestore 비용 증가 없음: 로컬(SQLite)만 write
    // ignore: unawaited_futures
    ParkingCompletedLogger.instance.maybeLogCompleted(
      plateNumber: plateNumber,
      area: area,
      oldStatus: oldKo,
      newStatus: newKo,
    );
  }
}

// 간단 튜플
class _Pair {
  final String item1;
  final String item2;
  _Pair(this.item1, this.item2);
}
