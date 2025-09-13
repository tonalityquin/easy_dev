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

  // 첫 스냅샷 묵음 처리
  static bool _initialEmissionDone = false;

  // 기준 시각/상태
  static DateTime _startTime = DateTime.now().toUtc();
  static int _listenSeq = 0;
  static String? _currentArea;

  // 출차 완료 반복
  static const int _completionRepeat = 2;
  static const Duration _completionRepeatGap = Duration(milliseconds: 700);

  // ✅ 유저 선택 필터(기본: 전부 on)
  static TtsUserFilters _filters = TtsUserFilters.defaults();

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
    // 오너십 체크는 유지하고 싶다면 여기(TtsOwnership)에서 수행
    // force가 true면 바로 진행
    await _ensureFirebaseInThisIsolate();

    _listenSeq += 1;

    await _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();
    _initialEmissionDone = false;

    _startTime = DateTime.now().toUtc();
    _currentArea = currentArea;

    _log('▶ START listen area="$_currentArea" since=$_startTime filters=${_filters.toMap()}');

    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ];
    _log('monitor types=$typesToMonitor');

    try {
      final query = FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: currentArea)
          .where('type', whereIn: typesToMonitor);

      _subscription = query.snapshots().listen((snapshot) {
        final isFirstEmission = !_initialEmissionDone;
        if (isFirstEmission) {
          _initialEmissionDone = true;
        }

        final dc = snapshot.docChanges.length;
        final total = snapshot.docs.length;
        _log('snapshot: total=$total changes=$dc firstEmission=$isFirstEmission');

        for (final change in snapshot.docChanges) {
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
            final spokenTail = _convertToKoreanDigits(tail);

            _log('change: id=$docId type=${change.type} newType=$newType prevType=$prevType reqTime=${requestTime?.toDate()}');

            bool didSpeak = false;

            // 필터 미적용 타입은 즉시 skip
            if (!_isEnabledForType(newType)) {
              _log('skip by filter: type=$newType id=$docId');
              _lastTypes[docId] = newType; // 상태는 갱신
              continue;
            }

            if (change.type == DocumentChangeType.added) {
              final shouldSpeak = !isFirstEmission ? true : _isNewByRequestTime(requestTime);

              if (shouldSpeak && _dedup(docId)) {
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
                _log('skip(added): ${isFirstEmission ? 'initial snapshot old' : 'dedup'} id=$docId');
              }
            } else if (change.type == DocumentChangeType.modified) {
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
      }, onError: (e, st) {
        _log('STREAM ERROR: $e\n$st');
      }, onDone: () {
        _log('STREAM DONE for area=$_currentArea');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st');
    }
  }

  static bool _isNewByRequestTime(Timestamp? requestTime) {
    if (requestTime == null) return true;
    final reqUtc = requestTime.toDate().toUtc();
    return reqUtc.isAfter(_startTime.subtract(const Duration(seconds: 3)));
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
  }

  static String _convertToKoreanDigits(String digits) {
    const koreanDigits = {
      '0': '공', '1': '하나', '2': '둘', '3': '삼', '4': '사',
      '5': '오', '6': '육', '7': '칠', '8': '팔', '9': '구',
    };
    return digits.split('').map((d) => koreanDigits[d] ?? d).join(', ');
  }
}
