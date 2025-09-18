// lib/utils/tts/chat_tts_listener_service.dart
//
// 변경 요약:
// - (A) 시작 시 get() 제거 → 첫 스냅샷은 '묵음'으로 처리하며 그 timestamp를 기준선으로 설정
// - 이후 더 최신인 경우에만 낭독
// - read 카운터(추정) 추가: 초기 스냅샷(있으면 1), 이후 스냅샷마다 1
//
// *latest_message*는 단일 문서 리스닝이므로 초기/이후 각각 1 read로 추정합니다.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'tts_manager.dart';
import 'tts_user_filters.dart'; // ✅ 사용자 on/off 반영

class ChatTtsListenerService {
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  static Timestamp? _lastSpokenTimestamp;

  // ✅ 카드에서 즉시 반영되도록 메모리 캐시
  static bool _enabled = true;

  // 첫 스냅샷은 묵음으로 하고 baseline만 확보
  static bool _skipFirstSnapshot = true;

  // ===== Read 추정 카운터 =====
  static int _readsInitial = 0; // 초기 스냅샷(문서가 있으면 1)
  static int _readsUpdates = 0; // 이후 스냅샷마다 1
  static int get _readsTotal => _readsInitial + _readsUpdates;

  static void _printReadSummary({String prefix = 'Chat READ SUMMARY'}) {
    debugPrint('[ChatTTS] $prefix: initial=$_readsInitial, updates=$_readsUpdates → total=$_readsTotal');
  }

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    debugPrint('[ChatTTS] enabled = $v');
  }

  static Future<void> refreshEnabledFromPrefs() async {
    final f = await TtsUserFilters.load();
    _enabled = f.chat;
    debugPrint('[ChatTTS] refresh from prefs → enabled=$_enabled');
  }

  static void start(String roomId) {
    Future.microtask(() => _startListening(roomId));
  }

  static void stop() {
    _subscription?.cancel();
    _subscription = null;
    _lastSpokenTimestamp = null;
    _skipFirstSnapshot = true;

    _printReadSummary(prefix: 'READ SUMMARY (stop)');
  }

  static Future<void> _startListening(String roomId) async {
    _subscription?.cancel();
    _lastSpokenTimestamp = null;
    _skipFirstSnapshot = true;

    // 카운터 리셋
    _readsInitial = 0;
    _readsUpdates = 0;

    // ✅ 시작 시 현재 설정 동기화
    await refreshEnabledFromPrefs();

    debugPrint('[ChatTTS] ▶ 감지 시작: $roomId (enabled=$_enabled)');

    _subscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(roomId)
        .collection('state')
        .doc('latest_message')
        .snapshots()
        .listen((docSnapshot) async {
      final data = docSnapshot.data();
      // ===== Read 카운터(추정) =====
      if (_skipFirstSnapshot) {
        // 초기 스냅샷: 문서가 있으면 1 read로 추정
        if (docSnapshot.exists) {
          _readsInitial += 1;
          debugPrint('[ChatTTS] READ++ (initial) → $_readsInitial');
        }
      } else {
        // 이후 스냅샷: 변경이 올 때마다 1 read로 추정
        _readsUpdates += 1;
        debugPrint('[ChatTTS] READ++ (update) → $_readsUpdates');
      }

      if (data == null) {
        // 문서가 없는 초기 스냅샷일 수 있음
        if (_skipFirstSnapshot) {
          _skipFirstSnapshot = false;
          debugPrint('[ChatTTS] baseline set: (no doc) (silent)');
          _printReadSummary(prefix: 'READ SUMMARY (tick)');
        }
        return;
      }

      final Timestamp? timestamp = data['timestamp'] as Timestamp?;
      final String text = (data['message'] as String?) ?? '';
      final String? name = data['name'] as String?;

      if (_skipFirstSnapshot) {
        _skipFirstSnapshot = false;
        if (timestamp != null) {
          _lastSpokenTimestamp = timestamp;
        }
        debugPrint('[ChatTTS] baseline set: ${timestamp?.toDate().toUtc()} (silent)');
        _printReadSummary(prefix: 'READ SUMMARY (tick)');
        return; // 묵음
      }

      if (timestamp == null) {
        debugPrint('[ChatTTS] timestamp 없음. 무시');
        _printReadSummary(prefix: 'READ SUMMARY (tick)');
        return;
      }

      // 최신 여부 체크
      if (_lastSpokenTimestamp != null &&
          !timestamp.toDate().isAfter(_lastSpokenTimestamp!.toDate())) {
        debugPrint('[ChatTTS] 무시됨 (이미 처리된 타임스탬프)');
        _printReadSummary(prefix: 'READ SUMMARY (tick)');
        return;
      }

      // ✅ OFF일 때도 타임스탬프는 업데이트해서 backlog 낭독 방지
      _lastSpokenTimestamp = timestamp;

      if (!_enabled) {
        debugPrint('[ChatTTS] 비활성화 상태라 낭독하지 않음');
        _printReadSummary(prefix: 'READ SUMMARY (tick)');
        return;
      }

      final String toSpeak =
      (name == null || name.trim().isEmpty) ? text : "$name 님의 메시지: $text";

      debugPrint('[ChatTTS] 새 메시지 ▶ $toSpeak');
      await TtsManager.speak(
        toSpeak,
        language: 'ko-KR',
        rate: 0.4,
        volume: 1.0,
        pitch: 1.0,
        preferGoogleOnAndroid: true,
        openPlayStoreIfMissing: false, // 채팅은 스토어 유도 없음
      );

      _printReadSummary(prefix: 'READ SUMMARY (tick)');
    }, onError: (e, st) {
      debugPrint('[ChatTTS] STREAM ERROR: $e\n$st');
      _printReadSummary(prefix: 'READ SUMMARY (error)');
    }, onDone: () {
      debugPrint('[ChatTTS] STREAM DONE (room=$roomId)');
      _printReadSummary(prefix: 'READ SUMMARY (done)');
    });
  }
}
