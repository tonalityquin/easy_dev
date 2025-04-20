import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'routes.dart';
import 'providers/providers.dart';
import 'theme.dart';
import 'states/user/user_state.dart';
import 'services/plate_tts_listener_service.dart';
import 'states/area/area_state.dart';
import 'screens/secondary_pages/dev_mode_pages/area_management.dart';
import 'dart:developer' as dev;

const String initialRoute = AppRoutes.login;

class TtsHelper {
  static final FlutterTts _flutterTts = FlutterTts();

  static Future<void> speak(String text) async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await registerDevResources(); // ✅ dev division/area/user_accounts 자동 생성

    runApp(const MyApp());
  } catch (e) {
    dev.log("DB 초기화 실패: $e");
    runApp(const ErrorApp(message: 'DB 초기화 실패. 앱을 다시 시작해주세요.'));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders,
      child: Builder(
        builder: (context) {
          return Consumer2<UserState, AreaState>(
            builder: (context, userState, areaState, child) {
              if (userState.isLoggedIn && !areaState.isLocked) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  // ✅ 1. userState.area를 기준으로 초기화
                  await areaState.initialize(userState.area);
                  areaState.lockArea();

                  // ✅ 2. TTS 시작은 currentArea가 동기화된 후 실행
                  PlateTtsListenerService.start(areaState.currentArea);
                  dev.log("[TTS] 감지 시작됨 (초기화 완료 후): ${areaState.currentArea}");
                });
              }

              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'easyvalet',
                theme: appTheme,
                initialRoute: initialRoute,
                routes: appRoutes,
                onUnknownRoute: (settings) => MaterialPageRoute(
                  builder: (context) => const NotFoundPage(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String message;

  const ErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('오류 발생')),
        body: Center(
          child: Text(
            message,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('404 - 페이지 없음')),
      body: const Center(
        child: Text(
          '요청하신 페이지를 찾을 수 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
