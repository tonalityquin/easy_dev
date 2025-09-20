// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'routes.dart';
import 'providers/providers.dart';
import 'screens/dev_package/dev_memo.dart';
import 'screens/head_package/head_memo.dart';
import 'theme.dart';
// import 'utils/init/dev_initializer.dart'; // 비상용 개발 지역 계정 임시 비활성화
import 'utils/tts/foreground_task_handler.dart';
import 'utils/app_navigator.dart';

String _ts() => DateTime.now().toIso8601String();

@pragma('vm:entry-point')
void myForegroundCallback() {
  // 포그라운드 태스크가 시작될 때 TaskHandler를 등록
  debugPrint('[MAIN][${_ts()}] myForegroundCallback → setTaskHandler(MyTaskHandler)');
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ UI <-> Task 통신 포트 초기화 (sendDataToTask / onReceiveData 사용을 위해 필요)
  debugPrint('[MAIN][${_ts()}] initCommunicationPort');
  FlutterForegroundTask.initCommunicationPort();

  // ✅ 포그라운드 태스크 초기화
  debugPrint('[MAIN][${_ts()}] ForegroundTask.init');
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

  debugPrint('[MAIN][${_ts()}] runApp(AppBootstrapper)');
  runApp(const AppBootstrapper());
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});
  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  // ✅ 중복 실행 방지: 한 번만 생성되는 Future
  late final Future<void> _initFuture = _initializeApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[MAIN][${_ts()}] FutureBuilder error: ${snapshot.error}');
          return const ErrorApp(message: 'DB 초기화 실패. 앱을 다시 시작해주세요.');
        }
        if (snapshot.connectionState == ConnectionState.done) {
          debugPrint('[MAIN][${_ts()}] FutureBuilder done → MyApp');
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
    debugPrint('[MAIN][${_ts()}] Firebase.initializeApp');
    await Firebase.initializeApp();

    // ✅ 개발용 리소스 등록 (비용 방지: 현재 비활성화)
    // debugPrint('[MAIN][${_ts()}] registerDevResources');
    // await registerDevResources();

    // ✅ 권한 요청
    debugPrint('[MAIN][${_ts()}] request permissions');
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
      debugPrint('[MAIN][${_ts()}] Permission.locationWhenInUse → $status');
    }

    final batteryOpt = await Permission.ignoreBatteryOptimizations.request();
    debugPrint('[MAIN][${_ts()}] Permission.ignoreBatteryOptimizations → $batteryOpt');

    // ✅ 포그라운드 서비스 시작
    debugPrint('[MAIN][${_ts()}] startService(callback: myForegroundCallback)');
    await FlutterForegroundTask.startService(
      notificationTitle: '이 서비스 알림 탭은 main에서 메시지 발신 중',
      notificationText: '포그라운드에서 대기 중',
      callback: myForegroundCallback, // ✅ 추가 핵심
    );
    debugPrint('[MAIN][${_ts()}] startService done');

    // ✅ 플로팅/메모 초기화(상태 로드). enabled가 true일 때만 mount됨
    debugPrint('[MAIN][${_ts()}] DevMemo.init');
    await DevMemo.init();
    debugPrint('[MAIN][${_ts()}] HeadMemo.init');
    await HeadMemo.init();

    // ⬇️ CommuteOutsideFloating.init 제거됨

    debugPrint('[MAIN][${_ts()}] _initializeApp done');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[MAIN][${_ts()}] build MyApp');
    return MultiProvider(
      providers: appProviders,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Easy Valet(Beta)',
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
            debugPrint('[MAIN][${_ts()}] postFrameCallback → mountIfNeeded');
            DevMemo.mountIfNeeded();
            HeadMemo.mountIfNeeded();
            // ⬇️ CommuteOutsideFloating.mountIfNeeded 제거됨
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
