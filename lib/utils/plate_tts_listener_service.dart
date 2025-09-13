// lib/utils/plate_tts_listener_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ 안전장치
import '../../enums/plate_type.dart';
import '../screens/dev_package/debug_package/tts_local_log.dart';
import 'tts_manager.dart';
import 'tts_ownership.dart';


String _ts() => DateTime.now().toIso8601String();

class PlateTtsListenerService {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  static final Map<String, String?> _lastTypes = {};
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
        debugPrint('[PLATE_TTS][${_ts()}] Firebase.initializeApp() done (isolate)');
      }
    } catch (e, st) {
      debugPrint('[PLATE_TTS][${_ts()}] Firebase init error: $e\n$st');
      // ❗ 중요: 앱/FG 이솔레이트 외에서 Firebase 초기화 실패
      await TtsLocalLog.error(
        'TTS.firebaseInit',
        'Firebase initialize failed in listener isolate',
        data: {'error': '$e', 'stack': '$st'},
      );
    }
  }

  static void _log(String msg) => debugPrint('[PLATE_TTS][$_listenSeq][${_ts()}] $msg');

  static Future<void> _startListening(String currentArea, {bool force = false}) async {
    // 앱 이솔레이트에서는 owner=app일 때만, FG 이솔레이트는 force=true로 강제 시작
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
    _startTime = DateTime.now().toUtc(); // 기준 시각
    _currentArea = currentArea;

    _log('▶ START listen area="$_currentArea" since=$_startTime');

    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
    ];
    _log('monitor types=$typesToMonitor');

    try {
      final query = FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: currentArea)
          .where('type', whereIn: typesToMonitor);

      _subscription = query.snapshots().listen((snapshot) {
        final dc = snapshot.docChanges.length;
        final total = snapshot.docs.length;
        _log('snapshot: total=$total changes=$dc');

        for (final change in snapshot.docChanges) {
          try {
            final doc = change.doc;
            final data = doc.data();
            if (data == null) {
              _log('(doc null) id=${doc.id} → skip');
              // ❗ 중요: null 문서 데이터
              TtsLocalLog.error(
                'TTS.listener',
                'doc data is null',
                data: {'id': doc.id, 'area': _currentArea},
              );
              continue;
            }

            final docId = doc.id;
            final newType = data['type'];
            final location = (data['location'] ?? '') as String;
            final plateNumber = (data['plate_number'] ?? '') as String;
            final Timestamp? requestTime = data['request_time'];
            final prevType = _lastTypes[docId];

            _lastTypes[docId] = newType;

            final tailPlate = plateNumber.length >= 4
                ? plateNumber.substring(plateNumber.length - 4)
                : plateNumber;
            final spokenTail = _convertToKoreanDigits(tailPlate);

            _log('change: id=$docId type=${change.type} newType=$newType prevType=$prevType '
                'reqTime=${requestTime?.toDate()}');

            if (change.type != DocumentChangeType.added) {
              _log('ignore changeType=${change.type} id=$docId');
              continue;
            }

            // ✅ 신규 판정: request_time이 없으면 “신규”로 간주(안전),
            // 있으면 리스닝 시작시각 -3초 버퍼 이후만 신규 처리
            bool isNew = true;
            if (requestTime != null) {
              final reqUtc = requestTime.toDate().toUtc();
              isNew = reqUtc.isAfter(_startTime.subtract(const Duration(seconds: 3)));
            }
            if (!isNew) {
              _log('skip: old doc id=$docId (req=${requestTime?.toDate()}, since=$_startTime)');
              continue;
            }

            final isDeparture = newType == PlateType.departureRequests.firestoreValue;
            if (newType == PlateType.parkingRequests.firestoreValue) {
              final utter = '입차 요청';
              _log('SPEAK: $utter (id=$docId, area=$_currentArea)');
              _safeSpeak(utter, docId: docId, area: _currentArea, type: '$newType');
            } else if (isDeparture) {
              final utter = '출차 요청 $spokenTail, $location';
              _log('SPEAK: $utter (id=$docId, area=$_currentArea)');
              _safeSpeak(utter, docId: docId, area: _currentArea, type: '$newType');
            } else {
              _log('skip: added but unhandled type=$newType id=$docId');
              // ❗ 중요: 알 수 없는 타입
              TtsLocalLog.error(
                'TTS.listener',
                'unhandled type',
                data: {'id': docId, 'area': _currentArea, 'type': '$newType'},
              );
            }
          } catch (e, st) {
            _log('ERROR in change loop: $e\n$st');
            // ❗ 중요: 개별 change 처리 중 예외
            TtsLocalLog.error(
              'TTS.listener',
              'error in change loop',
              data: {'area': _currentArea, 'error': '$e', 'stack': '$st'},
            );
          }
        }
      }, onError: (e, st) {
        _log('STREAM ERROR: $e\n$st');
        // ❗ 중요: 스냅샷 스트림 에러
        TtsLocalLog.error(
          'TTS.listener',
          'stream error',
          data: {'area': _currentArea, 'error': '$e', 'stack': '$st'},
        );
      }, onDone: () {
        _log('STREAM DONE for area=$_currentArea');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st');
      // ❗ 중요: 리스너 초기화 실패
      TtsLocalLog.error(
        'TTS.listener',
        'attach snapshots failed',
        data: {'area': _currentArea, 'error': '$e', 'stack': '$st'},
      );
    }
  }

  static Future<void> _safeSpeak(
      String text, {
        String? docId,
        String? area,
        String? type,
      }) async {
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
      // ❗ 중요: 발화 실패
      TtsLocalLog.error(
        'TTS.speak',
        'speak failed',
        data: {'id': docId ?? '', 'area': area ?? '', 'type': type ?? '', 'error': '$e', 'stack': '$st'},
      );
    }
  }

  static void stop() {
    if (_subscription != null) {
      _log('▶ STOP listen (area=$_currentArea)');
    }
    _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _currentArea = null;
  }

  static String _convertToKoreanDigits(String digits) {
    const koreanDigits = {
      '0': '공', '1': '하나', '2': '둘', '3': '삼', '4': '사',
      '5': '오', '6': '육', '7': '칠', '8': '팔', '9': '구',
    };
    return digits.split('').map((d) => koreanDigits[d] ?? d).join(', ');
  }
}
