import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'routes.dart';
import 'providers/providers.dart';
import 'screens/clock_in_pages/debugs/clock_in_debug_firestore_logger.dart';
import 'screens/logins/debugs/login_debug_firestore_logger.dart';
import 'theme.dart';
import 'utils/init/dev_initializer.dart';
import 'utils/foreground_task_handler.dart';
import 'utils/firestore_logger.dart'; // ✅ FirestoreLogger import

/// 🔹 포그라운드 태스크 콜백
@pragma('vm:entry-point')
void myForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

/// 🔹 앱 진입점
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'foreground_service',
      channelName: '출차 요청 수신 중',
      channelDescription: '포그라운드에서 대기 중',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000), // 5초마다 호출
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(const AppBootstrapper());
}

/// 🔹 앱 초기화 위젯
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

  /// 초기화 로직
  Future<void> _initializeApp() async {
    // ✅ Firebase 초기화
    await Firebase.initializeApp();

    // ✅ FirestoreLogger 초기화
    await FirestoreLogger().init();

    // ✅ LoginDebugFirestoreLogger 초기화
    await LoginDebugFirestoreLogger().init();

    await ClockInDebugFirestoreLogger().init();
    // ✅ 개발용 리소스 초기화
    await registerDevResources();

    // 📍 런타임 퍼미션 요청
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }

    // 배터리 최적화 제외 요청
    await Permission.ignoreBatteryOptimizations.request();

    // Foreground Service 시작
    await FlutterForegroundTask.startService(
      notificationTitle: '출차 요청 수신 중',
      notificationText: '포그라운드에서 대기 중',
    );
  }
}

/// 🔹 메인 앱 위젯
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
        initialRoute: AppRoutes.login,
        routes: appRoutes,
        onUnknownRoute: (_) => MaterialPageRoute(
          builder: (_) => const NotFoundPage(),
        ),
      ),
    );
  }
}

/// 🔹 에러 화면
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

/// 🔹 404 페이지
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
