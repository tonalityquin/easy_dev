import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../dev/debug/debug_action_recorder.dart';

Future<void> _invokeCardAction(PromptAction? action) async {
  if (action == null) return;
  final result = action();
  if (result is Future) {
    await result;
  }
}

Text _selectorCardTitle(BuildContext context, String text, {bool enabled = true}) {
  final tokens = PromptUiTheme.of(context);
  return Text(
    text,
    textAlign: TextAlign.center,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: enabled ? tokens.textPrimary : tokens.textDisabled,
          fontWeight: FontWeight.w700,
        ),
  );
}

Widget _selectorCardFeatureText(
  BuildContext context,
  String text, {
  TextAlign textAlign = TextAlign.center,
  int maxLines = 2,
  bool enabled = true,
}) {
  final tokens = PromptUiTheme.of(context);
  return Text(
    text,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: enabled ? tokens.textSecondary : tokens.textDisabled,
          fontWeight: FontWeight.w500,
        ),
  );
}

List<BoxShadow> _cardShadows(
  PromptUiTokens tokens, {
  required bool focused,
  required bool hovered,
}) {
  return <BoxShadow>[
    if (focused)
      BoxShadow(
        color: tokens.focusRing,
        blurRadius: 0,
        spreadRadius: 2,
      )
    else if (hovered)
      BoxShadow(
        color: tokens.shadow,
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
  ];
}

class CardBody extends StatefulWidget {
  const CardBody({
    super.key,
    required this.icon,
    required this.title,
    required this.onPressed,
    required this.traceName,
    this.enabled = true,
    this.disabledTooltip,
    this.featureText,
    this.traceMeta,
  });

  final IconData icon;
  final String title;
  final String? featureText;
  final PromptAction? onPressed;
  final bool enabled;
  final String? disabledTooltip;
  final String traceName;
  final Map<String, dynamic>? traceMeta;

  @override
  State<CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<CardBody> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;

  bool get _enabled => widget.enabled && widget.onPressed != null && !_invoking;

  Future<void> _activate(String source) async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      await HapticFeedback.selectionClick();
      if (!mounted) return;

      DebugActionRecorder.instance.recordAction(
        widget.traceName,
        route: ModalRoute.of(context)?.settings.name,
        meta: <String, dynamic>{
          'source': source,
          if (widget.featureText != null && widget.featureText!.trim().isNotEmpty)
            'featureText': widget.featureText,
          if (widget.traceMeta != null) ...widget.traceMeta!,
        },
      );

      await _invokeCardAction(widget.onPressed);
    } finally {
      if (mounted) {
        setState(() {
          _invoking = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final hasFeature =
        widget.featureText != null && widget.featureText!.trim().isNotEmpty;
    final surface = !_enabled
        ? tokens.surfaceDisabled
        : _hovered || _pressed
            ? tokens.surfaceOverlay
            : tokens.surfaceRaised;
    final border = _hovered && _enabled
        ? tokens.borderStrong
        : tokens.borderSubtle;
    final iconBackground =
        _enabled ? tokens.accentContainer : tokens.surfaceOverlay;
    final iconForeground =
        _enabled ? tokens.onAccentContainer : tokens.iconDisabled;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.title,
      value: _invoking ? '처리 중' : null,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: border, width: 1),
          boxShadow: _cardShadows(
            tokens,
            focused: _focused,
            hovered: _hovered && _enabled,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _enabled ? () => _activate('card') : null,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            mouseCursor:
                _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            child: AnimatedScale(
              scale: _pressed && _enabled ? 0.985 : 1,
              duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
              curve: PromptUiMotion.enter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration:
                          reduceMotion ? Duration.zero : PromptUiMotion.selection,
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _enabled
                              ? tokens.accent.withOpacity(
                                  tokens.isDark ? 0.48 : 0.30,
                                )
                              : tokens.borderSubtle,
                        ),
                      ),
                      child: _invoking
                          ? Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: iconForeground,
                                ),
                              ),
                            )
                          : Icon(
                              widget.icon,
                              color: iconForeground,
                              size: 28,
                            ),
                    ),
                    const SizedBox(height: 12),
                    _selectorCardTitle(
                      context,
                      widget.title,
                      enabled: _enabled,
                    ),
                    if (hasFeature) ...[
                      const SizedBox(height: 6),
                      _selectorCardFeatureText(
                        context,
                        widget.featureText!.trim(),
                        enabled: _enabled,
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const SizedBox(height: 12),
                    PromptIconButton(
                      icon: Icons.arrow_forward_rounded,
                      tooltip: _enabled
                          ? '이동'
                          : widget.disabledTooltip ?? '선택할 수 없음',
                      onPressed: _enabled ? () => _activate('arrow') : null,
                      haptic: PromptHaptic.none,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StaticCardBody extends StatelessWidget {
  const StaticCardBody({
    super.key,
    required this.icon,
    required this.title,
    this.featureText,
  });

  final IconData icon;
  final String title;
  final String? featureText;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final hasFeature =
        featureText != null && featureText!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.accent.withOpacity(
                    tokens.isDark ? 0.48 : 0.30,
                  ),
                ),
              ),
              child: Icon(
                icon,
                color: tokens.onAccentContainer,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            _selectorCardTitle(context, title),
            if (hasFeature) ...[
              const SizedBox(height: 6),
              _selectorCardFeatureText(context, featureText!.trim()),
              const SizedBox(height: 10),
            ] else
              const SizedBox(height: 12),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: tokens.onAccentContainer,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _selectorCardShell({
  required BuildContext context,
  required Widget child,
}) {
  return PromptAnimatedReveal(child: child);
}

class ExperienceCard extends StatefulWidget {
  const ExperienceCard({super.key});

  @override
  State<ExperienceCard> createState() => _ExperienceCardState();
}

class _ExperienceCardState extends State<ExperienceCard> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;

  Future<void> _openDescription(String source) async {
    if (_invoking) return;
    setState(() => _invoking = true);
    try {
      await HapticFeedback.selectionClick();
      if (!mounted) return;

      DebugActionRecorder.instance.recordAction(
        '앱에 대해 알아보기',
        route: ModalRoute.of(context)?.settings.name,
        meta: <String, dynamic>{
          'source': source,
          'to': AppRoutes.descriptionIntro,
        },
      );

      await Navigator.of(context).pushNamed(AppRoutes.descriptionIntro);
    } finally {
      if (mounted) {
        setState(() {
          _invoking = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final surface = _pressed || _hovered
        ? tokens.surfaceOverlay
        : tokens.surfaceRaised;
    final border = _hovered ? tokens.borderStrong : tokens.borderSubtle;

    return _selectorCardShell(
      context: context,
      child: Semantics(
        button: true,
        enabled: !_invoking,
        label: '앱에 대해 알아보기',
        value: _invoking ? '처리 중' : null,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            border: Border.all(color: border, width: 1),
            boxShadow: _cardShadows(
              tokens,
              focused: _focused,
              hovered: _hovered,
            ),
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _invoking ? null : () => _openDescription('card'),
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              onHover: (value) {
                if (_hovered == value) return;
                setState(() => _hovered = value);
              },
              onFocusChange: (value) {
                if (_focused == value) return;
                setState(() => _focused = value);
              },
              mouseCursor: _invoking
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: AnimatedScale(
                scale: _pressed && !_invoking ? 0.99 : 1,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: tokens.accentContainer,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: tokens.accent.withOpacity(
                                    tokens.isDark ? 0.48 : 0.30,
                                  ),
                                ),
                              ),
                              child: _invoking
                                  ? Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: tokens.onAccentContainer,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.explore_rounded,
                                      color: tokens.onAccentContainer,
                                      size: 28,
                                    ),
                            ),
                            const SizedBox(height: 12),
                            _selectorCardTitle(
                              context,
                              '앱에 대해 알아보기',
                            ),
                            const SizedBox(height: 6),
                            _selectorCardFeatureText(
                              context,
                              '대표 흐름과 화면 구성을 먼저 둘러보세요',
                            ),
                            const SizedBox(height: 10),
                            PromptIconButton(
                              icon: Icons.arrow_forward_rounded,
                              tooltip: '앱에 대해 알아보기 열기',
                              onPressed: _invoking
                                  ? null
                                  : () => _openDescription('arrow'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, color: tokens.borderSubtle),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '체험 안내',
                              style: text.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _selectorCardFeatureText(
                              context,
                              '해당 앱에서 제공하는 업무 프로세스와 편의 기능 등에 대해',
                              textAlign: TextAlign.start,
                              maxLines: 3,
                            ),
                            const SizedBox(height: 10),
                            _selectorCardFeatureText(
                              context,
                              '약식으로 화면과 함께 안내받아볼 수 있습니다.',
                              textAlign: TextAlign.start,
                              maxLines: 4,
                            ),
                          ],
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
    );
  }
}

class SingleLoginCard extends StatelessWidget {
  const SingleLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.access_time_filled_rounded,
        title: '출퇴근 기록형',
        featureText: '출/퇴근 · 휴게시간',
        traceName: '출퇴근 기록형',
        traceMeta: <String, dynamic>{
          'to': AppRoutes.singleLogin,
          'redirectAfterLogin': AppRoutes.singleCommute,
          'requiredMode': 'single',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.singleLogin,
          arguments: <String, dynamic>{
            'redirectAfterLogin': AppRoutes.singleCommute,
            'requiredMode': 'single',
          },
        ),
        enabled: enabled,
        disabledTooltip: '저장된 모드가 single일 때만 선택할 수 있어요',
      ),
    );
  }
}

class DoubleLoginCard extends StatelessWidget {
  const DoubleLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.bolt_rounded,
        title: '경량형',
        featureText: '입차 완료 · 출차 완료',
        traceName: '경량형',
        traceMeta: <String, dynamic>{
          'to': AppRoutes.doubleLogin,
          'requiredMode': 'double',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.doubleLogin,
          arguments: <String, dynamic>{'requiredMode': 'double'},
        ),
        enabled: enabled,
        disabledTooltip: '저장된 모드가 double일 때만 선택할 수 있어요',
      ),
    );
  }
}

