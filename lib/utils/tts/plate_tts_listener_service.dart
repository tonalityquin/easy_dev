// lib/utils/tts/plate_tts_listener_service.dart
//
// 변경 요약 (updatedAt 커서/윈도우 A안 + 컴파일 에러 수정):
// - 서버 기준선 1건 조회 후 ✨ startAfter(updatedAt, __name__) 커서 적용
// - ✨ 첫 스냅샷 무음 규칙 제거(커서가 초기 잡음을 제거하므로 안전)
// - setEnabled: Future<void>로 변경(호출부 await 가능)
// - updateFilters 추가(저장 없이 인메모리 반영)
// - Firestore fromCache 로깅, 미사용 카운터 정리
//
// 주의: 쿼리 정렬 순서와 startAfter 필드 순서는 반드시 동일해야 함.
// 필요한 인덱스(예): area + type + updatedAt + __name__ (ASC/ASC/ASC/ASC)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../enums/plate_type.dart';
import '../tts/tts_manager.dart';
import '../tts/tts_user_filters.dart';

class PlateTtsListenerService {
  // 마스터 토글
  static bool _enabled = true;

  /// 저장 없이 즉시 in-memory만 바꾸고 싶으면 [updateFilters] 사용
  static Future<void> setFilters(TtsUserFilters filters) async {
    _filters = filters;
    await _filters.save();
    _log('filters saved: $filters');
  }

