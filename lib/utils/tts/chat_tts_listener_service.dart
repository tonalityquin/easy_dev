import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'tts_manager.dart';
import 'tts_user_filters.dart'; // ✅ 추가

class ChatTtsListenerService {
  static StreamSubscription? _subscription;
  static Timestamp? _lastSpokenTimestamp;

  // ✅ 카드에서 즉시 반영되도록 메모리 캐시
  static bool _enabled = true;

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    debugPrint('[ChatTTS] enabled = $v');
  }

  static Future<void> refreshEnabledFromPrefs() async {
    final f = await TtsUserFilters.load();
    _enabled = f.chat;
    debugPrint('[ChatTTS] refresh from prefs → enabled=${_enabled}');
  }

  static void start(String roomId) {
    Future.microtask(() => _startListening(roomId));
  }

  static void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _startListening(String roomId) async {
    _subscription?.cancel();

    // ✅ 시작 시 현재 설정 동기화
    await refreshEnabledFromPrefs();

    final initialDoc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(roomId)
        .collection('state')
        .doc('latest_message')
        .get();

    if (initialDoc.exists) {
      final data = initialDoc.data();
      if (data != null && data['timestamp'] is Timestamp) {
        _lastSpokenTimestamp = data['timestamp'];
        debugPrint('[ChatTTS] 앱 시작 시점 메시지 타임스탬프 저장: $_lastSpokenTimestamp');
      }
    }

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

      // 최신 여부 체크
      if (_lastSpokenTimestamp != null &&
          !timestamp.toDate().isAfter(_lastSpokenTimestamp!.toDate())) {
        debugPrint('[ChatTTS] 무시됨 (이미 처리된 타임스탬프)');
        return;
      }

      // ✅ OFF일 때도 타임스탬프는 업데이트해서 backlog 낭독 방지
      _lastSpokenTimestamp = timestamp;

      if (!_enabled) {
        debugPrint('[ChatTTS] 비활성화 상태라 낭독하지 않음');
        return;
      }

      final String toSpeak =
      (name == null || name.trim().isEmpty) ? text : "$name 님의 메시지: $text";

      debugPrint('[ChatTTS] 새 메시지 ▶ $toSpeak');
      TtsHelper.speak(toSpeak);
    });
  }
}

class TtsHelper {
  static Future<void> speak(String text) async {
    await TtsManager.speak(
      text,
      language: 'ko-KR',
      rate: 0.4,
      volume: 1.0,
      pitch: 1.0,
      preferGoogleOnAndroid: true,
      openPlayStoreIfMissing: false, // 채팅은 스토어 유도 없음(로그만)
    );
  }
}
