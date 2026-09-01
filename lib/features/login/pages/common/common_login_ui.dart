import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

@immutable
class CommonLoginModeSpec {
  const CommonLoginModeSpec({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;

  static const CommonLoginModeSpec personal = CommonLoginModeSpec(
    title: '개인형 로그인',
    subtitle: '모바일에서 직접 출차 요청을 진행하는 계정입니다.',
    badge: '개인형',
    icon: Icons.phone_iphone_rounded,
  );

  static const CommonLoginModeSpec tablet = CommonLoginModeSpec(
    title: '태블릿형 로그인',
    subtitle: '태블릿 전용 계정으로 현장 업무 화면에 연결합니다.',
    badge: '태블릿형',
    icon: Icons.tablet_mac_rounded,
  );

  static const CommonLoginModeSpec single = CommonLoginModeSpec(
    title: '출퇴근 기록형 로그인',
    subtitle: '출근, 퇴근과 휴게시간 기록 기능에 연결합니다.',
    badge: '출퇴근 기록형',
    icon: Icons.access_time_filled_rounded,
  );

  static const CommonLoginModeSpec doubleMode = CommonLoginModeSpec(
    title: '경량형 로그인',
    subtitle: '입차 완료와 출차 완료 중심의 경량 업무에 연결합니다.',
    badge: '경량형',
    icon: Icons.bolt_rounded,
  );

  static const CommonLoginModeSpec triple = CommonLoginModeSpec(
    title: '기본형 로그인',
    subtitle: '입차 완료, 출차 요청과 출차 완료 업무에 연결합니다.',
    badge: '기본형',
    icon: Icons.apps_rounded,
  );

  static const CommonLoginModeSpec minor = CommonLoginModeSpec(
    title: '확장형 로그인',
    subtitle: '입차 요청부터 출차 완료까지 전체 업무에 연결합니다.',
    badge: '확장형',
    icon: Icons.tune_rounded,
  );
}


class CommonLoginImageMetrics {
  const CommonLoginImageMetrics._();

  static const Size topLogo = Size(180, 138);
  static const Size footerLogo = Size(160, 52);
  static const EdgeInsets topTouchPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
  static const EdgeInsets footerTouchPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );
}

class CommonLoginScaffold extends StatelessWidget {
  const CommonLoginScaffold({
    super.key,
    required this.spec,
    required this.fields,
    required this.actions,
    required this.onTopLogoPressed,
    required this.onFooterLogoPressed,
    this.status,
    this.topTrailing,
  });

  final CommonLoginModeSpec spec;
  final Widget fields;
  final Widget actions;
  final VoidCallback onTopLogoPressed;
  final VoidCallback onFooterLogoPressed;
  final Widget? status;
  final Widget? topTrailing;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final compact = media.size.height < 720;
    final horizontalPadding = media.size.width < 420 ? 14.0 : 24.0;
    final reduceMotion = media.disableAnimations;

    return Material(
      color: tokens.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 14 : 24,
                horizontalPadding,
                media.viewInsets.bottom + 20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      CommonAnimatedReveal(
                        duration: CommonUiMotion.layout,
                        child: _CommonLoginBrandHeader(
                          onPressed: onTopLogoPressed,
                        ),
                      ),
                      SizedBox(height: compact ? 14 : 20),
                      CommonAnimatedReveal(
                        delay: const Duration(milliseconds: 70),
                        duration: CommonUiMotion.layout,
                        child: _CommonLoginCard(
                          spec: spec,
                          status: status,
                          topTrailing: topTrailing,
                          fields: fields,
                          actions: actions,
                        ),
                      ),
                      AnimatedSize(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.component,
                        curve: CommonUiMotion.standard,
                        child: keyboardOpen
                            ? const SizedBox(height: 8)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: CommonAnimatedReveal(
                                  delay: const Duration(milliseconds: 150),
                                  child: _CommonLoginFooterLogo(
                                    onPressed: onFooterLogoPressed,
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
      ),
    );
  }
}

class _CommonLoginBrandHeader extends StatelessWidget {
  const _CommonLoginBrandHeader({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _CommonLoginImageButton(
      semanticsLabel: 'ParkinWorkin 로고',
      assetPath: 'assets/images/ParkinWorkin_logo.png',
      frameSize: CommonLoginImageMetrics.topLogo,
      touchPadding: CommonLoginImageMetrics.topTouchPadding,
      onPressed: onPressed,
    );
  }
}

class _CommonLoginCard extends StatelessWidget {
  const _CommonLoginCard({
    required this.spec,
    required this.fields,
    required this.actions,
    required this.status,
    required this.topTrailing,
  });

