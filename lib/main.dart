import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'app/auth/google_auth_session.dart';
import 'app/config/auth_config.dart';
import 'app/config/overlay_edge_side_config.dart';
import 'app/config/overlay_mode_config.dart';
import 'app/di/providers.dart';
import 'app/di/routes.dart';
import 'app/init/app_exit_flag.dart';
import 'app/init/checkout_nudge_guard.dart';
import 'app/init/app_navigator.dart';
import 'app/init/quick_overlay_main.dart';
import 'app/init/overlay_access_guard.dart';
import 'app/theme/theme_prefs_controller.dart';
import 'features/community/application/game/game_quick_actions.dart';
import 'features/chat/presentation/work_chat_alert_host.dart';
import 'features/dashboard/applications/common/firebase_google_auth_bridge.dart';
import 'features/dashboard/widgets/productivity_sheet.dart';
import 'features/dev/page/sheets/dev_quick_actions.dart';
import 'features/headquarter/application/fab/hub_quick_actions.dart';
import 'features/headquarter/page/sheets/head_memo.dart';
import 'shared/tts/application/plate_tts_event_hub.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const String kDevUnlockPassword = 'DEV-MODE-2025!';


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

Future<bool> _isSimpleAppMode() async {
  return (await OverlayAccessGuard.currentMode()) == 'simple';
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
    final h = (physicalHeight * 0.5).round();
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
  if (await OverlayAccessGuard.closeIfBlocked()) return;
  if (!await ensureOverlayPermission(context)) return;

  final requestedMode = await OverlayModeConfig.getMode();
  final isSimpleMode = await _isSimpleAppMode();
  final mode = isSimpleMode ? OverlayMode.bubble : requestedMode;
  final wire = _overlayModeToWire(mode);

  if (await FlutterOverlayWindow.isActive()) {
    if (!isSimpleMode) {
      await FlutterOverlayWindow.shareData('__mode:${wire}__');
      await FlutterOverlayWindow.shareData('__collapse__');
      return;
    }

    await FlutterOverlayWindow.closeOverlay();
    await Future<void>.delayed(const Duration(milliseconds: 120));
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

class _LifecycleOverlayRequest {
  final OverlayMode mode;
  final bool checkoutNudge;
  final bool workFinished;

  const _LifecycleOverlayRequest({
    required this.mode,
    required this.checkoutNudge,
    required this.workFinished,
  });

  String get wire {
    if (workFinished) return 'workFinished';
    if (checkoutNudge) return 'checkoutNudge';
    return _overlayModeToWire(mode);
  }

  String get title {
    if (workFinished) return 'ParkinWorkin 업무 종료 안내';
    if (checkoutNudge) return 'ParkinWorkin 퇴근 확인';
    return 'ParkinWorkin';
  }

  String get content {
    if (workFinished) return '오늘의 업무는 종료되었습니다. 앱 종료 방법을 확인해 주세요.';
    if (checkoutNudge) return '퇴근 시간이 지났습니다. 퇴근 버튼을 눌러주세요.';
    return 'Simple 모드 플로팅';
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
    await ProductivitySheet.init();

    debugPrint('[MAIN][${_ts()}] HeadHubActions.init');
    await HeadHubActions.init();

    debugPrint('[MAIN][${_ts()}] GameQuickActions.init');
    await GameQuickActions.init();

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
  String? _lifecycleOverlayWire;

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
        unawaited(GameQuickActions.terminateSession());
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
        _lifecycleOverlayWire = null;
        unawaited(GameQuickActions.terminateSession());
        unawaited(closeQuickOverlay());
        break;
    }
  }

  Future<_LifecycleOverlayRequest> _resolveLifecycleOverlayRequest() async {
    final isSimpleMode = await _isSimpleAppMode();
    final nudge = await CheckoutNudgeGuard.evaluate();

    if (isSimpleMode) {
      return const _LifecycleOverlayRequest(
        mode: OverlayMode.bubble,
        checkoutNudge: false,
        workFinished: false,
      );
    }

    if (nudge.shouldShowWorkFinished) {
      return const _LifecycleOverlayRequest(
        mode: OverlayMode.topHalf,
        checkoutNudge: false,
        workFinished: true,
      );
    }

    if (nudge.shouldNudge) {
      return const _LifecycleOverlayRequest(
        mode: OverlayMode.topHalf,
        checkoutNudge: true,
        workFinished: false,
      );
    }

    return const _LifecycleOverlayRequest(
      mode: OverlayMode.bubble,
      checkoutNudge: false,
      workFinished: false,
    );
  }

  Future<void> _applyLifecycleOverlayMode(
    _LifecycleOverlayRequest request,
  ) async {
    if (request.workFinished) {
      await FlutterOverlayWindow.shareData('__work_finished__');
    } else if (request.checkoutNudge) {
      await FlutterOverlayWindow.shareData('__checkout_nudge__');
    } else {
      await FlutterOverlayWindow.shareData('__mode:${request.wire}__');
    }
    await FlutterOverlayWindow.shareData('__collapse__');
  }

  Future<void> _startOverlayFromLifecycle() async {
    try {
      if (await OverlayAccessGuard.closeIfBlocked()) {
        _lifecycleOverlayWire = null;
        debugPrint(
            '[OVERLAY][${_ts()}] blocked app mode → skip auto start');
        return;
      }

      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        debugPrint(
            '[OVERLAY][${_ts()}] permission not granted → skip auto start');
        return;
      }

      final request = await _resolveLifecycleOverlayRequest();
      final wire = request.wire;

      if (await OverlayAccessGuard.closeIfBlocked()) {
        _lifecycleOverlayWire = null;
        debugPrint(
            '[OVERLAY][${_ts()}] blocked app mode after request → skip auto start');
        return;
      }

      if (await FlutterOverlayWindow.isActive()) {
        if (_lifecycleOverlayWire == wire) {
          await _applyLifecycleOverlayMode(request);
          return;
        }

        await FlutterOverlayWindow.closeOverlay();
        _lifecycleOverlayWire = null;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final config = await _buildOverlayWindowConfig(request.mode);

      await FlutterOverlayWindow.showOverlay(
        enableDrag: config.enableDrag,
        overlayTitle: request.title,
        overlayContent: request.content,
        flag: OverlayFlag.defaultFlag,
        alignment: config.alignment,
        positionGravity: config.positionGravity,
        height: config.height,
        width: config.width,
        startPosition: config.startPosition,
      );

      _lifecycleOverlayWire = wire;
      await _applyLifecycleOverlayMode(request);

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
        _lifecycleOverlayWire = null;
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
                GameQuickActions.mountIfNeeded();
                ProductivitySheet.mountIfNeeded();
                DevQuickActions.mountIfNeeded();
              });

              return WorkChatAlertHost(
                child: Stack(
                  children: [
                    child!,
                    const _DevUnlockHotspot(),
                  ],
                ),
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

    final input = await showDialog<String>(
      context: dialogContext,
      barrierDismissible: true,
      builder: (_) => const _DevUnlockPasswordDialog(),
    );

    if (input == kDevUnlockPassword) {
      DevQuickActions.setEnabled(true);
      DevQuickActions.mountIfNeeded();
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

class _DevUnlockPasswordDialog extends StatefulWidget {
  const _DevUnlockPasswordDialog();

  @override
  State<_DevUnlockPasswordDialog> createState() => _DevUnlockPasswordDialogState();
}

class _DevUnlockPasswordDialogState extends State<_DevUnlockPasswordDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('개발자 모드 잠금 해제'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '비밀번호',
          hintText: '비밀번호를 입력하세요',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('확인'),
        ),
      ],
    );
  }
}
