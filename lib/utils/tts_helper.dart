import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isSpeaking = false;

  static Future<void> speak(String text) async {
    try {
      if (_isSpeaking) {
        debugPrint("[TTS] ⏹️ 이전 발화 중지 요청");
        await _flutterTts.stop();
        _isSpeaking = false;
      }

      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5); // 더 느리게
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      debugPrint("[TTS] 🔊 발화 시작: $text");
      _isSpeaking = true;

      await _flutterTts.speak(text);

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        debugPrint("[TTS] ✅ 발화 완료");
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint("[TTS] ❌ 오류 발생: $msg");
      });
    } catch (e) {
      debugPrint("[TTS] ❌ 예외 발생: $e");
      _isSpeaking = false;
    }
  }

  /// 숫자 문자열을 한글로 변환하여 TTS로 발화 (예: "6699" → "육 육 구 구")
  static Future<void> speakHangulDigits(String digits) async {
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

    final spoken = digits
        .split('')
        .map((d) => koreanDigits[d] ?? d)
        .join(' ');
    await speak(spoken);
  }
}
