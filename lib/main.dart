import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app/config/auth_config.dart';
import 'app/config/overlay_edge_side_config.dart';
import 'app/config/overlay_mode_config.dart';
import 'app/di/providers.dart';
import 'app/di/routes.dart';
import 'app/init/app_exit_flag.dart';
import 'app/init/app_navigator.dart';
import 'app/theme/theme_prefs_controller.dart';
import 'features/dev/page/sheets/dev_quick_actions.dart';
import 'features/headquarter/application/hub_quick_actions.dart';
import 'features/headquarter/page/sheets/head_memo.dart';
import 'utils/auth/google_auth_session.dart';
import 'services/firebase_google_auth_bridge.dart';
import 'screens/common_package/memo_package/chat_bot.dart';
import 'utils/quick_overlay_main.dart';
import 'utils/tts/plate_tts_event_hub.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';


const String kDevUnlockPassword = 'DEV-MODE-2025!';

const double kTopOverlayLogicalHeight = 520.0;

final _devUnlockRouteTracker = _DevUnlockRouteTracker();

class _DevUnlockRouteTracker extends NavigatorObserver {
  final ValueNotifier<int> stackDepth = ValueNotifier<int>(0);
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  void _publish() {
    stackDepth.value = _routes.length;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _routes.add(route);
    _publish();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _publish();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _publish();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _routes.remove(oldRoute);
    }
    if (newRoute != null) {
      _routes.remove(newRoute);
      _routes.add(newRoute);
    }
    _publish();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

String _overlayModeToWire(OverlayMode mode) {
  switch (mode) {
    case OverlayMode.topHalf:
      return 'topHalf';
    case OverlayMode.bubble:
      return 'bubble';
  }
}

String _ts() => DateTime.now().toIso8601String();

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

Future<_OverlayWindowConfig> _buildOverlayWindowConfig(OverlayMode mode) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final physicalHeight = view.physicalSize.height;
  final physicalWidth = view.physicalSize.width;
  final devicePixelRatio = view.devicePixelRatio;

  final media = MediaQueryData.fromView(view);
  final statusBarLogical = media.padding.top;

  if (mode == OverlayMode.topHalf) {
    final desiredPhysicalHeight = kTopOverlayLogicalHeight * devicePixelRatio;
    final h = desiredPhysicalHeight.clamp(0.0, physicalHeight).round();
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
    final side = await OverlayEdgeSideConfig.getSide();

    final stripPhysicalW = (kEdgeStripWidth * devicePixelRatio).round();
    final stripPhysicalH = physicalHeight.round();

    final alignment = (side == OverlayEdgeSide.left)
        ? OverlayAlignment.topLeft
        : OverlayAlignment.topRight;
    return _OverlayWindowConfig(
      height: stripPhysicalH,
      width: stripPhysicalW,
      enableDrag: false,
      alignment: alignment,
      positionGravity: PositionGravity.none,
    );
  }
}