class MinorLoginCard extends StatelessWidget {
  const MinorLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.tune_rounded,
        title: '확장형',
        featureText: '입차 요청 · 입차 완료 · 출차 요청 · 출차 완료',
        traceName: '확장형',
        traceMeta: <String, dynamic>{
          'to': AppRoutes.minorLogin,
          'redirectAfterLogin': AppRoutes.minorCommute,
          'requiredMode': 'minor',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.minorLogin,
          arguments: <String, dynamic>{
            'redirectAfterLogin': AppRoutes.minorCommute,
            'requiredMode': 'minor',
          },
        ),
        enabled: enabled,
        disabledTooltip: '저장된 모드가 minor일 때만 선택할 수 있어요',
      ),
    );
  }
}

class PersonalLoginCard extends StatelessWidget {
  const PersonalLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.phone_iphone_rounded,
        title: '개인형',
        featureText: '모바일 직접 출차 요청',
        traceName: '개인형',
        traceMeta: <String, dynamic>{
          'to': AppRoutes.personalLogin,
          'requiredMode': 'personal',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.personalLogin,
          arguments: <String, dynamic>{'requiredMode': 'personal'},
        ),
        enabled: enabled,
        disabledTooltip: '저장된 모드가 personal일 때만 선택할 수 있어요',
      ),
    );
  }
}

