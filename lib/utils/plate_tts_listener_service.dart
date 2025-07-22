import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../enums/plate_type.dart';

class PlateTtsListenerService {
  static StreamSubscription? _subscription;

  /// 문서별 마지막 감지된 상태(type) 저장
  static final Map<String, String?> _lastTypes = {};

  /// 앱이 실행된 시각을 기준으로 이후 요청만 TTS로 안내
  ///
  /// 이유: Firestore `.snapshots()`는 앱 실행 시 기존 문서도 'added' 이벤트로 제공하므로,
  /// 과거 문서를 필터링하지 않으면 앱 재시작 시 이전 요청이 다시 TTS로 울림
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

        // ✅ 문서가 새로 추가된 경우만 TTS 대상
        //
        // 이유:
        // - Firestore는 type 필드만 바뀌어도 새 컬렉션에선 'added'로 감지됨
        // - 'modified' 이벤트는 다른 원인(예: 선택자 변경)도 포함될 수 있어 노이즈 많음
        // - 따라서 이 설계에선 'added'만 다루고, 상태 변경 감지는 배제
        if (change.type == DocumentChangeType.added) {
          final isDeparture = newType == PlateType.departureRequests.firestoreValue;

          // ✅ requestTime 필드가 없는 문서는 무시
          //
          // 이유:
          // - Firestore에는 종종 아직 완성되지 않은 문서가 추가될 수 있음
          // - 이 경우 잘못된 TTS 안내 방지 목적
          if (requestTime == null) {
            debugPrint('[TTS] 무시됨 (추가 - 시간 없음) ▶ $docId');
            continue;
          }

          // ✅ 앱 시작 이후 생성된 요청만 처리 (과거 요청 제외)
          final isNew = requestTime.toDate().isAfter(_startTime);
          if (!isNew) {
            debugPrint('[TTS] 무시됨 (과거 추가) ▶ $docId (요청 시각: ${requestTime.toDate()})');
            continue;
          }

          // ✅ 입차 요청 감지
          if (newType == PlateType.parkingRequests.firestoreValue) {
            debugPrint('[TTS] (추가) 입차 ▶ $docId');
            TtsHelper.speak("입차 요청");

            // ✅ 출차 요청 감지
          } else if (isDeparture) {
            debugPrint('[TTS] (추가) 출차 요청 ▶ $docId, 번호판: $tailPlate, 위치: $location');
            TtsHelper.speak("출차 요청 $spokenTail, $location");
          }
        }

        // ❌ DocumentChangeType.modified는 현재 TTS 대상 아님
        //
        // 이유:
        // - type 필드 변경이 아닌 단순 필드 머지(memo 등)에도 호출 위험 있음
        // - 이 경우 잘못된 TTS가 반복될 수 있음 (ex: 선택자 변경 등)
        // - 추가적으로 처리하려면 prevType 비교 및 시간 기준 등을 추가해야 함
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

/// TTS 실행 유틸리티 클래스
class TtsHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;
  static bool _isInitializing = false;

  /// 주어진 문장을 TTS로 읽음
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

    await _flutterTts.stop(); // 현재 읽고 있는 TTS 중단
    await _flutterTts.speak(text); // 새 TTS 실행
  }

  /// Google TTS 엔진이 있는지 확인하고 설정
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

  /// Google TTS 설치 유도
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
