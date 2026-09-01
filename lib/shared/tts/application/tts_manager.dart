import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

class TtsManager {
  TtsManager._();

  static final FlutterTts _tts = FlutterTts();
  static final StreamController<_Utterance> _queue =
      StreamController<_Utterance>(sync: true);
  static bool _initialized = false;
  static Future<void>? _initializationFuture;
  static StreamSubscription<dynamic>? _queueSubscription;

  static Future<void> _ensureInitialized({
    bool preferGoogleOnAndroid = true,
    bool openPlayStoreIfMissing = false,
  }) async {
    if (_initialized) return;

    final current = _initializationFuture;
    if (current != null) {
      await current;
      return;
    }

    final future = _initialize(
      preferGoogleOnAndroid: preferGoogleOnAndroid,
      openPlayStoreIfMissing: openPlayStoreIfMissing,
    );
    _initializationFuture = future;
    try {
      await future;
      _initialized = true;
      debugPrint('[TTS] initialization complete');
    } catch (e, st) {
      _initialized = false;
      debugPrint('[TTS] initialization failed: $e\n$st');
      rethrow;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  static Future<void> _initialize({
    required bool preferGoogleOnAndroid,
    required bool openPlayStoreIfMissing,
  }) async {
    if (preferGoogleOnAndroid && Platform.isAndroid) {
      List<String> engines = const <String>[];
      try {
        final raw = await _tts.getEngines;
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
          final url = Uri(
            scheme: 'https',
            host: 'play.google.com',
            path: '/store/apps/details',
            queryParameters: <String, String>{
              'id': 'com.google.android.tts',
            },
          );
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

    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('[TTS] awaitSpeakCompletion error: $e');
    }

    await _queueSubscription?.cancel();
    _queueSubscription = _queue.stream.asyncMap((_Utterance utterance) async {
      await _tts.setLanguage(utterance.language);
      await _tts.setSpeechRate(utterance.rate);
      await _tts.setVolume(utterance.volume);
      await _tts.setPitch(utterance.pitch);
      await _tts.stop();
      return _tts.speak(utterance.text);
    }).listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[TTS] speak error: $error\n$stackTrace');
      },
    );
  }

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
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    await _tts.stop();
    await _queue.close();
    _initialized = false;
    _initializationFuture = null;
  }
}

class _Utterance {
  _Utterance({
    required this.text,
    required this.language,
    required this.rate,
    required this.volume,
    required this.pitch,
  });

  final String text;
  final String language;
  final double rate;
  final double volume;
  final double pitch;
}
