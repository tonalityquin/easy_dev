// lib/main.dart
import 'dart:async'; // ⬅️ 권한 초기화 중복 방지용 Completer / unawaited
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart'; // ✅ 오버레이 플러그인

import 'routes.dart';
import 'providers/providers.dart';

// import 'screens/dev_package/dev_memo.dart'; // ⬅️ DevMemo 더 이상 사용 안 함
import 'screens/hubs_mode/head_package/head_memo.dart';
import 'theme.dart';

import 'utils/tts/foreground_task_handler.dart';
import 'utils/app_navigator.dart';

// 🔔 로컬 알림/타임존
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata; // ← prefix 정리
import 'package:timezone/timezone.dart' as tz;

// 🔔 endTime 리마인더 서비스 + prefs
import 'services/endtime_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ⬇️ 플랫폼 분기(웹/안드/IOS)에서 사용
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

// ✅ (신규) OAuth를 앱 최초 1회만 수행하여 전역 재사용
import 'utils/google_auth_session.dart';

// ✅ (신규) 본사 허브 퀵 액션 오버레이 전역 초기화/부착
import 'screens/hubs_mode/head_package/hub_quick_actions.dart';

// ✅ (신규) DashMemo 전역 오버레이 부착을 위해 추가
import 'screens/common_package/memo_package/dash_memo.dart';

// ✅ (신규) 개발 허브 퀵 액션(DevQuickActions) 사용
import 'screens/hubs_mode/dev_package/dev_quick_actions.dart';

// ✅ (신규) 오버레이 UI(App) 위젯
import 'utils/quick_overlay_main.dart';

// ✅ (신규) 장기 근무기록 저장/분석용 트래커
import 'time_record/app_usage_tracker.dart';

// ✅ 명시적 앱 종료 플래그
import 'utils/app_exit_flag.dart';

// ✅ (신규) 오버레이 모드 설정 (버블 / 상단 포그라운드)
import 'utils/overlay_mode_config.dart';

// ✅ 전역 테마 컨트롤러
import 'theme_prefs_controller.dart';

const kIsWorkingPrefsKey = 'isWorking';

/// ✅ GSI v7 “웹 애플리케이션” 클라이언트 ID (Android에선 serverClientId로 사용)
const String kWebClientId = '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

/// 🔐 개발자 모드 잠금 해제 비밀번호(원하는 값으로 교체하세요)
const String kDevUnlockPassword = 'DEV-MODE-2025!';

/// 🔲 오버레이 윈도우 실제 크기(px 단위)
const int kOverlayWindowWidthPx = 550;
const int kOverlayWindowHeightPx = 200;

/// 상단 포그라운드 모드에서 사용할 "논리 높이(dp)".
const double kTopOverlayLogicalHeight = 520.0;

/// OverlayMode → 오버레이로 전송할 문자열 키
String _overlayModeToWire(OverlayMode mode) {
  switch (mode) {
    case OverlayMode.topHalf:
      return 'topHalf';
    case OverlayMode.bubble:
      return 'bubble';
  }
}

String _ts() => DateTime.now().toIso8601String();

// ───────────────────────────────────────────────────────────────
// flutter_local_notifications 플러그인 인스턴스 & 백그라운드 탭 핸들러
final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void myForegroundCallback() {
  debugPrint('[MAIN][${_ts()}] myForegroundCallback → setTaskHandler(MyTaskHandler)');
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse resp) {
  // TODO
}

@pragma('vm:entry-point')
void overlayMain() {
  debugPrint('[OVERLAY][${_ts()}] overlayMain() 시작');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuickOverlayApp());
}

class _OverlayWindowConfig {
  final int height;
  final int width;
  final bool enableDrag;
  final OverlayAlignment alignment;
  final PositionGravity positionGravity;
  final OverlayPosition? startPosition;

  const _OverlayWindowConfig({
    required this.height,
    required this.width,
    required this.enableDrag,
    required this.alignment,
    required this.positionGravity,
    this.startPosition,
  });
}

