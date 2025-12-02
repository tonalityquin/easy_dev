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
import 'screens/head_package/head_memo.dart';
import 'theme.dart';

// import 'utils/init/dev_initializer.dart'; // 비상용 개발 지역 계정 임시 비활성화
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
import 'screens/head_package/hub_quick_actions.dart';

// ✅ (신규) DashMemo 전역 오버레이 부착을 위해 추가
import 'screens/type_package/common_widgets/dashboard_bottom_sheet/memo/dash_memo.dart';

// ✅ (신규) 개발 허브 퀵 액션(DevQuickActions) 사용
import 'screens/dev_package/dev_quick_actions.dart';

// ✅ (신규) 오버레이 UI(App) 위젯
import 'utils/quick_overlay_main.dart';

// ✅ (신규) 장기 근무기록 저장/분석용 트래커
import 'time_record/app_usage_tracker.dart';

// ✅ 명시적 앱 종료 플래그
import 'utils/app_exit_flag.dart';

// ✅ (신규) 오버레이 모드 설정 (버블 / 상단 포그라운드)
import 'utils/overlay_mode_config.dart';

const kIsWorkingPrefsKey = 'isWorking';

/// ✅ GSI v7 “웹 애플리케이션” 클라이언트 ID (Android에선 serverClientId로 사용)
const String kWebClientId = '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

/// 🔐 개발자 모드 잠금 해제 비밀번호(원하는 값으로 교체하세요)
const String kDevUnlockPassword = 'DEV-MODE-2025!';

/// 🔲 오버레이 윈도우 실제 크기(px 단위)
///  - QuickOverlayHome 의 UI는 이 크기 안에서만 배치됨 (bubble 모드 기준)
///  - topHalf 모드는 "고정 logical height" 를 px 로 변환해서 사용
const int kOverlayWindowWidthPx = 550;
const int kOverlayWindowHeightPx = 200;

/// 상단 포그라운드 모드에서 사용할 "논리 높이(dp)".
/// 실제 디바이스에서는 이 값 * devicePixelRatio 만큼의 px 높이가 사용됨.
/// 내용이 스크롤 없이 모두 들어갈 수 있도록 여유 있게 잡은 값.
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
  // 포그라운드 태스크가 시작될 때 TaskHandler를 등록
  debugPrint('[MAIN][${_ts()}] myForegroundCallback → setTaskHandler(MyTaskHandler)');
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse resp) {
  // TODO: 알림 탭 시 라우팅/처리가 필요하면 구현 (resp.payload 참조 가능)
}

// ───────────────────────────────────────────────────────────────
// ✅ flutter_overlay_window 가 호출하는 “오버레이 전용 엔트리포인트”
//    (Android 서비스에서 별도의 Flutter 엔진을 띄울 때 사용)
@pragma('vm:entry-point')
void overlayMain() {
  debugPrint('[OVERLAY][${_ts()}] overlayMain() 시작');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuickOverlayApp());
}

// ───────────────────────────────────────────────────────────────
// ✅ 오버레이 윈도우 geometry 계산 공통 유틸 (중복 제거용)

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

