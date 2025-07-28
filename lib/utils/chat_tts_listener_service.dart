import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ChatTtsListenerService {
  static StreamSubscription? _subscription;
  static Timestamp? _lastSpokenTimestamp;

  static void start(String roomId) {
    Future.microtask(() => _startListening(roomId));
  }

  static void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  static void _startListening(String roomId) {
    _subscription?.cancel();
    _lastSpokenTimestamp = null;

    debugPrint('[ChatTTS] 감지 시작: $roomId');

    _subscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(roomId)
        .collection('state')
        .doc('latest_message')
        .snapshots()
        .listen((docSnapshot) {
      final data = docSnapshot.data();
      if (data == null) return;

      final Timestamp? timestamp = data['timestamp'];
      final String text = data['message'] ?? '';
      final String? name = data['name'];

      if (timestamp == null) {
        debugPrint('[ChatTTS] timestamp 없음. 무시');
        return;
      }

      // 동일 메시지 반복 방지
      if (_lastSpokenTimestamp != null && !timestamp.toDate().isAfter(_lastSpokenTimestamp!.toDate())) {
        debugPrint('[ChatTTS] 무시됨 (이미 읽음)');
        return;
      }

      _lastSpokenTimestamp = timestamp;

      final String toSpeak = (name == null || name.trim().isEmpty) ? text : "$name 님의 메시지: $text";

      debugPrint('[ChatTTS] 새 메시지 ▶ $toSpeak');
      TtsHelper.speak(toSpeak);
    });
  }
}

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