_OverlayWindowConfig _buildOverlayWindowConfig(OverlayMode mode) {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final physicalHeight = view.physicalSize.height;
  final physicalWidth = view.physicalSize.width;
  final devicePixelRatio = view.devicePixelRatio;

  final media = MediaQueryData.fromView(view);
  final statusBarLogical = media.padding.top;
  final statusBarPhysical = statusBarLogical * devicePixelRatio;

  if (mode == OverlayMode.topHalf) {
    final desiredPhysicalHeight = kTopOverlayLogicalHeight * devicePixelRatio;
    final availablePhysicalHeight = (physicalHeight - statusBarPhysical).clamp(0.0, physicalHeight);

    final h = desiredPhysicalHeight.clamp(0.0, availablePhysicalHeight).round();
    final w = physicalWidth.round();

    return _OverlayWindowConfig(
      height: h,
      width: w,
      enableDrag: false,
      alignment: OverlayAlignment.topLeft,
      positionGravity: PositionGravity.none,
      startPosition: OverlayPosition(0.0, statusBarLogical),
    );
  } else {
    return const _OverlayWindowConfig(
      height: kOverlayWindowHeightPx,
      width: kOverlayWindowWidthPx,
      enableDrag: true,
      alignment: OverlayAlignment.centerRight,
      positionGravity: PositionGravity.auto,
      startPosition: null,
    );
  }
}

Future<bool> ensureOverlayPermission(BuildContext context) async {
  final isGranted = await FlutterOverlayWindow.isPermissionGranted();
  if (isGranted) return true;

  final granted = await FlutterOverlayWindow.requestPermission();
  final result = granted ?? false;

  if (!result && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('다른 앱 위에 표시 권한이 필요합니다.')),
    );
  }

  return result;
}

Future<void> openQuickOverlay(BuildContext context) async {
  if (!await ensureOverlayPermission(context)) return;

  final mode = await OverlayModeConfig.getMode();
  final wire = _overlayModeToWire(mode);

  if (await FlutterOverlayWindow.isActive()) {
    await FlutterOverlayWindow.shareData('__mode:${wire}__');
    await FlutterOverlayWindow.shareData('__collapse__');
    return;
  }

  final config = _buildOverlayWindowConfig(mode);

  await FlutterOverlayWindow.showOverlay(
    enableDrag: config.enableDrag,
    overlayTitle: 'Easy Valet 오버레이',
    overlayContent: '퀵 패널 실행 중',
    flag: OverlayFlag.defaultFlag,
    alignment: config.alignment,
    positionGravity: config.positionGravity,
    height: config.height,
    width: config.width,
    startPosition: config.startPosition,
  );

  await FlutterOverlayWindow.shareData('__mode:${wire}__');
  await FlutterOverlayWindow.shareData('__collapse__');
}

Future<void> closeQuickOverlay() async {
  if (await FlutterOverlayWindow.isActive()) {
    await FlutterOverlayWindow.closeOverlay();
  }
}

class _Once {
  static bool notificationsReady = false;
  static Completer<void>? notificationsInFlight;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[MAIN][${_ts()}] initCommunicationPort');
  FlutterForegroundTask.initCommunicationPort();

  // ✅ 전역 테마 컨트롤러를 최상단에 주입 (commute 포함 모든 화면에 적용)
  debugPrint('[MAIN][${_ts()}] runApp(AppBootstrapper + ThemePrefsController)');
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemePrefsController()..load(),
      child: const AppBootstrapper(),
    ),
  );

  unawaited(_postBootstrap());
}

