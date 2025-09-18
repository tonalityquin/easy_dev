// lib/utils/tts/plate_tts_listener_service.dart
//
// 변경 요약:
// - (B) 서버 기준선 1건 조회 → request_time & __name__(docId) 기준으로 startAfter 커서 설정
// - 초기 스냅샷부터 백로그 문서가 결과에 포함되지 않도록 보장
// - read 카운터(추정) 추가: baseline 조회 / 초기 스냅샷 / 이후 added/modified/removed
//
// 필요 인덱스(예): area + type(whereIn) + request_time + __name__ (ASC)
// 에러 메시지의 "Create index" 링크로 생성하세요.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../enums/plate_type.dart';
import 'tts_manager.dart';
// ⬇️ 유저 필터
import 'tts_user_filters.dart';

String _ts() => DateTime.now().toIso8601String();

class PlateTtsListenerService {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  // 타입 전환 감지용
  static final Map<String, String?> _lastTypes = {};

  // 짧은 디듀프
  static final Map<String, DateTime> _lastSpokenAt = {};
  static const Duration _speakDedupWindow = Duration(seconds: 2);

  // 첫 스냅샷 여부
  static bool _initialEmissionDone = false;

  // 기준 상태
  static int _listenSeq = 0;
  static String? _currentArea;

  // 서버 기준선(해당 지역 최신 1건)
  static Timestamp? _baselineTs;
  static String? _baselineDocId;

  // 출차 완료 반복
  static const int _completionRepeat = 2;
  static const Duration _completionRepeatGap = Duration(milliseconds: 700);

  // ✅ 유저 선택 필터(기본: 전부 on)
  static TtsUserFilters _filters = TtsUserFilters.defaults();

  // ===== Read 추정 카운터 =====
  static int _readsBaselineDocs = 0;          // 기준선 조회로 읽힌 문서 수(최대 1)
  static int _readsInitialSnapshotDocs = 0;   // 리스너 초기 스냅샷에서 전달된 문서 수
  static int _readsAdded = 0;                 // 이후 added 이벤트 read 수
  static int _readsModified = 0;              // 이후 modified 이벤트 read 수
  static int _readsRemoved = 0;               // 이후 removed 이벤트 read 수

  static void _resetReadCounters() {
    _readsBaselineDocs = 0;
    _readsInitialSnapshotDocs = 0;
    _readsAdded = 0;
    _readsModified = 0;
    _readsRemoved = 0;
  }

  static int get _readsTotal =>
      _readsBaselineDocs +
          _readsInitialSnapshotDocs +
          _readsAdded +
          _readsModified +
          _readsRemoved;

  static void _printReadSummary({String prefix = 'READ SUMMARY'}) {
    _log('$prefix: baseline=$_readsBaselineDocs, '
        'initial=$_readsInitialSnapshotDocs, '
        'added=$_readsAdded, modified=$_readsModified, removed=$_readsRemoved '
        '→ total=$_readsTotal');
  }

  static void updateFilters(TtsUserFilters f) {
    _filters = f;
    _log('filters updated: ${_filters.toMap()}');
  }

