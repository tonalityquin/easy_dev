import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Firebase 초기화를 위한 패키지
import 'package:provider/provider.dart'; // 상태 관리를 위한 Provider 패키지
import 'repositories/plate_repository.dart'; // PlateRepository 가져오기
import 'repositories/location_repository.dart'; // LocationRepository 가져오기
import 'repositories/user_repository.dart'; // UserRepository 가져오기
import 'states/secondary_access_state.dart';
import 'states/page_state.dart'; // 페이지 상태 관리를 위한 상태 클래스
import 'states/plate_state.dart'; // 차량 관련 데이터를 관리하는 상태 클래스
import 'states/page_info.dart'; // 페이지 정보 (기본 페이지 리스트 포함)
import 'states/area_state.dart'; // 지역 상태 관리
import 'states/user_state.dart'; // 사용자 상태 관리
import 'states/location_state.dart'; // Location 상태 관리
import 'screens/type_page.dart'; // 메인 화면 (타입 선택 화면)
import 'screens/login_page.dart'; // 로그인 화면
import 'screens/secondary_pages/office_mode_pages/location_management.dart'; // LocationManagement 페이지

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Firestore 기반의 Repository 구현체 생성
    final plateRepository = FirestorePlateRepository();
    final locationRepository = FirestoreLocationRepository();
    final userRepository = FirestoreUserRepository(); // UserRepository 구현체 생성

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PageState(pages: defaultPages)),
        ChangeNotifierProvider(create: (_) => PlateState(plateRepository)), // PlateRepository 주입
        ChangeNotifierProvider(create: (_) => AreaState()),
        ChangeNotifierProvider(create: (_) => UserState(userRepository)), // UserRepository 주입
        ChangeNotifierProvider(create: (_) => SecondaryAccessState()),
        ChangeNotifierProvider(create: (_) => LocationState(locationRepository)), // LocationRepository 주입
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'easyvalet',
        theme: ThemeData(primarySwatch: Colors.blue),
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginPage(),
          '/home': (context) => const TypePage(),
          '/location_management': (context) => const LocationManagement(), // LocationManagement 추가 가능
        },
      ),
    );
  }
}