Future<bool> ensureOverlayPermission(BuildContext context) async {
  final isGranted = await FlutterOverlayWindow.isPermissionGranted();
  if (isGranted) return true;
  if (!context.mounted) return false;
  return false;
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

  final config = await _buildOverlayWindowConfig(mode);

  await FlutterOverlayWindow.showOverlay(
    enableDrag: config.enableDrag,
    overlayTitle: 'ParkinWorkin 오버레이',
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);

  final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
  final deviceLocaleTag =
      (deviceLocale.countryCode != null && deviceLocale.countryCode!.isNotEmpty)
          ? '${deviceLocale.languageCode}_${deviceLocale.countryCode}'
          : deviceLocale.languageCode;

  Intl.defaultLocale = deviceLocaleTag;
  if (deviceLocaleTag != 'ko_KR') {
    try {
      await initializeDateFormatting(deviceLocaleTag, null);
    } catch (_) {}
  }

  debugPrint('[MAIN][${_ts()}] initCommunicationPort');
  FlutterForegroundTask.initCommunicationPort();
  PlateTtsEventHub.ensureStarted();

  debugPrint('[MAIN][${_ts()}] runApp(AppBootstrapper + ThemePrefsController)');
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemePrefsController()..load(),
      child: const AppBootstrapper(),
    ),
  );
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
    AuthConfig.validate();

    debugPrint('[MAIN][${_ts()}] Firebase.initializeApp');
    await Firebase.initializeApp();

    debugPrint('[MAIN][${_ts()}] FirebaseGoogleAuthBridge.configureRuntime');
    try {
      await FirebaseGoogleAuthBridge.instance.configureRuntime();
      debugPrint(
          '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.configureRuntime done uid=${FirebaseAuth.instance.currentUser?.uid} email=${FirebaseAuth.instance.currentUser?.email} anonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}');
    } catch (e, st) {
      debugPrint(
          '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.configureRuntime failed: $e\n$st');
    }

    debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init (one-time OAuth)');
    try {
      await GoogleAuthSession.instance.init(
        serverClientId: AuthConfig.webClientId,
      );
      debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init done');
    } catch (e, st) {
      debugPrint('[MAIN][${_ts()}] GoogleAuthSession.init failed: $e\n$st');
    }

    debugPrint(
        '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.bootstrapWithExistingGoogleUser');
    try {
      final existingGoogleUser = GoogleAuthSession.instance.currentUser;
      debugPrint(
          '[MAIN][${_ts()}] existing Google user email=${existingGoogleUser?.email}');
      final ok = await FirebaseGoogleAuthBridge.instance
          .bootstrapWithExistingGoogleUser(existingGoogleUser);
      debugPrint(
          '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.bootstrapWithExistingGoogleUser done ok=$ok uid=${FirebaseAuth.instance.currentUser?.uid} email=${FirebaseAuth.instance.currentUser?.email} anonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}');
    } catch (e, st) {
      debugPrint(
          '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.bootstrapWithExistingGoogleUser failed: $e\n$st');
    }

    debugPrint('[MAIN][${_ts()}] HeadMemo.init');
    await HeadMemo.init();

    debugPrint('[MAIN][${_ts()}] DashMemo.init');
    await ChatBot.init();

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
        debugPrint(
            '[OVERLAY][${_ts()}] permission not granted → skip auto start');
        return;
      }

      final mode = await OverlayModeConfig.getMode();
      final wire = _overlayModeToWire(mode);

      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData('__mode:${wire}__');
        await FlutterOverlayWindow.shareData('__collapse__');
        return;
      }

      final config = await _buildOverlayWindowConfig(mode);

      await FlutterOverlayWindow.showOverlay(
        enableDrag: config.enableDrag,
        overlayTitle: 'ParkinWorkin',
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

      debugPrint(
          '[OVERLAY][${_ts()}] auto start overlay from lifecycle (mode=$wire)');
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
            title: 'ParkinWorkin',
            theme: themeCtrl.buildLightTheme(),
            darkTheme: themeCtrl.buildDarkTheme(),
            themeMode: themeCtrl.themeMode,
            initialRoute: AppRoutes.startGate,
            routes: appRoutes,
            onUnknownRoute: (_) =>
                MaterialPageRoute(builder: (_) => const NotFoundPage()),
            navigatorKey: AppNavigator.key,
            navigatorObservers: [_devUnlockRouteTracker],
            builder: (context, child) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                debugPrint(
                    '[MAIN][${_ts()}] postFrameCallback → mountIfNeeded');
                HeadHubActions.mountIfNeeded();
                ChatBot.mountIfNeeded();
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
      _askPassword();
    }
  }

  Future<void> _askPassword() async {
    final dialogContext = AppNavigator.context;
    if (dialogContext == null) return;

    final controller = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: dialogContext,
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
        }
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _devUnlockRouteTracker.stackDepth,
      builder: (context, stackDepth, _) {
        if (stackDepth > 1) {
          return const SizedBox.shrink();
        }

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
      },
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