  static bool _isEnabledForType(String? type) {
    if (type == null) return false;
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

  static Future<void> _startListening(String currentArea, {bool force = false}) async {
    await _ensureFirebaseInThisIsolate();

    _listenSeq += 1;

    await _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();
    _initialEmissionDone = false;
    _baselineTs = null;
    _baselineDocId = null;
    _resetReadCounters();

    _currentArea = currentArea;

    _log('▶ START listen area="$_currentArea" filters=${_filters.toMap()}');
    _printReadSummary(prefix: 'READ SUMMARY (init)');

    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ];
    _log('monitor types=$typesToMonitor');

    try {
      // 1) 서버 기준선 1건 조회 (최신 1건)
      await _fetchBaseline(currentArea, typesToMonitor);

      // 2) 기준선 이후만 구독
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: currentArea)
          .where('type', whereIn: typesToMonitor)
      // 오름차순 정렬 (커서와 동일 순서 중요)
          .orderBy('request_time')
          .orderBy(FieldPath.documentId);

      if (_baselineTs != null && _baselineDocId != null) {
        query = query.startAfter([_baselineTs, _baselineDocId]);
        _log('apply startAfter([$_baselineTs, $_baselineDocId])');
      } else {
        _log('no baseline (empty collection or area/type has no docs) → start from beginning');
      }

      _subscription = query.snapshots().listen((snapshot) {
        final isFirstEmission = !_initialEmissionDone;
        if (isFirstEmission) {
          _initialEmissionDone = true;
        }

        final dc = snapshot.docChanges.length;
        final total = snapshot.docs.length;
        _log('snapshot: total=$total changes=$dc firstEmission=$isFirstEmission');

        for (final change in snapshot.docChanges) {
          // ===== Read 카운터(추정): 초기 스냅샷이면 initial++, 이후는 타입별로 구분 =====
          if (isFirstEmission) {
            _readsInitialSnapshotDocs += 1;
            _log('READ++ (initial snapshot) → $_readsInitialSnapshotDocs');
          } else {
            if (change.type == DocumentChangeType.added) {
              _readsAdded += 1;
              _log('READ++ (added) → $_readsAdded');
            } else if (change.type == DocumentChangeType.modified) {
              _readsModified += 1;
              _log('READ++ (modified) → $_readsModified');
            } else if (change.type == DocumentChangeType.removed) {
              _readsRemoved += 1;
              _log('READ++ (removed) → $_readsRemoved');
            }
          }

          try {
            final doc = change.doc;
            final data = doc.data();
            if (data == null) {
              _log('(doc null) id=${doc.id} → skip');
              continue;
            }

            final docId = doc.id;
            final newType = data['type'] as String?;
            final location = (data['location'] ?? '') as String;
            final plateNumber = (data['plate_number'] ?? '') as String;
            final Timestamp? requestTime = data['request_time'] as Timestamp?;
            final prevType = _lastTypes[docId];

            final tail = plateNumber.length >= 4
                ? plateNumber.substring(plateNumber.length - 4)
                : plateNumber;
            final spokenTail = _convertToKoreanDigits(_digitsOnly(tail));

            _log('change: id=$docId type=${change.type} newType=$newType prevType=$prevType reqTime=${requestTime?.toDate()}');

            bool didSpeak = false;

            // 필터 미적용 타입은 즉시 skip
            if (!_isEnabledForType(newType)) {
              _log('skip by filter: type=$newType id=$docId');
              _lastTypes[docId] = newType; // 상태는 갱신
              continue;
            }

            if (change.type == DocumentChangeType.added) {
              // 쿼리 자체가 baseline 이후만 주므로 별도 신규성 판정 불필요
              if (_dedup(docId)) {
                if (newType == PlateType.parkingRequests.firestoreValue) {
                  final utter = '입차 요청';
                  _log('SPEAK(added): $utter (id=$docId, area=$_currentArea)');
                  _safeSpeak(utter);
                  didSpeak = true;
                } else if (newType == PlateType.departureRequests.firestoreValue) {
                  final utter = '출차 요청 $spokenTail, $location';
                  _log('SPEAK(added): $utter (id=$docId, area=$_currentArea)');
                  _safeSpeak(utter);
                  didSpeak = true;
                } else if (newType == PlateType.departureCompleted.firestoreValue) {
                  final utter = '$spokenTail, 출차 완료 되었습니다.';
                  _log('SPEAK(added×$_completionRepeat): $utter (id=$docId, area=$_currentArea)');
                  _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                  didSpeak = true;
                }
              } else {
                _log('skip(added): dedup id=$docId');
              }
            } else if (change.type == DocumentChangeType.modified) {
              // 타입 변경에 대해서만 낭독 (필요 시 보조 시계/로그로 더 보수적 판단 가능)
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
                  final utter = '$spokenTail, 출차 완료 되었습니다.';
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
              // 후처리 여지
            }
          } catch (e, st) {
            _log('ERROR in change loop: $e\n$st');
          }
        }

        _printReadSummary(prefix: 'READ SUMMARY (tick)');
      }, onError: (e, st) {
        _log('STREAM ERROR: $e\n$st');
      }, onDone: () {
        _log('STREAM DONE for area=$_currentArea');
        _printReadSummary(prefix: 'READ SUMMARY (done)');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st');
      _printReadSummary(prefix: 'READ SUMMARY (start-error)');
    }
  }

  static Future<void> _fetchBaseline(String area, List<String> typesToMonitor) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: area)
          .where('type', whereIn: typesToMonitor)
          .orderBy('request_time', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(1)
          .get();

      _readsBaselineDocs += qs.docs.length; // 최대 1
      if (qs.docs.isEmpty) {
        _baselineTs = null;
        _baselineDocId = null;
        _log('baseline: (none)');
      } else {
        final d = qs.docs.first;
        _baselineTs = d.data()['request_time'] as Timestamp?;
        _baselineDocId = d.id;
        _log('baseline: ts=${_baselineTs?.toDate().toUtc()} id=$_baselineDocId (reads+${qs.docs.length})');
      }
      _printReadSummary(prefix: 'READ SUMMARY (after baseline)');
    } catch (e, st) {
      _log('baseline fetch error: $e\n$st');
    }
  }

  static bool _dedup(String docId) {
    final now = DateTime.now().toUtc();
    final last = _lastSpokenAt[docId];
    if (last != null && now.difference(last) < _speakDedupWindow) {
      _log('dedup: suppress speak for $docId within $_speakDedupWindow');
      return false;
    }
    _lastSpokenAt[docId] = now;
    return true;
  }

  static Future<void> _safeSpeak(String text) async {
    try {
      await TtsManager.speak(
        text,
        language: 'ko-KR',
        rate: 0.5,
        volume: 1.0,
        pitch: 1.0,
        preferGoogleOnAndroid: true,
        openPlayStoreIfMissing: true,
      );
    } catch (e, st) {
      _log('TTS ERROR: $e\n$st');
    }
  }

  static Future<void> _speakRepeated(String text, {int times = 1, Duration gap = Duration.zero}) async {
    for (var i = 0; i < times; i++) {
      await _safeSpeak(text);
      if (i < times - 1 && gap > Duration.zero) {
        await Future.delayed(gap);
      }
    }
  }

  static void stop() {
    if (_subscription != null) {
      _log('▶ STOP listen (area=$_currentArea)');
    }
    _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();
    _currentArea = null;
    _initialEmissionDone = false;

    _printReadSummary(prefix: 'READ SUMMARY (stop)');
  }

  static String _convertToKoreanDigits(String digits) {
    const koreanDigits = {
      '0': '공',
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
