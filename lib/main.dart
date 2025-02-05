import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Firebase 초기화를 위한 패키지
import 'package:provider/provider.dart'; // 상태 관리를 위한 Provider 패키지
import 'routes.dart'; // 앱 라우팅 정보를 관리하는 파일
import 'providers.dart'; // 상태 관리 객체를 정의한 파일

// 앱의 시작점: Firebase 초기화 후 MyApp 실행
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 비동기 작업을 위한 Flutter 엔진 초기화
  try {
    await Firebase.initializeApp(); // Firebase 초기화
  } catch (e) {
    print('Firebase 초기화 실패: $e'); // 에러 출력
  }

  runApp(const MyApp()); // MyApp 위젯 실행
}


// MyApp 클래스: 앱의 전체 구조 정의
class MyApp extends StatelessWidget {
  const MyApp({super.key}); // 생성자

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders, // providers.dart에서 정의된 상태 관리 객체 목록
      child: MaterialApp(
        debugShowCheckedModeBanner: false, // 디버그 배너 제거
        title: 'easyvalet', // 앱 이름
        theme: ThemeData(primarySwatch: Colors.blue), // 앱의 기본 테마 색상
        initialRoute: '/login', // 앱의 초기 라우트 경로
        routes: appRoutes, // routes.dart에서 정의된 라우팅 정보
      ),
    );
  }
}
