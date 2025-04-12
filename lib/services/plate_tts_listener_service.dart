import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../main.dart'; // TtsHelper가 정의된 경로
import 'dart:async';

class PlateTtsListenerService {
  static StreamSubscription? _subscription;
  static final Map<String, String?> _lastTypes = {};
  static DateTime _startTime = DateTime.now();

  static void start(String currentArea) {
    _subscription?.cancel();
    _lastTypes.clear();
    _startTime = DateTime.now();

    debugPrint('[TTS] 감지 시작: $currentArea @ $_startTime');

    _subscription = FirebaseFirestore.instance.collection('plates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        final docId = doc.id;
        final newType = data['type'];
        final area = data['area'];
        final plateNumber = data['plate_number'] ?? '';
        final Timestamp? requestTime = data['request_time'];
        final prevType = _lastTypes[docId];

        if (area != currentArea) continue;
        _lastTypes[docId] = newType;

        // 번호판 뒷자리 추출
        final tailPlate = plateNumber.length >= 4
            ? plateNumber.substring(plateNumber.length - 4)
            : plateNumber;

        // 한글 숫자 발화용 텍스트 생성
        final spokenTail = _convertToKoreanDigits(tailPlate);

        // 🔹 문서 추가
        if (change.type == DocumentChangeType.added) {
          if (requestTime == null || requestTime.toDate().isBefore(_startTime)) {
            debugPrint('[TTS] 무시됨 (추가) ▶ $docId (요청 시각: ${requestTime?.toDate()})');
            continue;
          }

          if (newType == 'parking_requests') {
            debugPrint('[TTS] (추가) 입차 ▶ $docId');
            TtsHelper.speak("입차 요청");
          } else if (newType == 'departure_requests') {
            debugPrint('[TTS] (추가) 출차 요청 ▶ $docId');
            TtsHelper.speak("출차 요청 $spokenTail");
          }
        }

        // 🔹 문서 수정
        if (change.type == DocumentChangeType.modified &&
            prevType != null &&
            prevType != newType) {
          if (newType == 'parking_requests') {
            debugPrint('[TTS] (수정) 입차 요청으로 변경됨 ▶ $docId (이전: $prevType)');
            TtsHelper.speak("입차 요청");
          } else if (newType == 'departure_requests') {
            if (prevType == 'parking_completed') {
              debugPrint('[TTS] (수정) 출차 요청으로 변경됨 ▶ $docId (이전: $prevType), 번호판: $tailPlate');
              TtsHelper.speak("출차 요청 $spokenTail");
            } else {
              debugPrint('[TTS] (수정) 출차 요청이지만 이전 상태가 $prevType ▶ 무시');
            }
          } else {
            debugPrint('[TTS] (수정) type 변경 감지됨 ▶ $docId (이전: $prevType → 현재: $newType) ▶ 무시');
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

    return digits
        .split('')
        .map((d) => koreanDigits[d] ?? d)
        .join(', ');
  }

}
