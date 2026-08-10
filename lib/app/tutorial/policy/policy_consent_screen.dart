import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../di/routes.dart';
import '../../init/app_start_debug_trace.dart';
import '../../init/app_start_flow_prefs.dart';
import '../../../features/selector/application/dev_auth.dart';
import 'policy_documents.dart';

export 'policy_documents.dart';

class PolicyConsentScreen extends StatefulWidget {
  const PolicyConsentScreen({
    super.key,
    required this.kind,
  });

  final PolicyConsentKind kind;

  @override
  State<PolicyConsentScreen> createState() => _PolicyConsentScreenState();
}

class _PolicyConsentScreenState extends State<PolicyConsentScreen> {
  final ScrollController _documentScrollController = ScrollController();
  bool _readToEnd = false;
  bool _agreed = false;
  bool _busy = false;
  double _scrollProgress = 0;

  PolicyDocumentSpec get _spec => policyDocumentOf(widget.kind);

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    DevAuth.isDevModeEnabled();
    AppStartDebugTrace.log(
      'policy_consent',
      'screen_init',
      meta: <String, Object?>{'kind': _kindValue(widget.kind)},
    );
    _documentScrollController.addListener(_handleDocumentScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNeeded());
  }

  String _kindValue(PolicyConsentKind kind) {
    return switch (kind) {
      PolicyConsentKind.termsOfService => 'terms_of_service',
      PolicyConsentKind.privacyPolicy => 'privacy_policy',
      PolicyConsentKind.accountDeletion => 'account_deletion',
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNeeded());
  }

  void _handleDocumentScroll() {
    if (!_documentScrollController.hasClients) return;
    final position = _documentScrollController.position;
    final progress = position.maxScrollExtent <= 0
        ? 1.0
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0).toDouble();
    final readToEnd = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24;
    if (readToEnd && !_readToEnd) {
      AppStartDebugTrace.log(
        'policy_consent',
        'document_read_to_end',
        meta: <String, Object?>{'kind': _kindValue(widget.kind)},
      );
    }
    if ((progress - _scrollProgress).abs() < 0.01 &&
        readToEnd == _readToEnd) {
      return;
    }
    setState(() {
      _scrollProgress = progress;
      if (readToEnd) _readToEnd = true;
    });
  }

  void _markReadIfNeeded() {
    if (!mounted || !_documentScrollController.hasClients) return;
    final position = _documentScrollController.position;
    final readToEnd = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24;
    if (!readToEnd && _scrollProgress > 0) return;
    setState(() {
      _scrollProgress = readToEnd ? 1 : _scrollProgress;
      if (readToEnd) _readToEnd = true;
    });
  }

  Future<void> _saveAgreement() async {
    switch (widget.kind) {
      case PolicyConsentKind.termsOfService:
        await AppStartFlowPrefs.setTermsOfServiceAgreed(true);
        return;
      case PolicyConsentKind.privacyPolicy:
        await AppStartFlowPrefs.setPrivacyPolicyAgreed(true);
        return;
      case PolicyConsentKind.accountDeletion:
        await AppStartFlowPrefs.setAccountDeletionPolicyAgreed(true);
        return;
    }
  }

  String _nextRoute() {
    switch (widget.kind) {
      case PolicyConsentKind.termsOfService:
        return AppRoutes.privacyPolicyConsent;
      case PolicyConsentKind.privacyPolicy:
        return AppRoutes.accountDeletionPolicyConsent;
      case PolicyConsentKind.accountDeletion:
        return AppRoutes.startGate;
    }
  }

  Future<void> _complete() async {
    if (_busy || !_agreed) return;
    setState(() => _busy = true);
    final nextRoute = _nextRoute();
    AppStartDebugTrace.log(
      'policy_consent',
      'agreement_save_start',
      meta: <String, Object?>{
        'kind': _kindValue(widget.kind),
        'nextRoute': nextRoute,
      },
    );
    try {
      await _saveAgreement();
      AppStartDebugTrace.log(
        'policy_consent',
        'agreement_save_success',
        meta: <String, Object?>{
          'kind': _kindValue(widget.kind),
          'nextRoute': nextRoute,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        nextRoute,
        (route) => false,
      );
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'policy_consent',
        'agreement_save_failure',
        meta: <String, Object?>{
          'kind': _kindValue(widget.kind),
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDeveloperStatus() async {
    AppStartDebugTrace.log(
      'policy_consent',
      'developer_status_request',
      meta: <String, Object?>{
        'kind': _kindValue(widget.kind),
        'readToEnd': _readToEnd,
        'agreed': _agreed,
        'busy': _busy,
      },
    );
    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: '정책 동의 개발자 상태',
      description: '정책 및 후속 설정 흐름의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'policy_consent',
    );
  }

  Widget _buildFlowProgress(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final progress = _spec.step / _spec.totalSteps;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CommonUiShapes.pill),
            child: TweenAnimationBuilder<double>(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.layout,
              curve: CommonUiMotion.standard,
              tween: Tween<double>(begin: 0, end: progress),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: tokens.surfaceOverlay,
                  color: tokens.accent,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(CommonUiShapes.pill),
            border: Border.all(
              color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
            ),
          ),
          child: Text(
            '${_spec.step}/${_spec.totalSteps}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tokens.onAccentContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PolicyEntrance(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color:
                      tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
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
                _spec.icon,
                color: tokens.onAccentContainer,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _spec.title,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _spec.subtitle,
            style: textTheme.bodyLarge?.copyWith(
              color: tokens.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocument(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PolicyEntrance(
      delay: const Duration(milliseconds: 70),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              color: tokens.surface,
              child: Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    color: tokens.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '문서 확인',
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration:
                        _reduceMotion ? Duration.zero : CommonUiMotion.component,
                    child: _readToEnd
                        ? _PolicyReadPill(
                            key: const ValueKey('read'),
                            label: '확인 완료',
                            icon: Icons.check_circle_rounded,
                            background: tokens.successContainer,
                            foreground: tokens.onSuccessContainer,
                            border: tokens.success,
                          )
                        : _PolicyReadPill(
                            key: const ValueKey('reading'),
                            label: '${(_scrollProgress * 100).round()}%',
                            icon: Icons.swipe_vertical_rounded,
                            background: tokens.surfaceOverlay,
                            foreground: tokens.textSecondary,
                            border: tokens.borderSubtle,
                          ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 4,
              child: TweenAnimationBuilder<double>(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                tween: Tween<double>(begin: 0, end: _scrollProgress),
                builder: (context, value, child) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: tokens.surfaceOverlay,
                    color: _readToEnd ? tokens.success : tokens.accent,
                  );
                },
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _documentScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _documentScrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 30, 24),
                  child: Text(
                    _spec.body.trim(),
                    style: textTheme.bodyMedium?.copyWith(
                      height: 1.62,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgreement(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final enabled = _readToEnd && !_busy;

    return _PolicyEntrance(
      delay: const Duration(milliseconds: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
            child: _readToEnd
                ? const SizedBox.shrink(key: ValueKey('ready'))
                : Padding(
                    key: const ValueKey('guide'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_double_arrow_down_rounded,
                          color: tokens.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '문서를 끝까지 스크롤하면 동의할 수 있습니다.',
                            style: textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          AnimatedContainer(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            decoration: BoxDecoration(
              color: _agreed ? tokens.surfaceSelected : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.card),
              border: Border.all(
                color: _agreed ? tokens.accent : tokens.borderSubtle,
              ),
            ),
            child: CheckboxListTile(
              value: _agreed,
              onChanged: enabled
                  ? (value) {
                      final agreed = value ?? false;
                      setState(() => _agreed = agreed);
                      AppStartDebugTrace.log(
                        'policy_consent',
                        'agreement_toggle',
                        meta: <String, Object?>{
                          'kind': _kindValue(widget.kind),
                          'agreed': agreed,
                        },
                      );
                    }
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              title: Text(
                _spec.agreeLabel,
                style: textTheme.titleSmall?.copyWith(
                  color:
                      enabled ? tokens.textPrimary : tokens.textDisabled,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CommonButton(
            label: _busy ? '저장 중' : _spec.actionLabel,
            icon: widget.kind == PolicyConsentKind.accountDeletion
                ? Icons.check_rounded
                : Icons.arrow_forward_rounded,
            onPressed: _agreed && !_busy ? _complete : null,
            loading: _busy,
            expand: true,
            haptic: CommonHaptic.selection,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _documentScrollController.removeListener(_handleDocumentScroll);
    _documentScrollController.dispose();
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
                  title: Text(_spec.title),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: DevAuth.devModeEnabled,
                      builder: (context, enabled, child) {
                        if (!enabled) return const SizedBox.shrink();
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
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildFlowProgress(context),
                            const SizedBox(height: 18),
                            _buildHeader(context),
                            const SizedBox(height: 18),
                            Expanded(child: _buildDocument(context)),
                            const SizedBox(height: 12),
                            _buildAgreement(context),
                          ],
                        ),
                      ),
                    ),
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

class _PolicyReadPill extends StatelessWidget {
  const _PolicyReadPill({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: border.withOpacity(0.58)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyEntrance extends StatelessWidget {
  const _PolicyEntrance({
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
      curve: CommonUiMotion.enter,
      builder: (context, value, child) {
        final adjusted = delay == Duration.zero
            ? value
            : ((value * duration.inMilliseconds - delay.inMilliseconds) /
                    CommonUiMotion.layout.inMilliseconds)
                .clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: adjusted,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - adjusted)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
