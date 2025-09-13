// lib/utils/plate_tts_listener_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../enums/plate_type.dart';
import 'tts_manager.dart';
import 'tts_ownership.dart';

String _ts() => DateTime.now().toIso8601String();

class PlateTtsListenerService {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  // 직전 type 기억(타입 전환 감지)
  static final Map<String, String?> _lastTypes = {};

  // 직전 발화 시각(디듀프)
  static final Map<String, DateTime> _lastSpokenAt = {};
  static const Duration _speakDedupWindow = Duration(seconds: 2);

  // 첫 스냅샷 묵음 처리용 플래그
  static bool _initialEmissionDone = false;

  // 기준 시각(로그용), area/seq
  static DateTime _startTime = DateTime.now().toUtc();
  static int _listenSeq = 0;
  static String? _currentArea;

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
    // 앱 이솔레이트는 owner=app일 때만, FG 이솔레이트는 force=true로 강제 시작
    if (!force) {
      final isApp = await TtsOwnership.isAppOwner();
      if (!isApp) {
        _log('skip start in app (owner=foreground)');
        return;
      }
    }

    await _ensureFirebaseInThisIsolate();

    _listenSeq += 1;

    await _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();
    _initialEmissionDone = false;

    _startTime = DateTime.now().toUtc(); // 기준 시각(로그)
    _currentArea = currentArea;

    _log('▶ START listen area="$_currentArea" since=$_startTime');

    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,   // 'parking_requests'
      PlateType.departureRequests.firestoreValue, // 'departure_requests'
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
            final inMonitored = newType != null && typesToMonitor.contains(newType);

            final tailPlate = plateNumber.length >= 4
                ? plateNumber.substring(plateNumber.length - 4)
                : plateNumber;
            final spokenTail = _convertToKoreanDigits(tailPlate);

            _log('change: id=$docId type=${change.type} newType=$newType '
                'prevType=$prevType reqTime=${requestTime?.toDate()}');

            bool didSpeak = false;

            // 1) 'added'
            if (change.type == DocumentChangeType.added && inMonitored) {
              // 첫 스냅샷: request_time 기준(버퍼 3s)으로만 "신규" 판정 → 묵음 방지
              // 이후 스냅샷: 시간과 무관하게 "신규"로 간주(쿼리 재진입/타 디바이스 변경 포함)
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
                }
              } else {
                _log('skip(added): ${isFirstEmission ? 'initial snapshot old' : 'dedup'} id=$docId');
              }

              // 2) 'modified'에서 type 전환 감지 → 시간 무관 발화
            } else if (change.type == DocumentChangeType.modified && inMonitored) {
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
                }
              } else {
                _log('ignore modified (no type change or dedup) id=$docId');
              }

            } else {
              _log('ignore changeType=${change.type} id=$docId');
            }

            // 마지막에 prevType 갱신
            _lastTypes[docId] = newType;

            if (didSpeak) {
              // 필요 시: 추가 후처리 훅(예: 로컬/원격 로깅)
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

  // 초기 스냅샷에서만 사용하는 "신규" 판정 (시간 기준 + 3초 버퍼)
  static bool _isNewByRequestTime(Timestamp? requestTime) {
    if (requestTime == null) return true;
    final reqUtc = requestTime.toDate().toUtc();
    return reqUtc.isAfter(_startTime.subtract(const Duration(seconds: 3)));
  }

  // 짧은 디듀프 창으로 중복발화 억제
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
