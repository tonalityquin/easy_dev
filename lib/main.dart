// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'routes.dart';
import 'providers/providers.dart';
import 'screens/commute_package/commute_outside_package/floating_controls/commute_outside_floating.dart';
import 'screens/dev_package/dev_memo.dart';
import 'screens/head_package/head_memo.dart';
import 'theme.dart';
import 'utils/init/dev_initializer.dart';
import 'utils/foreground_task_handler.dart';
import 'utils/app_navigator.dart'; // ✅ 전역 NavigatorKey

@pragma('vm:entry-point')
void myForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 포그라운드 태스크 초기화 (const 제거로 인한 오류 방지)
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: '출차 요청 수신 중',
      channelDescription: '포그라운드에서 대기 중',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(const AppBootstrapper());
}

class AppBootstrapper extends StatelessWidget {
  const AppBootstrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeApp(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ErrorApp(message: 'DB 초기화 실패. 앱을 다시 시작해주세요.');
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return const MyApp();
        }
        return const MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        );
      },
    );
  }

  Future<void> _initializeApp() async {
    // ✅ Firebase
    await Firebase.initializeApp();

    // ✅ 개발용 리소스 등록
    await registerDevResources();

    // ✅ 권한 요청
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }

    await Permission.ignoreBatteryOptimizations.request();

    // ✅ 포그라운드 서비스 시작
    await FlutterForegroundTask.startService(
      notificationTitle: '이 서비스 알림 탭은 main에서 메시지 발신 중',
      notificationText: '포그라운드에서 대기 중',
    );

    // ✅ 플로팅/메모 초기화(상태 로드). enabled가 true일 때만 mount됨
    await DevMemo.init();
    await HeadMemo.init();

    // ✅ 출퇴근 플로팅(휴식/퇴근) 컨트롤 초기화
    //    - on/off 상태를 복원해서 재실행 시에도 표시 가능
    await CommuteOutsideFloating.init();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'easyvalet',
        theme: appTheme,
        initialRoute: AppRoutes.selector,
        routes: appRoutes,
        onUnknownRoute: (_) => MaterialPageRoute(builder: (_) => const NotFoundPage()),

        // ✅ 앱 전역 네비게이터 키(오버레이/시트 컨텍스트 안정성)
        navigatorKey: AppNavigator.key,
        scaffoldMessengerKey: AppNavigator.scaffoldMessengerKey,

        // ✅ 첫 프레임 후, 각 플로팅이 켜져있다면 오버레이 장착
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            DevMemo.mountIfNeeded();
            HeadMemo.mountIfNeeded();
            CommuteOutsideFloating.mountIfNeeded();
          });
          return child!;
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
