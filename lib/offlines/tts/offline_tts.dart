import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'offline_tts_filters.dart';

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
      try {
        await _tts.setQueueMode(1);
      } catch (_) {}
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}
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
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _tts.speak(t);
    } catch (e) {
      if (kDebugMode) debugPrint('[OfflineTts] speak failed: $e');
    }
  }

  String? _fourOf({String? plateNumber, String? fourDigit}) {
    final f = (fourDigit ?? '').trim();
    if (RegExp(r'^\d{4}$').hasMatch(f)) return f;
    final pn = (plateNumber ?? '').replaceAll(RegExp(r'\D'), '');
    if (pn.length >= 4) return pn.substring(pn.length - 4);
    return null;
  }

  Future<void> sayParkingInserted() async {
    if (!OfflineTtsFilters.parkingRequest) return;
    await _speak('입차 요청');
  }

  Future<void> sayDepartureRequested({
    String? plateNumber,
    String? fourDigit,
  }) async {
    if (!OfflineTtsFilters.departureRequest) return;
    final f = _fourOf(plateNumber: plateNumber, fourDigit: fourDigit) ?? '미상';
    await _speak('$f 출차 요청');
  }

  Future<void> sayDepartureCompleted({
    String? plateNumber,
    String? fourDigit,
  }) async {
    if (!OfflineTtsFilters.departureCompleted) return;
    final f = _fourOf(plateNumber: plateNumber, fourDigit: fourDigit) ?? '미상';
    await _speak('$f 출차 완료되었습니다.');
  }
}