Future<void> _postBootstrap() async {
  try {
    await _initLocalNotifications();
  } catch (e, st) {
    debugPrint('[MAIN][${_ts()}] _initLocalNotifications error: $e');
    debugPrint(st.toString());
  }

  EndTimeReminderService.instance.attachPlugin(flnp);

  try {
    final prefs = await SharedPreferences.getInstance();
    final savedEnd = prefs.getString('endTime');
    final isWorking = prefs.getBool(kIsWorkingPrefsKey) ?? false;

    if (isWorking && savedEnd != null && savedEnd.isNotEmpty) {
      await EndTimeReminderService.instance.scheduleDailyOneHourBefore(savedEnd);
    } else {
      await EndTimeReminderService.instance.cancel();
    }
  } catch (e, st) {
    debugPrint('[MAIN][${_ts()}] EndtimeReminderService init error: $e');
    debugPrint(st.toString());
  }
}

Future<void> _initLocalNotifications() async {
  if (_Once.notificationsReady) return;

  if (_Once.notificationsInFlight != null) {
    return _Once.notificationsInFlight!.future;
  }

  final c = Completer<void>();
  _Once.notificationsInFlight = c;

  try {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await flnp.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {},
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      final enabled = await androidImpl?.areNotificationsEnabled();
      if (enabled == false) {
        await androidImpl?.requestNotificationsPermission();
      }

      const channel = AndroidNotificationChannel(
        'easydev_reminders',
        '근무 리마인더',
        description: '퇴근 1시간 전 알림 채널',
        importance: Importance.high,
      );
      await androidImpl?.createNotificationChannel(channel);
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImpl = flnp.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _Once.notificationsReady = true;
    c.complete();
  } catch (e, st) {
    if (!c.isCompleted) {
      c.completeError(e, st);
    }
    debugPrint('[MAIN][${_ts()}] _initLocalNotifications exception: $e');
    debugPrint(st.toString());
  } finally {
    _Once.notificationsInFlight = null;
  }
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
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

        // ✅ 로딩 화면도 전역 테마를 따르도록 Consumer 적용
        return Consumer<ThemePrefsController>(
          builder: (context, themeCtrl, _) {
            return MaterialApp(
              theme: themeCtrl.buildLightTheme(),
              darkTheme: themeCtrl.buildDarkTheme(),
              themeMode: themeCtrl.themeMode,
              home: const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _initializeApp() async {
    debugPrint('[MAIN][${_ts()}] Firebase.initializeApp');
    await Firebase.initializeApp();

    debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init (one-time OAuth)');
    try {
      await GoogleAuthSession.instance.init(serverClientId: kWebClientId);
      debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init done');
    } catch (e) {
      debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init failed: $e');
    }

    debugPrint('[MAIN][${_ts()}] request permissions');
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
      debugPrint('[MAIN][${_ts()}] Permission.locationWhenInUse → $status');
    }

    final batteryOpt = await Permission.ignoreBatteryOptimizations.request();
    debugPrint('[MAIN][${_ts()}] Permission.ignoreBatteryOptimizations → $batteryOpt');

    debugPrint('[MAIN][${_ts()}] startService(callback: myForegroundCallback)');
    await FlutterForegroundTask.startService(
      notificationTitle: '이 서비스 알림 탭은 main에서 메시지 발신 중',
      notificationText: '포그라운드에서 대기 중',
      callback: myForegroundCallback,
    );
    debugPrint('[MAIN][${_ts()}] startService done');

    debugPrint('[MAIN][${_ts()}] HeadMemo.init');
    await HeadMemo.init();

    debugPrint('[MAIN][${_ts()}] DashMemo.init');
    await DashMemo.init();

    debugPrint('[MAIN][${_ts()}] HeadHubActions.init');
    await HeadHubActions.init();

    debugPrint('[MAIN][${_ts()}] DevQuickActions.init');
    await DevQuickActions.init();

    debugPrint('[MAIN][${_ts()}] _initializeApp done');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUsageTracker.instance.onStateChange(AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[LIFECYCLE][${_ts()}] $state');

    AppUsageTracker.instance.onStateChange(state);

    if (AppExitFlag.isExiting) {
      if (state == AppLifecycleState.detached) {
        unawaited(closeQuickOverlay());
        AppExitFlag.reset();
      }
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _stopOverlayFromLifecycle();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _startOverlayFromLifecycle();
        break;

      case AppLifecycleState.detached:
        unawaited(closeQuickOverlay());
        break;
    }
  }

  Future<void> _startOverlayFromLifecycle() async {
    try {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        debugPrint('[OVERLAY][${_ts()}] permission not granted → skip auto start');
        return;
      }

      final mode = await OverlayModeConfig.getMode();
      final wire = _overlayModeToWire(mode);

      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData('__mode:${wire}__');
        await FlutterOverlayWindow.shareData('__collapse__');
        return;
      }

      final config = _buildOverlayWindowConfig(mode);

      await FlutterOverlayWindow.showOverlay(
        enableDrag: config.enableDrag,
        overlayTitle: 'Easy Valet',
        overlayContent: 'Simple 모드 플로팅',
        flag: OverlayFlag.defaultFlag,
        alignment: config.alignment,
        positionGravity: config.positionGravity,
        height: config.height,
        width: config.width,
        startPosition: config.startPosition,
      );

      await FlutterOverlayWindow.shareData('__mode:${wire}__');
      await FlutterOverlayWindow.shareData('__collapse__');

      debugPrint('[OVERLAY][${_ts()}] auto start overlay from lifecycle (mode=$wire)');
    } catch (e, st) {
      debugPrint('[OVERLAY][${_ts()}] auto start error: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _stopOverlayFromLifecycle() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        debugPrint('[OVERLAY][${_ts()}] auto stop overlay from lifecycle');
      }
    } catch (e, st) {
      debugPrint('[OVERLAY][${_ts()}] auto stop error: $e');
      debugPrint(st.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[MAIN][${_ts()}] build MyApp');

    return MultiProvider(
      providers: appProviders,
      child: Consumer<ThemePrefsController>(
        builder: (context, themeCtrl, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Easy Valet(Beta)',

            // ✅ 전역 테마 적용: commute 포함 전체 화면 반영
            theme: themeCtrl.buildLightTheme(),
            darkTheme: themeCtrl.buildDarkTheme(),
            themeMode: themeCtrl.themeMode,

            initialRoute: AppRoutes.selector,
            routes: appRoutes,
            onUnknownRoute: (_) => MaterialPageRoute(builder: (_) => const NotFoundPage()),

            navigatorKey: AppNavigator.key,
            scaffoldMessengerKey: AppNavigator.scaffoldMessengerKey,

            builder: (context, child) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                debugPrint('[MAIN][${_ts()}] postFrameCallback → mountIfNeeded');
                HeadHubActions.mountIfNeeded();
                DashMemo.mountIfNeeded();
                DevQuickActions.mountIfNeeded();
              });

              return Stack(
                children: [
                  child!,
                  const _DevUnlockHotspot(),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DevUnlockHotspot extends StatefulWidget {
  const _DevUnlockHotspot();

  @override
  State<_DevUnlockHotspot> createState() => _DevUnlockHotspotState();
}

class _DevUnlockHotspotState extends State<_DevUnlockHotspot> {
  int _tapCount = 0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _onTap() {
    _tapCount++;
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 550), () {
      _tapCount = 0;
    });

    if (_tapCount >= 3) {
      _tapCount = 0;
      _resetTimer?.cancel();
      _askPassword(context);
    }
  }

  Future<void> _askPassword(BuildContext ctx) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('개발자 모드 잠금 해제'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '비밀번호',
              hintText: '비밀번호를 입력하세요',
            ),
            onSubmitted: (_) => Navigator.of(context).pop(true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      final input = controller.text;
      if (input == kDevUnlockPassword) {
        DevQuickActions.setEnabled(true);
        DevQuickActions.mountIfNeeded();

        AppNavigator.messenger?.showSnackBar(
          const SnackBar(
            content: Text('개발 허브 퀵 액션이 활성화되었습니다.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        AppNavigator.messenger?.showSnackBar(
          const SnackBar(
            content: Text('비밀번호가 올바르지 않습니다.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: const SizedBox(
          width: 48,
          height: 48,
        ),
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
