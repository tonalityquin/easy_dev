import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app/auth/google_auth_session.dart';
import 'app/config/auth_config.dart';
import 'app/di/providers.dart';
import 'app/di/routes.dart';
import 'app/init/app_exit_flag.dart';
import 'app/init/app_mode_migration.dart';
import 'app/init/app_navigator.dart';
import 'app/init/work_status_notification.dart';
import 'app/theme/theme_prefs_controller.dart';
import 'features/chat/presentation/work_chat_alert_host.dart';
import 'features/community/application/game/game_quick_actions.dart';
import 'features/dashboard/applications/common/firebase_google_auth_bridge.dart';
import 'features/dashboard/widgets/productivity_sheet.dart';
import 'features/dev/page/sheets/dev_quick_actions.dart';
import 'features/dev/presentation/debug_session_visual_overlay.dart';
import 'features/headquarter/page/sheets/head_memo.dart';
import 'shared/tts/application/plate_tts_event_hub.dart';

String _ts() => DateTime.now().toIso8601String();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);

  final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
  final deviceLocaleTag =
      deviceLocale.countryCode != null && deviceLocale.countryCode!.isNotEmpty
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
  WorkStatusNotificationController.initializeForegroundTask();
  WorkStatusNotificationController.initializeTaskEventListener();
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
    return FutureBuilder<void>(
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
    await AppModeMigration.migrateLegacyMode();

    debugPrint('[MAIN][${_ts()}] Firebase.initializeApp');
    await Firebase.initializeApp();

    debugPrint('[MAIN][${_ts()}] FirebaseGoogleAuthBridge.configureRuntime');
    try {
      await FirebaseGoogleAuthBridge.instance.configureRuntime();
      debugPrint(
        '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.configureRuntime done uid=${FirebaseAuth.instance.currentUser?.uid} email=${FirebaseAuth.instance.currentUser?.email} anonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}',
      );
    } catch (e, st) {
      debugPrint(
        '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.configureRuntime failed: $e\n$st',
      );
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
      '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.bootstrapWithExistingGoogleUser',
    );
    try {
      final existingGoogleUser = GoogleAuthSession.instance.currentUser;
      debugPrint(
        '[MAIN][${_ts()}] existing Google user email=${existingGoogleUser?.email}',
      );
      final ok = await FirebaseGoogleAuthBridge.instance
          .bootstrapWithExistingGoogleUser(existingGoogleUser);
      debugPrint(
        '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.bootstrapWithExistingGoogleUser done ok=$ok uid=${FirebaseAuth.instance.currentUser?.uid} email=${FirebaseAuth.instance.currentUser?.email} anonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}',
      );
    } catch (e, st) {
      debugPrint(
        '[MAIN][${_ts()}] FirebaseGoogleAuthBridge.bootstrapWithExistingGoogleUser failed: $e\n$st',
      );
    }

    debugPrint('[MAIN][${_ts()}] HeadMemo.init');
    await HeadMemo.init();

    debugPrint('[MAIN][${_ts()}] DashMemo.init');
    await ProductivitySheet.init();

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
    WorkStatusNotificationController.recordLifecycle(state);

    if (AppExitFlag.isExiting) {
      if (state == AppLifecycleState.detached) {
        unawaited(GameQuickActions.terminateSession());
        AppExitFlag.reset();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(
        WorkStatusNotificationController.refresh(
          source: 'app_lifecycle_resumed',
        ),
      );
    }

    if (state == AppLifecycleState.detached) {
      unawaited(GameQuickActions.terminateSession());
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
            builder: (context, child) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                debugPrint('[MAIN][${_ts()}] postFrameCallback → mountIfNeeded');
                GameQuickActions.mountIfNeeded();
                ProductivitySheet.mountIfNeeded();
                DevQuickActions.mountIfNeeded();
              });

              return Stack(
                children: [
                  WorkChatAlertHost(child: child!),
                  const Positioned.fill(
                    child: DebugSessionVisualOverlay(),
                  ),
                ],
              );
            },
          );
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
