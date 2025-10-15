// lib/offlines/tts/offline_tts.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'offline_tts_filters.dart';

/// 오프라인 전용 TTS 싱글톤.
/// - 포그라운드 서비스 없음
/// - 외부 스토리지 의존 없음
/// - 호출 지점에서 즉시 발화
class OfflineTts {
  OfflineTts._();
  static final OfflineTts instance = OfflineTts._();

  final FlutterTts _tts = FlutterTts();
  bool _inited = false;

  Future<void> _ensureInit() async {
    if (_inited) return;
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.4);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      try { await _tts.setQueueMode(1); } catch (_) {}
      try { await _tts.awaitSpeakCompletion(true); } catch (_) {}
      _inited = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[OfflineTts] init failed: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (!OfflineTtsFilters.enabled) return;
    final t = text.trim();
    if (t.isEmpty) return;
    await _ensureInit();
    try { await _tts.stop(); } catch (_) {}
    try { await _tts.speak(t); } catch (e) {
      if (kDebugMode) debugPrint('[OfflineTts] speak failed: $e');
    }
  }

  /// plate/fourDigit에서 "뒷 4자리" 산출
  String? _fourOf({String? plateNumber, String? fourDigit}) {
    final f = (fourDigit ?? '').trim();
    if (RegExp(r'^\d{4}$').hasMatch(f)) return f;
    final pn = (plateNumber ?? '').replaceAll(RegExp(r'\D'), '');
    if (pn.length >= 4) return pn.substring(pn.length - 4);
    return null;
  }

  // ─────────────────────────────────────────
  // 요구 문구
  // ─────────────────────────────────────────

  /// (입차 "요청" 생성 직후)
  /// → "입차 되었습니다."
  Future<void> sayParkingInserted() async {
    if (!OfflineTtsFilters.parkingRequest) return;
    await _speak('입차 요청');
  }

  /// (입차 완료 → 출차 요청)
  /// → "차량 뒷번호#### 출차 요청"
  Future<void> sayDepartureRequested({
    String? plateNumber,
    String? fourDigit,
  }) async {
    if (!OfflineTtsFilters.departureRequest) return;
    final f = _fourOf(plateNumber: plateNumber, fourDigit: fourDigit) ?? '미상';
    await _speak('$f 출차 요청');
  }

  /// (출차 요청 → 출차 완료)
  /// → "차량 뒷번호#### 출차 완료되었습니다."
  Future<void> sayDepartureCompleted({
    String? plateNumber,
    String? fourDigit,
  }) async {
    if (!OfflineTtsFilters.departureCompleted) return;
    final f = _fourOf(plateNumber: plateNumber, fourDigit: fourDigit) ?? '미상';
    await _speak('$f 출차 완료되었습니다.');
  }

  /// (선택) 환경 조정
  Future<void> configure({
    String language = 'ko-KR',
    double rate = 0.4,
    double volume = 1.0,
    double pitch = 1.0,
  }) async {
    await _ensureInit();
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(volume);
      await _tts.setPitch(pitch);
    } catch (e) {
      if (kDebugMode) debugPrint('[OfflineTts] configure failed: $e');
    }
  }
}