  final CommonLoginModeSpec spec;
  final Widget fields;
  final Widget actions;
  final Widget? status;
  final Widget? topTrailing;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.standard,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.control),
                          border: Border.all(
                            color: tokens.accent.withOpacity(
                              tokens.isDark ? 0.62 : 0.42,
                            ),
                          ),
                        ),
                        child: Icon(
                          spec.icon,
                          size: 24,
                          color: tokens.onAccentContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _CommonLoginBadge(label: spec.badge),
                            const SizedBox(height: 8),
                            Text(
                              spec.title,
                              style: textTheme.titleLarge?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              spec.subtitle,
                              style: textTheme.bodyMedium?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (topTrailing != null) ...<Widget>[
                        const SizedBox(width: 8),
                        topTrailing!,
                      ],
                    ],
                  ),
                  if (status != null) ...<Widget>[
                    const SizedBox(height: 18),
                    status!,
                  ],
                  const SizedBox(height: 20),
                  Divider(height: 1, color: tokens.borderSubtle),
                  const SizedBox(height: 20),
                  fields,
                  const SizedBox(height: 22),
                  actions,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommonLoginBadge extends StatelessWidget {
  const _CommonLoginBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: tokens.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommonLoginFooterLogo extends StatelessWidget {
  const _CommonLoginFooterLogo({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _CommonLoginImageButton(
      semanticsLabel: '모드 터미널로 돌아가기',
      assetPath: 'assets/images/ParkinWorkin_text.png',
      frameSize: CommonLoginImageMetrics.footerLogo,
      touchPadding: CommonLoginImageMetrics.footerTouchPadding,
      onPressed: onPressed,
    );
  }
}

class _CommonLoginImageButton extends StatefulWidget {
  const _CommonLoginImageButton({
    required this.semanticsLabel,
    required this.assetPath,
    required this.frameSize,
    required this.touchPadding,
    required this.onPressed,
  });

  final String semanticsLabel;
  final String assetPath;
  final Size frameSize;
  final EdgeInsets touchPadding;
  final VoidCallback onPressed;

  @override
  State<_CommonLoginImageButton> createState() =>
      _CommonLoginImageButtonState();
}

class _CommonLoginImageButtonState extends State<_CommonLoginImageButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = _hovered || _focused;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.press;
    final borderColor = _focused ? tokens.focusRing : tokens.transparent;
    final backgroundColor = active ? tokens.surfaceOverlay : tokens.transparent;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: Center(
        child: AnimatedContainer(
          duration: duration,
          curve: CommonUiMotion.standard,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(CommonUiShapes.card),
            border: Border.all(
              color: borderColor,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(CommonUiShapes.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onPressed();
              },
              onHover: (value) {
                if (_hovered == value) return;
                setState(() => _hovered = value);
              },
              onFocusChange: (value) {
                if (_focused == value) return;
                setState(() => _focused = value);
              },
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              borderRadius: BorderRadius.circular(CommonUiShapes.card),
              child: Padding(
                padding: widget.touchPadding,
                child: SizedBox.fromSize(
                  size: widget.frameSize,
                  child: Center(
                    child: AnimatedScale(
                      duration: duration,
                      curve: CommonUiMotion.standard,
                      scale: _pressed ? 0.97 : 1,
                      child: _CommonTintedImage(
                        assetPath: widget.assetPath,
                        width: widget.frameSize.width,
                        height: widget.frameSize.height,
                        background: tokens.canvas,
                        preferred: tokens.accent,
                        fallback: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommonTintedImage extends StatelessWidget {
  const _CommonTintedImage({
    required this.assetPath,
    required this.width,
    required this.height,
    required this.background,
    required this.preferred,
    required this.fallback,
  });

  final String assetPath;
  final double width;
  final double height;
  final Color background;
  final Color preferred;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    final tint = _contrastRatio(preferred, background) >= 3
        ? preferred
        : fallback;
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

double _contrastRatio(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  final lighter = aLuminance >= bLuminance ? aLuminance : bLuminance;
  final darker = aLuminance >= bLuminance ? bLuminance : aLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

InputDecoration commonLoginInputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  Widget? suffixIcon,
}) {
  final tokens = CommonUiTheme.of(context);
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: tokens.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.focusRing, width: 2),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.danger, width: 2),
    ),
  );
}

class CommonLoginFields extends StatelessWidget {
  const CommonLoginFields({
    super.key,
    required this.nameController,
    required this.nameFocus,
    required this.accountController,
    required this.accountFocus,
    required this.passwordController,
    required this.passwordFocus,
    required this.accountLabel,
    required this.accountIcon,
    required this.accountKeyboardType,
    required this.onAccountChanged,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onSubmit,
    this.passwordLabel = '비밀번호(5자리 이상)',
    this.passwordKeyboardType,
    this.passwordInputFormatters,
    this.enabled = true,
    this.accountTextCapitalization = TextCapitalization.none,
    this.accountAutocorrect = false,
    this.accountEnableSuggestions = false,
  });

  final TextEditingController nameController;
  final FocusNode nameFocus;
  final TextEditingController accountController;
  final FocusNode accountFocus;
  final TextEditingController passwordController;
  final FocusNode passwordFocus;
  final String accountLabel;
  final IconData accountIcon;
  final TextInputType accountKeyboardType;
  final ValueChanged<String> onAccountChanged;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final String passwordLabel;
  final TextInputType? passwordKeyboardType;
  final List<TextInputFormatter>? passwordInputFormatters;
  final bool enabled;
  final TextCapitalization accountTextCapitalization;
  final bool accountAutocorrect;
  final bool accountEnableSuggestions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 90),
          child: TextField(
            controller: nameController,
            focusNode: nameFocus,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(accountFocus),
            decoration: commonLoginInputDecoration(
              context,
              label: '이름',
              icon: Icons.person_rounded,
            ),
          ),
        ),
        const SizedBox(height: 14),
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 140),
          child: TextField(
            controller: accountController,
            focusNode: accountFocus,
            enabled: enabled,
            keyboardType: accountKeyboardType,
            textCapitalization: accountTextCapitalization,
            autocorrect: accountAutocorrect,
            enableSuggestions: accountEnableSuggestions,
            textInputAction: TextInputAction.next,
            onChanged: onAccountChanged,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(passwordFocus),
            decoration: commonLoginInputDecoration(
              context,
              label: accountLabel,
              icon: accountIcon,
            ),
          ),
        ),
        const SizedBox(height: 14),
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 190),
          child: TextField(
            controller: passwordController,
            focusNode: passwordFocus,
            enabled: enabled,
            obscureText: obscurePassword,
            keyboardType: passwordKeyboardType,
            inputFormatters: passwordInputFormatters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: commonLoginInputDecoration(
              context,
              label: passwordLabel,
              icon: Icons.lock_rounded,
              suffixIcon: Padding(
                padding: const EdgeInsets.all(4),
                child: CommonIconButton(
                  icon: obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  tooltip: obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
                  onPressed: enabled ? onTogglePassword : null,
                  haptic: CommonHaptic.selection,
                  size: 40,
                  iconSize: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CommonLoginStatusBanner extends StatelessWidget {
  const CommonLoginStatusBanner({
    super.key,
    required this.visible,
    required this.message,
  });

  final bool visible;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(sizeFactor: animation, child: child),
        );
      },
      child: visible
          ? Container(
              key: const ValueKey<String>('login-status-visible'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.successContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(
                  color: tokens.success.withOpacity(tokens.isDark ? 0.62 : 0.38),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_rounded,
                    color: tokens.success,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.onSuccessContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(
              key: ValueKey<String>('login-status-hidden'),
            ),
    );
  }
}

void showCommonLoginSnack(
  BuildContext context, {
  required String message,
  required bool success,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final tokens = CommonUiTheme.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          success ? tokens.successContainer : tokens.dangerContainer,
      content: Row(
        children: <Widget>[
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: success ? tokens.success : tokens.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: success
                        ? tokens.onSuccessContainer
                        : tokens.onDangerContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        side: BorderSide(
          color: success
              ? tokens.success.withOpacity(0.42)
              : tokens.danger.withOpacity(0.42),
        ),
      ),
    ),
  );
}

Future<void> showCommonLoginFailure(
  BuildContext context, {
  String title = '로그인 실패',
  String? description,
  String? copyText,
  String copyButtonLabel = '실패 내용 복사',
}) async {
  if (!context.mounted) return;
  final tokens = CommonUiTheme.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final hasCopy = copyText != null && copyText.trim().isNotEmpty;
  final route = RawDialogRoute<void>(
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: tokens.scrim,
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, __) {
      return CommonUiScope(
        child: CommonDialogFrame(
          child: _CommonLoginFailureContent(
            title: title,
            description: description,
            copyText: copyText,
            copyButtonLabel: copyButtonLabel,
          ),
        ),
      );
    },
  );

  navigator.push<void>(route);
  await Future<void>.delayed(
    hasCopy ? const Duration(seconds: 45) : const Duration(milliseconds: 1800),
  );
  if (navigator.mounted && route.isActive) {
    navigator.removeRoute(route);
  }
}

class _CommonLoginFailureContent extends StatefulWidget {
  const _CommonLoginFailureContent({
    required this.title,
    required this.description,
    required this.copyText,
    required this.copyButtonLabel,
  });

  final String title;
  final String? description;
  final String? copyText;
  final String copyButtonLabel;

  @override
  State<_CommonLoginFailureContent> createState() =>
      _CommonLoginFailureContentState();
}

class _CommonLoginFailureContentState
    extends State<_CommonLoginFailureContent> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final description = widget.description?.trim() ?? '';
    final copyText = widget.copyText?.trim() ?? '';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tokens.dangerContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.danger.withOpacity(0.42),
                ),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: tokens.danger,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  description,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (copyText.isNotEmpty) ...<Widget>[
            CommonButton(
              label: _copied ? '복사 완료' : widget.copyButtonLabel,
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              variant: CommonButtonVariant.secondary,
              expand: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: copyText));
                if (!mounted) return;
                setState(() => _copied = true);
              },
              haptic: CommonHaptic.selection,
            ),
            const SizedBox(height: 10),
          ],
          CommonButton(
            label: '닫기',
            icon: Icons.close_rounded,
            variant: CommonButtonVariant.tertiary,
            expand: true,
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }
}
