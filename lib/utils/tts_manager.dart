// lib/utils/tts_manager.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// 공용 TTS 매니저(싱글톤).
/// - 엔진/언어/속도/피치/볼륨 기본 세팅
/// - 발화 큐(동시 1건 보장)
/// - Android에서 Google TTS 우선 선택(선택적 Play 스토어 유도)
class TtsManager {
  TtsManager._();

  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _initializing = false;

  static final StreamController<_Utterance> _queue = StreamController<_Utterance>(sync: true);

  static Future<void> _ensureInitialized({
    bool preferGoogleOnAndroid = true,
    bool openPlayStoreIfMissing = false,
  }) async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // ── 엔진 선택(안드로이드 전용) ───────────────────────────────────────
      if (preferGoogleOnAndroid && Platform.isAndroid) {
        List<String> engines = const [];
        try {
          // getEngines: List<dynamic>? 반환 가능 → 런타임 캐스팅
          final raw = await _tts.getEngines; // <-- 여기서만 await
          if (raw is List) {
            engines = raw.map((e) => e.toString()).toList(growable: false);
          }
          debugPrint('[TTS] engines: $engines');
        } catch (e) {
          debugPrint('[TTS] getEngines error: $e');
        }

        if (engines.contains('com.google.android.tts')) {
          await _tts.setEngine('com.google.android.tts');
          debugPrint('[TTS] Google TTS 엔진 선택됨');
        } else {
          debugPrint('[TTS] Google TTS 엔진 없음');
          if (openPlayStoreIfMissing) {
            final url = Uri.parse('https://play.google.com/store/apps/details?id=com.google.android.tts');
            try {
              await launcher.launchUrl(
                url,
                mode: launcher.LaunchMode.externalApplication,
              );
            } catch (e) {
              debugPrint('[TTS] PlayStore launch error: $e');
            }
          }
        }
      }

      // ── 발화 완료 대기 설정(플랫폼 지원 시) ───────────────────────────────
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}

      // ── 큐 소비 시작(한 번만) ────────────────────────────────────────────
      _queue.stream.asyncMap((_Utterance u) async {
        // 호출 시점마다 말하기 설정 적용
        await _tts.setLanguage(u.language);
        await _tts.setSpeechRate(u.rate);
        await _tts.setVolume(u.volume);
        await _tts.setPitch(u.pitch);

        await _tts.stop();
        return _tts.speak(u.text);
      }).listen((_) {}, onError: (e) {
        debugPrint('[TTS] speak error: $e');
      });
    } finally {
      _initialized = true;
      _initializing = false;
    }
  }

  /// 한 문장을 말합니다. 호출 시 설정을 함께 지정할 수 있습니다.
  static Future<void> speak(
    String text, {
    String language = 'ko-KR',
    double rate = 0.5,
    double volume = 1.0,
    double pitch = 1.0,
    bool preferGoogleOnAndroid = true,
    bool openPlayStoreIfMissing = false,
  }) async {
    await _ensureInitialized(
      preferGoogleOnAndroid: preferGoogleOnAndroid,
      openPlayStoreIfMissing: openPlayStoreIfMissing,
    );
    _queue.add(
      _Utterance(
        text: text,
        language: language,
        rate: rate,
        volume: volume,
        pitch: pitch,
      ),
    );
  }

  static Future<void> stop() => _tts.stop();

  static Future<void> dispose() async {
    await _tts.stop();
    await _queue.close();
  }
}

class _Utterance {
  final String text;
  final String language;
  final double rate;
  final double volume;
  final double pitch;

  _Utterance({
    required this.text,
    required this.language,
    required this.rate,
    required this.volume,
    required this.pitch,
  });
}
