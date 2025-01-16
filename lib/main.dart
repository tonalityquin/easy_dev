import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Firebase 초기화를 위한 패키지
import 'package:provider/provider.dart'; // 상태 관리를 위한 Provider 패키지
import 'states/secondary_role_state.dart';
import 'states/page_state.dart'; // 페이지 상태 관리를 위한 상태 클래스
import 'states/plate_state.dart'; // 차량 관련 데이터를 관리하는 상태 클래스
import 'states/page_info.dart'; // 페이지 정보 (기본 페이지 리스트 포함)
import 'states/area_state.dart'; // 지역 상태 관리
import 'states/user_state.dart'; // 사용자 상태 관리
import 'screens/type_page.dart'; // 메인 화면 (타입 선택 화면)
import 'screens/login_page.dart'; // 로그인 화면

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PageState(pages: defaultPages)),
        ChangeNotifierProvider(create: (_) => PlateState()),
        ChangeNotifierProvider(create: (_) => AreaState()),
        ChangeNotifierProvider(create: (_) => UserState()),
        ChangeNotifierProvider(create: (_) => SecondaryRoleState()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'easyvalet',
        theme: ThemeData(primarySwatch: Colors.blue),
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginPage(),
          '/home': (context) => const TypePage(),
        },
      ),
    );
  }
}
