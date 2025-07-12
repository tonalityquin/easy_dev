import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../enums/plate_type.dart';

class PlateTtsListenerService {
  static StreamSubscription? _subscription;
  static final Map<String, String?> _lastTypes = {};
  static DateTime _startTime = DateTime.now();

  static void start(String currentArea) {
    Future.microtask(() => _startListening(currentArea));
  }

  static void _startListening(String currentArea) {
    _subscription?.cancel();
    _lastTypes.clear();
    _startTime = DateTime.now();

    debugPrint('[TTS] 감지 시작: $currentArea @ $_startTime');

    final typesToMonitor = [
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
    ];

    _subscription = FirebaseFirestore.instance
        .collection('plates')
        .where('area', isEqualTo: currentArea)
        .where('type', whereIn: typesToMonitor)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        final docId = doc.id;
        final newType = data['type'];
        final location = data['location'];
        final plateNumber = data['plate_number'] ?? '';
        final Timestamp? requestTime = data['request_time'];
        final prevType = _lastTypes[docId];

        _lastTypes[docId] = newType;

        final tailPlate = plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;
        final spokenTail = _convertToKoreanDigits(tailPlate);

        debugPrint('[TTS] DEBUG ▶ changeType: ${change.type}, newType: $newType, prevType: $prevType');

        if (change.type == DocumentChangeType.added) {
          final isDeparture = newType == PlateType.departureRequests.firestoreValue;

          if (requestTime == null) {
            debugPrint('[TTS] 무시됨 (추가 - 시간 없음) ▶ $docId');
            continue;
          }

          final isNew = requestTime.toDate().isAfter(_startTime);

          if (!isNew && !isDeparture) {
            debugPrint('[TTS] 무시됨 (과거 추가) ▶ $docId (요청 시각: ${requestTime.toDate()})');
            continue;
          }

          if (newType == PlateType.parkingRequests.firestoreValue) {
            debugPrint('[TTS] (추가) 입차 ▶ $docId');
            TtsHelper.speak("입차 요청");
          } else if (isDeparture) {
            debugPrint('[TTS] (추가) 출차 요청 ▶ $docId, 번호판: $tailPlate, 위치: $location');
            TtsHelper.speak("출차 요청 $spokenTail, $location");
          }
        }

        if (change.type == DocumentChangeType.modified && prevType != null && prevType != newType) {
          if (newType == PlateType.parkingRequests.firestoreValue) {
            debugPrint('[TTS] (수정) 입차 요청 ▶ $docId (이전: $prevType)');
            TtsHelper.speak("입차 요청");
          } else if (newType == PlateType.departureRequests.firestoreValue) {
            if (prevType == PlateType.parkingCompleted.firestoreValue) {
              debugPrint('[TTS] (수정) 출차 요청 ▶ $docId (이전: $prevType), 번호판: $tailPlate, 위치: $location');
              TtsHelper.speak("출차 요청 $spokenTail, $location");
            } else {
              debugPrint('[TTS] (수정) 출차 요청이지만 이전 상태가 $prevType ▶ 무시');
            }
          }
        }
      }
    });
  }

  static void stop() {
    _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
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
}

class TtsHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;
  static bool _isInitializing = false;

  static Future<void> speak(String text) async {
    if (!_isInitialized && !_isInitializing) {
      _isInitializing = true;
      await _ensureGoogleTtsEngine();
      _isInitialized = true;
      _isInitializing = false;
    }

    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  static Future<void> _ensureGoogleTtsEngine() async {
    final engines = await _flutterTts.getEngines ?? [];
    debugPrint('[TTS] available engines: $engines');

    if (engines.contains('com.google.android.tts')) {
      await _flutterTts.setEngine('com.google.android.tts');
      debugPrint('[TTS] Google TTS 엔진 선택됨');
    } else {
      debugPrint('[TTS] Google TTS 엔진 없음, PlayStore 유도');
      await _openGoogleTtsOnPlayStore();
    }
  }

  static Future<void> _openGoogleTtsOnPlayStore() async {
    final url = Uri.parse("https://play.google.com/store/apps/details?id=com.google.android.tts");

    final launched = await launcher.launchUrl(
      url,
      mode: launcher.LaunchMode.externalApplication,
    );

    if (!launched) {
      debugPrint('[TTS] PlayStore 열기 실패');
    }
  }
}