///
/// - topHalf 모드:
///   · kTopOverlayLogicalHeight(dp) 를 사용해 "내용이 다 보이는" 고정 높이로 계산
///   · statusBar 높이만큼 Y 오프셋(startPosition.y) 을 줘서
///     **핸드폰 상태창(상단 시스템 바)을 절대 침범하지 않도록** 함
///   · 전체 화면 높이를 넘어가지 않도록 clamp
///
/// - bubble 모드:
///   · 기존 고정 width/height, 드래그 가능
///
_OverlayWindowConfig _buildOverlayWindowConfig(OverlayMode mode) {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final physicalHeight = view.physicalSize.height;
  final physicalWidth = view.physicalSize.width;
  final devicePixelRatio = view.devicePixelRatio;

  final media = MediaQueryData.fromView(view);
  final statusBarLogical = media.padding.top; // dp 단위
  final statusBarPhysical = statusBarLogical * devicePixelRatio;

  if (mode == OverlayMode.topHalf) {
    final desiredPhysicalHeight = kTopOverlayLogicalHeight * devicePixelRatio;

    // 상태창 아래에서 시작하므로, 실제로 쓸 수 있는 영역은 (전체 - statusBar 높이)
    final availablePhysicalHeight = (physicalHeight - statusBarPhysical).clamp(0.0, physicalHeight);

    final h = desiredPhysicalHeight.clamp(0.0, availablePhysicalHeight).round();
    final w = physicalWidth.round();

    return _OverlayWindowConfig(
      height: h,
      width: w,
      enableDrag: false,
      // 상단 포그라운드 모드는 위치 이동 불가
      alignment: OverlayAlignment.topLeft,
      positionGravity: PositionGravity.none,
      // 🔴 dp 단위의 논리 좌표 사용 (double)
      startPosition: OverlayPosition(0.0, statusBarLogical),
    );
  } else {
    // 버블 모드: 기존 고정 크기 + 드래그 가능
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

// ───────────────────────────────────────────────────────────────
// ✅ Android 오버레이(다른 앱 위 플로팅 패널) 관련 유틸 함수

/// SYSTEM_ALERT_WINDOW 권한 확인 + 필요 시 설정 화면으로 이동
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

/// 앱 어디서든 `openQuickOverlay(context)` 를 호출하면
/// overlayMain → QuickOverlayApp 이 뜨게 됩니다.
/// 선택된 모드(버블 / 상단 포그라운드)에 따라 윈도우 크기와 UI가 달라집니다.
Future<void> openQuickOverlay(BuildContext context) async {
  if (!await ensureOverlayPermission(context)) return;

  // 현재 선택된 오버레이 모드
  final mode = await OverlayModeConfig.getMode();
  final wire = _overlayModeToWire(mode);

  // 이미 떠 있으면 다시 띄우지 않고 모드/상태만 갱신
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

  // 오버레이에 현재 모드와 초기 상태 전달
  await FlutterOverlayWindow.shareData('__mode:${wire}__');
  await FlutterOverlayWindow.shareData('__collapse__');
}

/// 떠 있는 오버레이를 닫고 싶을 때 사용
Future<void> closeQuickOverlay() async {
  if (await FlutterOverlayWindow.isActive()) {
    await FlutterOverlayWindow.closeOverlay();
  }
}

// ───────────────────────────────────────────────────────────────
// ⬇️ 알림 초기화 중복 실행 방지 게이트
class _Once {
  static bool notificationsReady = false; // 이미 한 번 끝났으면 true
  static Completer<void>? notificationsInFlight; // 동시에 들어오면 합류
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ UI <-> Task 통신 포트 초기화 (sendDataToTask / onReceiveData 사용을 위해 필요)
  debugPrint('[MAIN][${_ts()}] initCommunicationPort');
  FlutterForegroundTask.initCommunicationPort();

  // ✅ 먼저 Flutter UI를 띄운다.
  debugPrint('[MAIN][${_ts()}] runApp(AppBootstrapper)');
  runApp(const AppBootstrapper());

  // ✅ 그 다음에 비동기로 알림/리마인더 초기화를 수행 (UI를 막지 않도록)
  unawaited(_postBootstrap());
}

Future<void> _postBootstrap() async {
  try {
    // 🔔 로컬 알림/타임존 초기화 (게이트 적용)
    await _initLocalNotifications();
  } catch (e, st) {
    debugPrint('[MAIN][${_ts()}] _initLocalNotifications error: $e');
    debugPrint(st.toString());
  }

  // 🔔 서비스에 플러그인 주입 (알림 예약/취소에 사용)
  EndtimeReminderService.instance.attachPlugin(flnp);

  // 🔔 앱 시작 시 보강: prefs의 endTime & isWorking 기준으로 예약/취소 정합화
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedEnd = prefs.getString('endTime');
    final isWorking = prefs.getBool(kIsWorkingPrefsKey) ?? false;

    if (isWorking && savedEnd != null && savedEnd.isNotEmpty) {
      await EndtimeReminderService.instance.scheduleDailyOneHourBefore(savedEnd);
    } else {
      await EndtimeReminderService.instance.cancel();
    }
  } catch (e, st) {
    debugPrint('[MAIN][${_ts()}] EndtimeReminderService init error: $e');
    debugPrint(st.toString());
  }
}

// 🔔 로컬 알림/타임존 초기화 + 권한/채널 생성 (중복 호출 안전)
Future<void> _initLocalNotifications() async {
  // 이미 완료되었으면 즉시 반환
  if (_Once.notificationsReady) return;

  // 누군가 진행 중이면 그 Future에 합류
  if (_Once.notificationsInFlight != null) {
    return _Once.notificationsInFlight!.future;
  }

  final c = Completer<void>();
  _Once.notificationsInFlight = c;

  try {
    // 타임존 초기화(KST)
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    // 플러그인 초기화
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await flnp.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        // 포그라운드 상태에서 알림 탭 시 처리 (필요 시 라우팅)
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // ─── 플랫폼별 권한 요청/채널 생성 ───
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      // 이미 허용 상태면 요청 생략
      final enabled = await androidImpl?.areNotificationsEnabled();
      if (enabled == false) {
        await androidImpl?.requestNotificationsPermission();
      }

      // 알림 채널 생성(안드로이드)
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

    // ✅ (신규) OAuth 1회 초기화 — 이후 전역 재사용
    debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init (one-time OAuth)');
    try {
      await GoogleAuthSession.instance.init(serverClientId: kWebClientId);
      debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init done');
    } catch (e) {
      debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init failed: $e');
    }

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
      callback: myForegroundCallback,
    );
    debugPrint('[MAIN][${_ts()}] startService done');

    // ✅ (유지) HeadMemo 초기화
    debugPrint('[MAIN][${_ts()}] HeadMemo.init');
    await HeadMemo.init();

    // ✅ DashMemo 전역 초기화 — 이후 mountIfNeeded로 부착
    debugPrint('[MAIN][${_ts()}] DashMemo.init');
    await DashMemo.init();

    // ✅ 본사 허브 퀵 액션 버블 전역 초기화
    debugPrint('[MAIN][${_ts()}] HeadHubActions.init');
    await HeadHubActions.init();

    // ✅ (신규) 개발 허브 퀵 액션(DevQuickActions) 초기화 (기본 OFF)
    debugPrint('[MAIN][${_ts()}] DevQuickActions.init');
    await DevQuickActions.init();

    debugPrint('[MAIN][${_ts()}] _initializeApp done');
  }
}

