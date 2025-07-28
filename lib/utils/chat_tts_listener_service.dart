import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ChatTtsListenerService {
  static StreamSubscription? _subscription;
  static DateTime _startTime = DateTime.now();

  static void start(String roomId) {
    Future.microtask(() => _startListening(roomId));
  }

  static void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  static void _startListening(String roomId) {
    _subscription?.cancel();
    _startTime = DateTime.now();

    debugPrint('[ChatTTS] 감지 시작: $roomId @ $_startTime');

    _subscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        final Timestamp? timestamp = data['timestamp'];
        final String text = data['message'] ?? '';
        final String? name = data['name'];

        // 새 메시지 추가만 감지
        if (change.type == DocumentChangeType.added) {
          // timestamp 없거나 과거 메시지는 무시
          if (timestamp == null || !timestamp.toDate().isAfter(_startTime)) {
            debugPrint('[ChatTTS] 무시됨 (과거 데이터 또는 시간 없음)');
            continue;
          }

          // 익명 처리: name 없으면 그냥 본문만 읽음
          final String toSpeak = (name == null || name.trim().isEmpty) ? text : "$name 님의 메시지: $text";

          debugPrint('[ChatTTS] 새 메시지 ▶ $toSpeak');
          TtsHelper.speak(toSpeak);
        }
      }
    });
  }
}

/// 공통 TTS 유틸리티
/// 공통 TTS 유틸리티
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
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  static Future<void> _ensureGoogleTtsEngine() async {
    final engines = await _flutterTts.getEngines ?? [];
    if (engines.contains('com.google.android.tts')) {
      await _flutterTts.setEngine('com.google.android.tts');
    } else {
      debugPrint('[TTS] Google TTS 엔진 없음');
    }
  }
}
