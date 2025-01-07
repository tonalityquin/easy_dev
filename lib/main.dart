import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Firebase 초기화를 위한 패키지
import 'package:provider/provider.dart'; // 상태 관리를 위한 Provider 패키지
import 'states/page_state.dart'; // 페이지 상태 관리를 위한 상태 클래스
import 'states/plate_state.dart'; // 차량 관련 데이터를 관리하는 상태 클래스
import 'states/page_info.dart'; // 페이지 정보 (기본 페이지 리스트 포함)
import 'screens/type_page.dart'; // 메인 화면 (타입 선택 화면)
import 'screens/login_page.dart'; // 로그인 화면

/// 앱의 진입점 (main 함수)
void main() async {
  // Flutter 프레임워크가 네이티브 통합을 위해 준비되었는지 확인
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 (Firebase 기능 사용 전 필수 설정)
  await Firebase.initializeApp();

  // Flutter 앱 실행
  runApp(const MyApp());
}

/// MyApp 클래스: 앱의 최상위 위젯
class MyApp extends StatelessWidget {
  const MyApp({super.key}); // key는 Flutter 위젯 트리에서 고유 식별자 역할

  /// 앱의 위젯 트리를 빌드
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // 여러 상태 관리자를 제공하는 MultiProvider
      providers: [
        // 페이지 상태 관리 (ChangeNotifier 사용)
        ChangeNotifierProvider(
          create: (_) => PageState(pages: defaultPages), // 기본 페이지 설정
        ),
        // 차량 관련 데이터 관리 (ChangeNotifier 사용)
        ChangeNotifierProvider(create: (_) => PlateState()),
      ],
      child: MaterialApp(
        // 디버그 모드 배너 비활성화
        debugShowCheckedModeBanner: false,
        title: 'easyvalet',
        // 앱 이름
        theme: ThemeData(
          primarySwatch: Colors.blue, // 앱의 기본 테마 색상
        ),
        initialRoute: '/login',
        // 앱 실행 시 첫 화면 경로
        routes: {
          // 라우트 정의 (화면 전환 시 사용)
          '/login': (context) => const LoginPage(), // 로그인 페이지
          '/home': (context) => const TypePage(), // 메인 화면 (타입 선택 페이지)
        },
      ),
    );
  }
}