  /// 호출부에서 await로 사용하므로 반환형을 Future로 변경
  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    _log('master enabled=$_enabled');
  }

  /// 저장 없이 앱/FG isolate에 바로 반영하고 싶을 때 사용
  static void updateFilters(TtsUserFilters filters) {
    _filters = filters;
    _log('filters updated (in-memory): $filters');
  }

  // 리스닝 핸들
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  // 타입 전환 감지용
  static final Map<String, String?> _lastTypes = {};

  // 짧은 디듀프(문서별 일정 시간 내 중복 발화 방지)
  static final Map<String, DateTime> _lastSpokenAt = {};

  // 기준 상태
  static int _listenSeq = 0;
  static String? _currentArea;

  // 서버 기준선(해당 지역 최신 1건, updatedAt 기준)
  static Timestamp? _baselineUpdatedAt;
  static String? _baselineDocId;

  // 출차 완료 반복
  static const int _completionRepeat = 2;
  static const Duration _completionRepeatGap = Duration(milliseconds: 700);

  // ✅ 유저 선택 필터(기본: 전부 on)
  static TtsUserFilters _filters = TtsUserFilters.defaults();

  // (옵션) 기준선이 전혀 없을 때 참고용으로만 쓰는 초기 포함 윈도우
  static Duration _initialWindow = const Duration(minutes: 30);

  static Future<void> setInitialWindow(Duration d) async {
    _initialWindow = d;
    _log('initialWindow=${_initialWindow.inMinutes}m');
  }

  // speak 디듀프 윈도우
  static Duration _speakDedupWindow = const Duration(seconds: 2);

  static Future<void> setSpeakDedupWindow(Duration d) async {
    _speakDedupWindow = d;
    _log('speakDedupWindow=${_speakDedupWindow.inMilliseconds}ms');
  }

  static bool _isEnabledForType(String? type) {
    if (type == null) return false;
    if (!_enabled) return false; // ✅ 마스터 가드: OFF면 모두 스킵
    if (type == PlateType.parkingRequests.firestoreValue) return _filters.parking;
    if (type == PlateType.departureRequests.firestoreValue) return _filters.departure;
    if (type == PlateType.departureCompleted.firestoreValue) return _filters.completed;
    return false;
  }

  static void start(String currentArea, {bool force = false}) {
    Future.microtask(() => _startListening(currentArea, force: force));
  }

  static Future<void> _ensureFirebaseInThisIsolate() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
        _log('Firebase.initializeApp() done (isolate)');
      }
    } catch (e, st) {
      _log('Firebase init error: $e\n$st');
    }
  }

  static void _log(String msg) => debugPrint('[PLATE_TTS][$_listenSeq][${_ts()}] $msg');
  static String _ts() => DateTime.now().toIso8601String();

  static Future<void> stop() async {
    if (_subscription != null) {
      _log('▶ STOP listen (area=$_currentArea)');
    }
    await _subscription?.cancel();
    _subscription = null;

    _currentArea = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();

    _baselineUpdatedAt = null;
    _baselineDocId = null;
  }

  static Future<void> _startListening(String currentArea, {bool force = false}) async {
    await _ensureFirebaseInThisIsolate();

    _listenSeq += 1;

    await _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();

    _baselineUpdatedAt = null;
    _baselineDocId = null;

    _currentArea = currentArea;

    // 모니터링할 타입
    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ];

    try {
      // 1) 기준선(앵커) 확보 — 최신 updatedAt DESC, __name__ DESC
      await _fetchBaseline(currentArea, typesToMonitor);

      // 2) 리스닝 쿼리 구성 (updatedAt ASC, __name__ ASC)
      //    ✨ startAfter([_baselineUpdatedAt, _baselineDocId])로 첫 스냅샷도 '기준선 이후'만 수신
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: currentArea)
          .where('type', whereIn: typesToMonitor)
          .orderBy('updatedAt')
          .orderBy(FieldPath.documentId);

      if (_baselineUpdatedAt != null && _baselineDocId != null) {
        query = query.startAfter([_baselineUpdatedAt, _baselineDocId]);
        _log('apply cursor(startAfter): ts=${_baselineUpdatedAt?.toDate().toUtc()} id=$_baselineDocId');
      } else {
        // 기준선이 없으면 — 문서 0건 상황.
        // (옵션) 여기서 where(updatedAt >= now - _initialWindow) 하한을 추가할 수도 있음.
        _log('no baseline available → start without cursor');
      }

      _resetReadCounters();
      _log('▶ START listen (area=$currentArea)');

      _subscription = query.snapshots().listen((snapshot) async {
        // Firestore 로컬 보류 스냅샷은 과금 기준이 아님 → 건너뜀
        if (snapshot.metadata.hasPendingWrites) {
          _log('skip local pendingWrites snapshot');
          return;
        }

        final bool isFromCache = snapshot.metadata.isFromCache;
        final docChanges = snapshot.docChanges;

        if (docChanges.isEmpty) {
          _readsEmptySnapshots += 1;
          return;
        }

        // 통계
        _readsTotal += 1;
        _readsAdded += docChanges.where((c) => c.type == DocumentChangeType.added).length;
        _readsModified += docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        _readsRemoved += docChanges.where((c) => c.type == DocumentChangeType.removed).length;

        _log('snapshot changes=${docChanges.length}, fromCache=$isFromCache');

        // ✨ 첫 스냅샷도 커서 이후만 오므로 발화 OK

        for (final change in docChanges) {
          final doc = change.doc;
          final data = doc.data();
          if (data == null) continue;

          final docId = doc.id;
          final newType = data['type'] as String?;
          final location = (data['location'] as String?) ?? '';
          final plateNumber = (data['plate_number'] as String?) ?? '';
          final tail = plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;
          final spokenTail = _convertToKoreanDigits(_digitsOnly(tail));

          bool didSpeak = false;

          // 필터 미적용 타입은 즉시 skip
          if (!_isEnabledForType(newType)) {
            _log('skip by filter: type=$newType id=$docId');
            _lastTypes[docId] = newType; // 상태는 갱신
            continue;
          }

          if (change.type == DocumentChangeType.added) {
            // Added는 쿼리 집합에 '처음' 들어온 것 — startAfter 덕에 기준선 이후만 들어옴
            if (_dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청'; // 필요시 '입차 요청 $spokenTail, $location'로 확장 가능
                _log('SPEAK(added): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log('SPEAK(added): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureCompleted.firestoreValue) {
                final utter = '출차 완료 $spokenTail, $location';
                _log('SPEAK(added×$_completionRepeat): $utter (id=$docId, area=$_currentArea)');
                _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              } else {
                _log('ignore added: type=$newType id=$docId');
              }
            } else {
              _log('dedup skip added id=$docId');
            }
          } else if (change.type == DocumentChangeType.modified) {
            // ✨ 타입 변경에 대해서만 발화
            final prevType = _lastTypes[docId];
            final typeChanged = prevType != null && prevType != newType;

            if (typeChanged && _dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청';
                _log('SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log('SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureCompleted.firestoreValue) {
                final utter = '출차 완료 $spokenTail, $location';
                _log('SPEAK(modified→type change×$_completionRepeat): $utter (id=$docId, area=$_currentArea)');
                _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              }
            } else {
              _log('ignore modified (no type change or dedup) id=$docId');
            }
          } else {
            _log('ignore changeType=${change.type} id=$docId');
          }

          _lastTypes[docId] = newType;

          if (didSpeak) {
            // 후처리 훅(필요 시 확장)
          }
        }
      }, onError: (e, st) {
        _log('listen error: $e\n$st');
        _printReadSummary(prefix: 'READ SUMMARY (listen-error)');
      }, onDone: () {
        _log('listen done');
        _printReadSummary(prefix: 'READ SUMMARY (done)');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st');
      _printReadSummary(prefix: 'READ SUMMARY (start-error)');
    }
  }

  static Future<void> _fetchBaseline(
      String area,
      List<String> typesToMonitor,
      ) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: area)
          .where('type', whereIn: typesToMonitor)
          .orderBy('updatedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        _baselineUpdatedAt = null;
        _baselineDocId = null;
        _log('baseline(updatedAt): (none)');
      } else {
        final d = qs.docs.first;
        _baselineUpdatedAt = d.data()['updatedAt'] as Timestamp?;
        _baselineDocId = d.id;
        _log('baseline(updatedAt): ts=${_baselineUpdatedAt?.toDate().toUtc()} id=$_baselineDocId (reads+${qs.docs.length})');
      }
      _printReadSummary(prefix: 'READ SUMMARY (after baseline)');
    } catch (e, st) {
      _log('baseline fetch error: $e\n$st');
    }
  }

  // ===== 통계 및 유틸 =====
  static int _readsTotal = 0;
  static int _readsAdded = 0;
  static int _readsModified = 0;
  static int _readsRemoved = 0;
  static int _readsEmptySnapshots = 0;

  static void _resetReadCounters() {
    _readsTotal = 0;
    _readsAdded = 0;
    _readsModified = 0;
    _readsRemoved = 0;
    _readsEmptySnapshots = 0;
  }

  static void _printReadSummary({required String prefix}) {
    _log('$prefix: total=$_readsTotal, added=$_readsAdded, modified=$_readsModified, '
        'removed=$_readsRemoved, emptySnapshots=$_readsEmptySnapshots');
  }

  static bool _dedup(String docId) {
    final now = DateTime.now();
    final last = _lastSpokenAt[docId];
    if (last != null && now.difference(last) < _speakDedupWindow) {
      return false;
    }
    _lastSpokenAt[docId] = now;
    return true;
  }

  static Future<void> _safeSpeak(String text) async {
    try {
      await TtsManager.speak(text);
    } catch (e) {
      _log('TTS error: $e');
    }
  }

  static Future<void> _speakRepeated(String text, {int times = 2, Duration gap = Duration.zero}) async {
    for (var i = 0; i < times; i++) {
      await _safeSpeak(text);
      if (i < times - 1 && gap > Duration.zero) {
        await Future.delayed(gap);
      }
    }
  }

  static String _convertToKoreanDigits(String digits) {
    const koreanDigits = {
      '0': '영',
      '1': '하나',
      '2': '둘',
      '3': '삼',
      '4': '사',
      '5': '오',
      '6': '육',
      '7': '칠',
      '8': '팔',
      '9': '구',
    };
    return digits.split('').map((d) => koreanDigits[d] ?? d).join(', ');
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
}
