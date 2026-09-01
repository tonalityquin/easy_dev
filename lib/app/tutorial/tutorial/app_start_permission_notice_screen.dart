import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../app/tutorial/widgets/app_start_cinematic_reveal.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/selector/application/dev_auth.dart';

class AppStartPermissionNoticeScreen extends StatefulWidget {
  const AppStartPermissionNoticeScreen({super.key});

  @override
  State<AppStartPermissionNoticeScreen> createState() =>
      _AppStartPermissionNoticeScreenState();
}

class _AppStartPermissionNoticeScreenState
    extends State<AppStartPermissionNoticeScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _messages = <String>[
    '앱에서 안내한 설정과 다르게 기기의 권한을 임의로 변경할 경우 서비스 이용에 문제가 발생할 수 있습니다.',
    '이로 인한 이용 장애에 대해서는 책임지지 않습니다.',
    '문제가 발생한 경우 앱 캐시 및 데이터를 삭제한 뒤 재설치하여 초기 설정을 다시 진행해 주세요.',
  ];

  static const List<Duration> _holdDurations = <Duration>[
    Duration(milliseconds: 2800),
    Duration(milliseconds: 2200),
    Duration(milliseconds: 3000),
  ];

  late final AnimationController _controller;
  int _messageIndex = 0;
  int _sequenceGeneration = 0;
  bool _exiting = false;
  bool _developerStatusOpen = false;
  AppStartUserPurpose? _purpose;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 720),
    );
    AppStartDebugTrace.log('permission_notice', 'screen_init');
    DevAuth.isDevModeEnabled();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    final purpose = await AppStartFlowPrefs.getUserPurpose();
    if (!mounted) return;
    if (purpose == null) {
      AppStartDebugTrace.log(
        'permission_notice',
        'missing_user_purpose',
      );
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.startGate,
        (route) => false,
      );
      return;
    }

    _purpose = purpose;
    AppStartDebugTrace.log(
      'permission_notice',
      'purpose_loaded',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );
    _startSequence();
  }

  Future<void> _startSequence({int startIndex = 0}) async {
    final generation = ++_sequenceGeneration;
    for (var i = startIndex; i < _messages.length; i++) {
      if (!mounted || generation != _sequenceGeneration) return;
      setState(() {
        _messageIndex = i;
        _exiting = false;
      });
      _controller.value = 0;
      AppStartDebugTrace.log(
        'permission_notice',
        'message_enter_start',
        meta: <String, Object?>{
          'messageIndex': i + 1,
          'messageCount': _messages.length,
        },
      );

      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        try {
          await _controller.forward(from: 0).orCancel;
        } on TickerCanceled {
          return;
        }
      }

      if (!mounted || generation != _sequenceGeneration) return;
      AppStartDebugTrace.log(
        'permission_notice',
        'message_visible',
        meta: <String, Object?>{'messageIndex': i + 1},
      );

      await Future<void>.delayed(_holdDurations[i]);
      if (!mounted || generation != _sequenceGeneration) return;

      setState(() => _exiting = true);
      AppStartDebugTrace.log(
        'permission_notice',
        'message_exit_start',
        meta: <String, Object?>{'messageIndex': i + 1},
      );

      if (_reduceMotion) {
        _controller.value = 0;
      } else {
        try {
          await _controller.reverse(from: 1).orCancel;
        } on TickerCanceled {
          return;
        }
      }

      if (!mounted || generation != _sequenceGeneration) return;
      AppStartDebugTrace.log(
        'permission_notice',
        'message_exit_complete',
        meta: <String, Object?>{'messageIndex': i + 1},
      );
    }

    if (!mounted || generation != _sequenceGeneration) return;
    await AppStartFlowPrefs.setPermissionNoticeDone(true);
    AppStartDebugTrace.log(
      'permission_notice',
      'notice_complete',
      meta: <String, Object?>{
        'purpose': _purpose?.storageValue ?? 'unknown',
      },
    );
    if (!mounted || generation != _sequenceGeneration) return;
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.appStartPermissionSetup,
    );
  }

  Future<void> _showDeveloperStatus() async {
    if (_developerStatusOpen) return;
    setState(() => _developerStatusOpen = true);
    _sequenceGeneration++;
    _controller.stop();
    AppStartDebugTrace.log(
      'permission_notice',
      'sequence_paused_for_developer_status',
      meta: <String, Object?>{'messageIndex': _messageIndex + 1},
    );

    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: '권한 주의문 개발자 상태',
      description: '주의문 3단계 전환 흐름의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'permission_notice',
    );

    if (!mounted) return;
    setState(() => _developerStatusOpen = false);
    AppStartDebugTrace.log(
      'permission_notice',
      'sequence_resumed_after_developer_status',
      meta: <String, Object?>{'messageIndex': _messageIndex + 1},
    );
    _startSequence(startIndex: _messageIndex);
  }

  Widget _buildMessage(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final animation = CurvedAnimation(
      parent: _controller,
      curve: _exiting ? Curves.easeInOutCubic : Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    return AppStartCinematicReveal(
      animation: animation,
      reduceMotion: _reduceMotion,
      exiting: _exiting,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Text(
            _messages[_messageIndex],
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.65,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sequenceGeneration++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final iconBrightness =
              tokens.isDark ? Brightness.light : Brightness.dark;

          return PopScope(
            canPop: false,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.canvas,
                statusBarIconBrightness: iconBrightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: tokens.canvas,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                body: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: _buildMessage(context)),
                      Align(
                        alignment: Alignment.topRight,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: DevAuth.devModeEnabled,
                          builder: (context, enabled, child) {
                            if (!enabled) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: IconButton.filledTonal(
                                tooltip: '개발자 상태',
                                onPressed: _developerStatusOpen
                                    ? null
                                    : _showDeveloperStatus,
                                icon: const Icon(Icons.terminal_rounded),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
