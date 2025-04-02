import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Firebase 초기화를 위한 패키지
import 'package:provider/provider.dart'; // 상태 관리를 위한 Provider 패키지
import 'routes.dart'; // 앱 라우팅 정보를 관리하는 파일
import 'providers/providers.dart'; // 상태 관리 객체를 정의한 파일
import 'theme.dart'; // 테마 설정을 분리한 파일
import 'dart:developer' as dev;

// 초기 라우트 상수 정의
const String initialRoute = AppRoutes.login;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    runApp(const MyApp());
  } catch (e) {
    dev.log("DB 초기화 실패: $e");
    runApp(const ErrorApp(message: 'DB 초기화 실패. 앱을 다시 시작해주세요.'));
  }
}

// MyApp 클래스: 앱의 전체 구조 정의
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders, // providers.dart에서 정의된 상태 관리 객체 목록
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'easyvalet',
        theme: appTheme,
        initialRoute: initialRoute, // 초기 라우트 값을 상수로 사용
        routes: appRoutes, // routes.dart에서 정의된 라우팅 정보
        onUnknownRoute: (settings) => MaterialPageRoute(
          builder: (context) => const NotFoundPage(),
        ),
      ),
    );
  }
}

// Firebase 초기화 실패 시 표시할 에러 화면
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

// 정의되지 않은 경로 접근 시 보여줄 페이지
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
