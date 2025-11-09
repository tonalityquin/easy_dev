import 'dart:async'; // ⬅️ 권한 초기화 중복 방지용 Completer
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

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

const kIsWorkingPrefsKey = 'isWorking';

/// ✅ GSI v7 “웹 애플리케이션” 클라이언트 ID (Android에선 serverClientId로 사용)
const String kWebClientId =
    '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

/// 🔐 개발자 모드 잠금 해제 비밀번호(원하는 값으로 교체하세요)
const String kDevUnlockPassword = 'DEV-MODE-2025!';

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

  // (요청에 따라 ForegroundTask.init 제거)

  // 🔔 로컬 알림 초기화 (게이트 적용)
  await _initLocalNotifications();

  // 🔔 서비스에 플러그인 주입 (알림 예약/취소에 사용)
  EndtimeReminderService.instance.attachPlugin(flnp);

  // 🔔 앱 시작 시 보강: prefs의 endTime & isWorking 기준으로 예약/취소 정합화
  final prefs = await SharedPreferences.getInstance();
  final savedEnd = prefs.getString('endTime');
  final isWorking = prefs.getBool(kIsWorkingPrefsKey) ?? false;

  if (isWorking && savedEnd != null && savedEnd.isNotEmpty) {
    await EndtimeReminderService.instance.scheduleDailyOneHourBefore(savedEnd);
  } else {
    await EndtimeReminderService.instance.cancel();
  }

  debugPrint('[MAIN][${_ts()}] runApp(AppBootstrapper)');
  runApp(const AppBootstrapper());
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

    // ─── 플랫폼별 권한 요청/채널 생성: 교차 플랫폼 API 호출 금지 ───
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl =
      flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      // 이미 허용 상태면 요청 생략
      final enabled = await androidImpl?.areNotificationsEnabled();
      if (enabled == false) {
        // Android 13+ 에서만 실제 요청이 발생 (API 내부에서 분기 처리됨)
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
      final iosImpl =
      flnp.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      // 이미 허용되어 있으면 내부적으로 no-op
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _Once.notificationsReady = true;
    c.complete();
  } catch (e, st) {
    if (!c.isCompleted) c.completeError(e, st);
    rethrow;
  } finally {
    _Once.notificationsInFlight = null; // 다음 호출은 ready 플래그로 즉시 반환
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
      // 초기 인증 실패하더라도 앱은 실행되며, 이후 기능에서 재시도 가능
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
      callback: myForegroundCallback, // ✅ 추가 핵심
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

        // ✅ 앱 전역 네비게이터 키(시트 컨텍스트 안정성)
        navigatorKey: AppNavigator.key,
        scaffoldMessengerKey: AppNavigator.scaffoldMessengerKey,

        // ✅ 첫 프레임 후 필요 시 오버레이 부착 + 숨김 제스처(비밀번호)로 DevQuickActions 켜기
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[MAIN][${_ts()}] postFrameCallback → mountIfNeeded');

            // ⛔️ DevMemo 플로팅 버블 제거 → 자동 부착 없음
            // DevMemo: no mount call

            // HeadMemo: 버블 제거 → mountIfNeeded 호출 없음 (기존 주석 유지)
            // HeadMemo: no mount call

            // ✅ (유지) 허브 퀵 액션 / DashMemo / DevQuickActions 오버레이 부착 시도
            HeadHubActions.mountIfNeeded();
            DashMemo.mountIfNeeded();
            DevQuickActions.mountIfNeeded();
          });

          // ⬇️ 숨김 제스처(우상단 48x48 영역 '트리플 탭') + 비밀번호로 DevQuickActions 활성화
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

/// 🔐 우상단 작은 투명 핫스팟을 '트리플 탭'하면 비밀번호 입력 다이얼로그를 띄우고,
///     올바르면 DevQuickActions 를 ON 합니다. (상태는 SharedPreferences에 저장)
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
        // 바로 부착 시도(다음 프레임에서 overlay가 들어오지만 안전하게 한 번 더 시도)
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
    // 우상단 48x48 투명 터치 영역 (상태바/앱바 버튼과 충돌을 줄이기 위해 살짝 안쪽으로)
    return Positioned(
      top: 12,
      right: 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: const SizedBox(
          width: 48,
          height: 48,
          // 디버깅 시 아래 박스를 잠시 켜면 위치 확인 쉬움:
          // child: DecoratedBox(decoration: BoxDecoration(color: Colors.red.withOpacity(.1))),
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
