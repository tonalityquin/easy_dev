import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../auth/google_auth_session.dart';
import '../../config/auth_config.dart';
import '../../config/gmail_sender_config.dart';
import '../../di/routes.dart';
import '../../init/app_start_debug_trace.dart';
import '../../init/app_start_flow_prefs.dart';
import '../../init/app_start_user_purpose.dart';

class AppStartGoogleServicesSetupScreen extends StatefulWidget {
  const AppStartGoogleServicesSetupScreen({super.key});

  @override
  State<AppStartGoogleServicesSetupScreen> createState() =>
      _AppStartGoogleServicesSetupScreenState();
}

class _AppStartGoogleServicesSetupScreenState
    extends State<AppStartGoogleServicesSetupScreen> {
  bool _busy = false;
  bool _connected = false;
  bool _entryReady = false;
  bool _skipping = false;
  int _skipTapCount = 0;
  String? _accountEmail;
  String? _errorText;
  AppStartUserPurpose? _purpose;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static const List<_GoogleServiceSpec> _services = <_GoogleServiceSpec>[
    _GoogleServiceSpec(
      title: 'Google Calendar',
      description: '업무 일정 조회, 등록, 수정 및 삭제에 사용합니다.',
      detail: 'Calendar · Calendar Events',
      icon: Icons.calendar_month_rounded,
    ),
    _GoogleServiceSpec(
      title: 'Gmail',
      description: '업무 시작·종료 보고와 첨부파일 메일 전송에 사용합니다.',
      detail: 'Gmail Send',
      icon: Icons.mail_rounded,
    ),
    _GoogleServiceSpec(
      title: 'Google Cloud Storage',
      description: '업무 파일과 이미지의 저장 및 조회에 사용합니다.',
      detail: 'Cloud Storage Full Control',
      icon: Icons.cloud_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    DevAuth.isDevModeEnabled();
    AppStartDebugTrace.log('google_services_setup', 'screen_init');
    _initialize();
  }

  Future<void> _initialize() async {
    final purpose = await AppStartFlowPrefs.getUserPurpose();
    final policiesDone = await AppStartFlowPrefs.getAllPolicyConsentsDone();
    final setupDone = await AppStartFlowPrefs.getGoogleServicesSetupDone();
    final setupSkipped =
        await AppStartFlowPrefs.getGoogleServicesSetupSkipped();
    if (!mounted) return;

    if (purpose == null ||
        purpose.skipsPolicyAndPostSetup ||
        !policiesDone ||
        setupSkipped) {
      AppStartDebugTrace.log(
        'google_services_setup',
        'entry_rejected',
        meta: <String, Object?>{
          'purpose': purpose?.storageValue ?? 'none',
          'skipPolicyAndPostSetup':
              purpose?.skipsPolicyAndPostSetup ?? false,
          'policiesDone': policiesDone,
          'setupSkipped': setupSkipped,
        },
      );
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.startGate,
        (route) => false,
      );
      return;
    }

    final identity = GoogleAuthSession.instance.currentIdentity;
    setState(() {
      _purpose = purpose;
      _connected = setupDone;
      _accountEmail = setupDone ? identity?.email : null;
      _entryReady = true;
    });
    AppStartDebugTrace.log(
      'google_services_setup',
      'profile_ready',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'setupDone': setupDone,
        'setupSkipped': setupSkipped,
        'configuredScopes': AppScopes.values.join(','),
      },
    );
  }

  Future<void> _connectGoogleServices() async {
    if (_busy || _connected || _skipping || !_entryReady) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    AppStartDebugTrace.log(
      'google_services_setup',
      'oauth_start',
      meta: <String, Object?>{
        'purpose': _purpose?.storageValue ?? 'none',
        'scopeCount': AppScopes.values.length,
        'scopes': AppScopes.values.join(','),
      },
    );

    try {
      await GoogleAuthSession.instance.init(
        serverClientId: AuthConfig.webClientId,
      );
      final identity = await GoogleAuthSession.instance.authenticateAccount(
        bridgeFirebase: false,
      );
      final gmailSenderInitialized =
          await GmailSenderConfig.initializeFromEmailIfUnset(identity.email);
      if (_skipping || !mounted) return;
      await AppStartFlowPrefs.setGoogleServicesSetupDone(true);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _accountEmail = identity.email;
        _errorText = null;
      });
      AppStartDebugTrace.log(
        'google_services_setup',
        'oauth_success',
        meta: <String, Object?>{
          'email': identity.email,
          'gmailSenderInitialized': gmailSenderInitialized,
          'scopeCount': AppScopes.values.length,
        },
      );
    } catch (error, stackTrace) {
      if (_skipping || !mounted) return;
      setState(() => _errorText = 'Google 서비스 권한 허용을 완료하지 못했습니다. 다시 시도해 주세요.');
      AppStartDebugTrace.log(
        'google_services_setup',
        'oauth_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (_busy || _skipping || !_connected) return;
    AppStartDebugTrace.log(
      'google_services_setup',
      'complete',
      meta: <String, Object?>{
        'purpose': _purpose?.storageValue ?? 'none',
        'email': _accountEmail ?? 'unknown',
      },
    );
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.startGate,
      (route) => false,
    );
  }

  Future<void> _handlePostSetupTitleTap() async {
    if (!_entryReady || _connected || _skipping || _busy) return;
    final nextCount = (_skipTapCount + 1).clamp(0, 5).toInt();
    setState(() => _skipTapCount = nextCount);
    AppStartDebugTrace.log(
      'google_services_setup',
      'skip_tap',
      meta: <String, Object?>{
        'count': nextCount,
        'required': 5,
        'busy': _busy,
      },
    );
    if (nextCount < 5) {
      await HapticFeedback.selectionClick();
      return;
    }

    setState(() {
      _skipping = true;
      _errorText = null;
    });
    await HapticFeedback.mediumImpact();
    await AppStartFlowPrefs.setGoogleServicesSetupSkipped(true);
    AppStartDebugTrace.log(
      'google_services_setup',
      'setup_skipped',
      meta: <String, Object?>{
        'source': 'appbar_five_taps',
        'purpose': _purpose?.storageValue ?? 'none',
        'oauthCompleted': false,
      },
    );
    if (!mounted) return;
    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: 'Google 서비스 연결 스킵 상태',
      description: '후속 설정 5회 터치 스킵 흐름의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'google_services_setup',
    );
    if (!mounted) return;
    await Future<void>.delayed(
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 520),
    );
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.startGate,
      (route) => false,
    );
  }

  Future<void> _showDeveloperStatus() async {
    AppStartDebugTrace.log(
      'google_services_setup',
      'developer_status_request',
      meta: <String, Object?>{
        'busy': _busy,
        'connected': _connected,
        'skipping': _skipping,
        'skipTapCount': _skipTapCount,
        'purpose': _purpose?.storageValue ?? 'loading',
      },
    );
    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: 'Google 서비스 연결 개발자 상태',
      description: 'Google OAuth 사전 허용 흐름의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'google_services_setup',
    );
  }

  Widget _buildHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return _GoogleSetupEntrance(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.security_rounded,
              size: 42,
              color: tokens.onAccentContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Google 서비스 연결',
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              '업무에 필요한 Google 서비스를 초기 설정에서 미리 허용합니다. 한 번의 승인 과정에서 아래 서비스 권한을 함께 요청합니다.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(
    BuildContext context,
    _GoogleServiceSpec spec,
    int index,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return _GoogleSetupEntrance(
      delay: Duration(milliseconds: 60 + index * 45),
      child: AnimatedContainer(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _connected ? tokens.surfaceSelected : tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(
            color: _connected ? tokens.success : tokens.borderSubtle,
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration:
                  _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _connected
                    ? tokens.successContainer
                    : tokens.accentContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                spec.icon,
                color: _connected
                    ? tokens.onSuccessContainer
                    : tokens.onAccentContainer,
                size: 25,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.title,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    spec.description,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    spec.detail,
                    style: textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration:
                  _reduceMotion ? Duration.zero : CommonUiMotion.component,
              switchInCurve: Curves.linear,
              switchOutCurve: Curves.linear,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
                    child: child,
                  ),
                );
              },
              child: _connected
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey('connected'),
                      color: tokens.success,
                    )
                  : Icon(
                      Icons.radio_button_unchecked_rounded,
                      key: const ValueKey('pending'),
                      color: tokens.textSecondary,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionState(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.layout,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _connected
          ? Container(
              key: const ValueKey('connected_state'),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.successContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.card),
                border: Border.all(color: tokens.success),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, color: tokens.onSuccessContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google 서비스 허용 완료',
                          style: textTheme.titleSmall?.copyWith(
                            color: tokens.onSuccessContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_accountEmail != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _accountEmail!,
                            style: textTheme.bodySmall?.copyWith(
                              color: tokens.onSuccessContainer,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Container(
              key: const ValueKey('pending_state'),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Text(
                'Google 계정 선택과 OAuth 동의 화면에서 Calendar, Gmail, Google Cloud Storage 권한을 허용해 주세요.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
    );
  }

  Widget _buildError(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AnimatedSize(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.layout,
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
        child: _errorText == null
            ? const SizedBox.shrink(key: ValueKey('no_error'))
            : Container(
                key: const ValueKey('error'),
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.dangerContainer,
                  borderRadius: BorderRadius.circular(CommonUiShapes.card),
                  border: Border.all(color: tokens.danger),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_rounded, color: tokens.onDangerContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorText!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: tokens.onDangerContainer,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
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
                statusBarColor: tokens.surface,
                statusBarIconBrightness: iconBrightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: tokens.borderSubtle,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                appBar: AppBar(
                  title: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handlePostSetupTitleTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey<int>(_skipTapCount),
                        tween: Tween<double>(begin: 0.965, end: 1),
                        duration: _reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: child,
                          );
                        },
                        child: const Text('후속 설정'),
                      ),
                    ),
                  ),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: DevAuth.devModeEnabled,
                      builder: (context, enabled, child) {
                        if (!enabled || !_entryReady) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          tooltip: '개발자 상태',
                          onPressed: _showDeveloperStatus,
                          icon: const Icon(Icons.terminal_rounded),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                body: Stack(
                  children: [
                    SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: AnimatedOpacity(
                            opacity: _skipping ? 0.34 : 1,
                            duration: _reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: IgnorePointer(
                              ignoring: _skipping,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        22,
                                        16,
                                        20,
                                      ),
                                      child: Column(
                                        children: [
                                          _buildHeader(context),
                                          const SizedBox(height: 26),
                                          for (var i = 0;
                                              i < _services.length;
                                              i++) ...[
                                            _buildServiceCard(
                                              context,
                                              _services[i],
                                              i,
                                            ),
                                            if (i < _services.length - 1)
                                              const SizedBox(height: 12),
                                          ],
                                          const SizedBox(height: 16),
                                          _GoogleSetupEntrance(
                                            delay: const Duration(
                                              milliseconds: 210,
                                            ),
                                            child: _buildConnectionState(
                                              context,
                                            ),
                                          ),
                                          _buildError(context),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.surface,
                                      border: Border(
                                        top: BorderSide(
                                          color: tokens.borderSubtle,
                                        ),
                                      ),
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: _reduceMotion
                                          ? Duration.zero
                                          : CommonUiMotion.component,
                                      child: _connected
                                          ? CommonButton(
                                              key: const ValueKey('complete'),
                                              label: '설정 완료',
                                              icon:
                                                  Icons.arrow_forward_rounded,
                                              onPressed: _busy || _skipping
                                                  ? null
                                                  : _complete,
                                              expand: true,
                                              haptic: CommonHaptic.selection,
                                            )
                                          : CommonButton(
                                              key: const ValueKey('connect'),
                                              label: _busy
                                                  ? 'Google 권한 확인 중'
                                                  : 'Google 계정 연결 및 권한 허용',
                                              icon: Icons.login_rounded,
                                              onPressed: _busy ||
                                                      _skipping ||
                                                      !_entryReady
                                                  ? null
                                                  : _connectGoogleServices,
                                              loading: _busy,
                                              expand: true,
                                              haptic: CommonHaptic.selection,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedSwitcher(
                          duration: _reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final scale = Tween<double>(
                              begin: 0.96,
                              end: 1,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: scale,
                                child: child,
                              ),
                            );
                          },
                          child: _skipping
                              ? Container(
                                  key: const ValueKey('skip_transition'),
                                  color: tokens.canvas.withOpacity(0.9),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(24),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 420,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(22),
                                      decoration: BoxDecoration(
                                        color: tokens.surfaceRaised,
                                        borderRadius: BorderRadius.circular(
                                          CommonUiShapes.card,
                                        ),
                                        border: Border.all(
                                          color: tokens.accent,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: tokens.shadow,
                                            blurRadius: 20,
                                            offset: const Offset(0, 9),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.skip_next_rounded,
                                            size: 38,
                                            color: tokens.accent,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Google 서비스 연결을 건너뜁니다.',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: tokens.textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('skip_transition_hidden'),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GoogleServiceSpec {
  const _GoogleServiceSpec({
    required this.title,
    required this.description,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String description;
  final String detail;
  final IconData icon;
}

class _GoogleSetupEntrance extends StatelessWidget {
  const _GoogleSetupEntrance({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    final duration = CommonUiMotion.layout + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final adjusted = delay == Duration.zero
            ? value
            : ((value * duration.inMilliseconds - delay.inMilliseconds) /
                    CommonUiMotion.layout.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        return Opacity(
          opacity: adjusted,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - adjusted)),
            child: Transform.scale(
              scale: 0.985 + 0.015 * adjusted,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