class TabletCard extends StatelessWidget {
  const TabletCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.tablet_mac_rounded,
        title: '태블릿형',
        traceName: '태블릿 로그인',
        traceMeta: <String, dynamic>{
          'to': AppRoutes.tabletLogin,
          'requiredMode': 'tablet',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.tabletLogin,
          arguments: <String, dynamic>{'requiredMode': 'tablet'},
        ),
        enabled: enabled,
        disabledTooltip: '저장된 모드가 tablet일 때만 선택할 수 있어요',
      ),
    );
  }
}

class DevCard extends StatelessWidget {
  const DevCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.developer_mode_rounded,
        title: '개발',
        traceName: '개발',
        traceMeta: const <String, dynamic>{'to': 'dev'},
        onPressed: onTap,
      ),
    );
  }
}

class TripleLoginCard extends StatelessWidget {
  const TripleLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.apps_rounded,
        title: '기본형',
        featureText: '입차 완료 · 출차 요청 · 출차 완료',
        traceName: '기본형',
        traceMeta: <String, dynamic>{
          'to': AppRoutes.tripleLogin,
          'redirectAfterLogin': AppRoutes.tripleCommute,
          'requiredMode': 'triple',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.tripleLogin,
          arguments: <String, dynamic>{
            'redirectAfterLogin': AppRoutes.tripleCommute,
            'requiredMode': 'triple',
          },
        ),
        enabled: enabled,
        disabledTooltip: '저장된 모드가 triple일 때만 선택할 수 있어요',
      ),
    );
  }
}

class ParkingCard extends StatelessWidget {
  const ParkingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.location_city,
        title: 'Practice Space',
        traceName: 'Practice Space',
        traceMeta: <String, dynamic>{'to': AppRoutes.practiceSpaceLab},
        onPressed: () => Navigator.of(context).pushNamed(
          AppRoutes.practiceSpaceLab,
        ),
      ),
    );
  }
}