// ───────────────────────────────────────────────────────────────
// ⬇️ 여기부터: 앱 라이프사이클에 따라 플로팅 버블/포그라운드 패널 자동 ON/OFF
//     + AppUsageTracker 를 통해 장기 근무기록 DB에 저장
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

    // 앱이 처음 켜졌다고 가정하고 한 번 초기 상태 기록
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

    // ✅ 포그라운드/백그라운드 시간 기록 (DB에 interval 저장)
    AppUsageTracker.instance.onStateChange(state);

    // 🔐 1) 헤더에서 "앱 종료" 버튼을 눌러 명시적 종료 중일 때
    if (AppExitFlag.isExiting) {
      // 이 플로우에서는 자동 오버레이 ON/OFF를 하지 않는다.
      if (state == AppLifecycleState.detached) {
        // 앱 엔진이 완전히 떨어지기 직전 마지막 정리
        unawaited(closeQuickOverlay());
        AppExitFlag.reset(); // 종료 플로우 끝, 플래그 리셋
      }
      return; // ✅ 여기서 종료 → inactive/paused/hidden 에서 오버레이 안 켜짐
    }

    // 🔓 2) 일반 라이프사이클(홈 버튼, 앱 전환 등)에서는 기존 동작 유지
    switch (state) {
      case AppLifecycleState.resumed:
        // 앱이 다시 앞으로 나왔을 때 → 플로팅 버블/포그라운드 패널 자동 종료
        _stopOverlayFromLifecycle();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 홈 버튼 / 앱 전환 등으로 백그라운드로 갈 때 → 오버레이 자동 시작
        _startOverlayFromLifecycle();
        break;

      case AppLifecycleState.detached:
        // 일반적인 detach(시스템 종료 등)에서도 혹시 남아 있던 오버레이 정리
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

      // 현재 선택된 모드
      final mode = await OverlayModeConfig.getMode();
      final wire = _overlayModeToWire(mode);

      if (await FlutterOverlayWindow.isActive()) {
        // 이미 떠 있으면 모드/상태만 갱신
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
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Easy Valet(Beta)',
        theme: appTheme,
        initialRoute: AppRoutes.selector,
        routes: appRoutes,
        onUnknownRoute: (_) => MaterialPageRoute(builder: (_) => const NotFoundPage()),

        // ✅ 앱 전역 네비게이터 키(시트 컨텍스트 안정성)
        navigatorKey: AppNavigator.key,
        scaffoldMessengerKey: AppNavigator.scaffoldMessengerKey,

        // ✅ 첫 프레임 후 필요 시 오버레이 부착 + 숨김 제스처(비밀번호)로 DevQuickActions 켜기
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[MAIN][${_ts()}] postFrameCallback → mountIfNeeded');

            // DevMemo / HeadMemo 는 자동 부착 X
            HeadHubActions.mountIfNeeded();
            DashMemo.mountIfNeeded();
            DevQuickActions.mountIfNeeded();
          });

          return Stack(
            children: [
              child!,
              const _DevUnlockHotspot(), // 🔐 개발자 모드 잠금 해제 핫스팟
            ],
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
