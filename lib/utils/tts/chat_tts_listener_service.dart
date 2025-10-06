// lib/utils/tts/chat_tts_listener_service.dart
//
// 변경 요약:
// - Firestore 직접 구독 제거
// - LatestMessageService.latest(ValueListenable)만 구독하여 낭독 수행
// - 첫 "서버 확정" 스냅은 baseline(묵음) 처리
// - 서버 확정(!isFromCache && !hasPendingWrites) + 최신 타임스탬프일 때만 낭독
//
// ※ READ 집계는 LatestMessageService가 서버 확정 스냅에서만 1회 수행합니다.

import 'package:flutter/material.dart';

import '../../services/latest_message_service.dart';
import 'tts_manager.dart';
import 'tts_user_filters.dart'; // 사용자 on/off 반영

class ChatTtsListenerService {
  static VoidCallback? _detach;
  static DateTime? _lastSpokenAt; // Timestamp 대신 DateTime으로 보관(의존성 축소)

  // 카드에서 즉시 반영되도록 메모리 캐시
  static bool _enabled = true;

  // 첫 "서버 확정" 스냅은 baseline만 확보(묵음)
  static bool _skipFirstServerSnapshot = true;

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
    // 전역 서비스가 유일한 Firestore 구독자가 되도록 start(idempotent)
    LatestMessageService.instance.start(roomId);

    _detach?.call();
    _lastSpokenAt = null;
    _skipFirstServerSnapshot = true;

    // 시작 시 설정 동기화
    refreshEnabledFromPrefs();

    // 전역 캐시 구독 시작
    _detach = () {
      LatestMessageService.instance.latest.removeListener(_onLatestChanged);
    };
    LatestMessageService.instance.latest.addListener(_onLatestChanged);

    debugPrint('[ChatTTS] ▶ 감지 시작(서비스 캐시 구독): $roomId (enabled=$_enabled)');
  }

  static void stop() {
    _detach?.call();
    _detach = null;

    _lastSpokenAt = null;
    _skipFirstServerSnapshot = true;

    debugPrint('[ChatTTS] ◼︎ 감지 중지');
  }

  static void _onLatestChanged() async {
    final data = LatestMessageService.instance.latest.value;

    // 서버 확정 스냅만 낭독 대상으로 취급
    final bool isServer = !data.isFromCache && !data.hasPendingWrites;
    if (!isServer) return;

    // 첫 서버 확정 스냅은 baseline만 설정(묵음)
    if (_skipFirstServerSnapshot) {
      _skipFirstServerSnapshot = false;
      _lastSpokenAt = data.timestamp?.toDate();
      debugPrint('[ChatTTS] baseline set: ${_lastSpokenAt?.toUtc()} (silent)');
      return;
    }

    // 타임스탬프가 없으면 낭독 불가
    final dt = data.timestamp?.toDate();
    if (dt == null) return;

    // 최신 여부 확인(이미 처리한 타임스탬프면 무시)
    if (_lastSpokenAt != null && !dt.isAfter(_lastSpokenAt!)) {
      return;
    }

    // backlog 방지: OFF여도 최신 타임스탬프는 업데이트
    _lastSpokenAt = dt;

    if (!_enabled) {
      debugPrint('[ChatTTS] 비활성화 상태 - 낭독 생략');
      return;
    }

    final text = data.text.trim();
    if (text.isEmpty) return;

    final String toSpeak =
    (data.name == null || data.name!.trim().isEmpty)
        ? text
        : '${data.name} 님의 메시지: $text';

    debugPrint('[ChatTTS] 새 메시지 ▶ $toSpeak');
    await TtsManager.speak(
      toSpeak,
      language: 'ko-KR',
      rate: 0.4,
      volume: 1.0,
      pitch: 1.0,
      preferGoogleOnAndroid: true,
      openPlayStoreIfMissing: false,
    );
  }
}
