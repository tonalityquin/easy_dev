import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../dev/debug/debug_action_recorder.dart';

@immutable
class _SelectorCardTokens {
  const _SelectorCardTokens({
    required this.cardSurface,
    required this.cardBorder,
    required this.iconBg,
    required this.iconFg,
    required this.titleFg,
    required this.featureFg,
    required this.ctaBg,
    required this.ctaFg,
    required this.disabledOpacity,
  });

  final Color cardSurface;
  final Color cardBorder;
  final Color iconBg;
  final Color iconFg;
  final Color titleFg;
  final Color featureFg;
  final Color ctaBg;
  final Color ctaFg;
  final double disabledOpacity;

  factory _SelectorCardTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _SelectorCardTokens(
      cardSurface: cs.surfaceContainerLow,
      cardBorder: cs.outlineVariant.withOpacity(0.55),
      iconBg: cs.primaryContainer,
      iconFg: cs.onPrimaryContainer,
      titleFg: cs.onSurface,
      featureFg: cs.onSurfaceVariant,
      ctaBg: cs.primary,
      ctaFg: cs.onPrimary,
      disabledOpacity: 0.48,
    );
  }
}

Text _selectorCardTitle(BuildContext context, String text) {
  final t = _SelectorCardTokens.of(context);
  return Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: t.titleFg,
    ),
  );
}

Widget _selectorCardFeatureText(
    BuildContext context,
    String text, {
      TextAlign textAlign = TextAlign.center,
      int maxLines = 2,
    }) {
  final t = _SelectorCardTokens.of(context);
  return Text(
    text,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: t.featureFg,
    ),
  );
}

Widget _selectorCardStaticCta(BuildContext context) {
  final t = _SelectorCardTokens.of(context);
  return Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: t.ctaBg,
      shape: BoxShape.circle,
    ),
    child: Icon(
      Icons.arrow_forward_rounded,
      color: t.ctaFg,
      size: 22,
    ),
  );
}

class CardBody extends StatefulWidget {
  const CardBody({
    super.key,
    required this.icon,
    required this.titleWidget,
    required this.onPressed,
    this.enabled = true,
    this.disabledHint,
    this.featureText,
    required this.traceName,
    this.traceMeta,
  });

  final IconData icon;
  final Widget titleWidget;
  final String? featureText;
  final VoidCallback? onPressed;
  final bool enabled;
  final String? disabledHint;
  final String traceName;
  final Map<String, dynamic>? traceMeta;

  @override
  State<CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<CardBody> {
  static const _pressScale = 0.96;
  static const _duration = Duration(milliseconds: 160);
  static const _frame = Duration(milliseconds: 16);

  bool _pressed = false;
  bool _animating = false;

  Future<void> _animateThenNavigate({required String source}) async {
    if (!widget.enabled || widget.onPressed == null || _animating) return;
    _animating = true;

    try {
      if (mounted) setState(() => _pressed = true);

      await Future<void>.delayed(_frame);
      await Future<void>.delayed(_duration);

      HapticFeedback.selectionClick();

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

      widget.onPressed!.call();
    } finally {
      _animating = false;
      if (mounted) setState(() => _pressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _SelectorCardTokens.of(context);
    final hasFeature =
        widget.featureText != null && widget.featureText!.trim().isNotEmpty;

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LeadingIcon(
            bg: t.iconBg,
            icon: widget.icon,
            iconColor: t.iconFg,
          ),
          const SizedBox(height: 12),
          widget.titleWidget,
          if (hasFeature) ...[
            const SizedBox(height: 6),
            _selectorCardFeatureText(context, widget.featureText!.trim()),
            const SizedBox(height: 10),
          ] else ...[
            const SizedBox(height: 12),
          ],
          Tooltip(
            message: widget.enabled
                ? '이동'
                : (widget.disabledHint ?? '현재 저장된 모드에서만 선택할 수 있어요'),
            child: IconButton.filled(
              onPressed: widget.enabled
                  ? () => _animateThenNavigate(source: 'arrow')
                  : null,
              style: IconButton.styleFrom(
                backgroundColor: t.ctaBg,
                foregroundColor: t.ctaFg,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : t.disabledOpacity,
      child: AnimatedScale(
        scale: _pressed ? _pressScale : 1.0,
        duration: _duration,
        curve: Curves.easeOut,
        child: InkWell(
          onTap: widget.enabled
              ? () => _animateThenNavigate(source: 'card')
              : null,
          child: content,
        ),
      ),
    );
  }
}

class StaticCardBody extends StatelessWidget {
  const StaticCardBody({
    super.key,
    required this.icon,
    required this.titleWidget,
    this.featureText,
  });

  final IconData icon;
  final Widget titleWidget;
  final String? featureText;

  @override
  Widget build(BuildContext context) {
    final t = _SelectorCardTokens.of(context);
    final hasFeature =
        featureText != null && featureText!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LeadingIcon(
            bg: t.iconBg,
            icon: icon,
            iconColor: t.iconFg,
          ),
          const SizedBox(height: 12),
          titleWidget,
          if (hasFeature) ...[
            const SizedBox(height: 6),
            _selectorCardFeatureText(context, featureText!.trim()),
            const SizedBox(height: 10),
          ] else ...[
            const SizedBox(height: 12),
          ],
          _selectorCardStaticCta(context),
        ],
      ),
    );
  }
}

class LeadingIcon extends StatelessWidget {
  const LeadingIcon({
    super.key,
    required this.bg,
    required this.icon,
    required this.iconColor,
  });

  final Color bg;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 28),
    );
  }
}

Widget _selectorCardShell({
  required BuildContext context,
  required Widget child,
}) {
  final t = _SelectorCardTokens.of(context);

  return Card(
    color: t.cardSurface,
    elevation: 1,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: t.cardBorder),
    ),
    child: child,
  );
}

class ExperienceCard extends StatelessWidget {
  const ExperienceCard({super.key});

  Future<void> _openDescription(
    BuildContext context, {
    required String source,
  }) async {
    HapticFeedback.selectionClick();
    DebugActionRecorder.instance.recordAction(
      '앱에 대해 알아보기',
      route: ModalRoute.of(context)?.settings.name,
      meta: {
        'source': source,
        'to': AppRoutes.descriptionIntro,
      },
    );
    await Navigator.of(context).pushNamed(AppRoutes.descriptionIntro);
  }

  @override
  Widget build(BuildContext context) {
    final t = _SelectorCardTokens.of(context);
    final title = _selectorCardTitle(context, '앱에 대해 알아보기');
    final textTheme = Theme.of(context).textTheme;

    return _selectorCardShell(
      context: context,
      child: InkWell(
        onTap: () => _openDescription(context, source: 'card'),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LeadingIcon(
                      bg: t.iconBg,
                      icon: Icons.explore_rounded,
                      iconColor: t.iconFg,
                    ),
                    const SizedBox(height: 12),
                    title,
                    const SizedBox(height: 6),
                    _selectorCardFeatureText(
                      context,
                      '대표 흐름과 화면 구성을 먼저 둘러보세요',
                    ),
                    const SizedBox(height: 10),
                    Tooltip(
                      message: '앱에 대해 알아보기 열기',
                      child: IconButton.filled(
                        onPressed: () => _openDescription(context, source: 'arrow'),
                        style: IconButton.styleFrom(
                          backgroundColor: t.ctaBg,
                          foregroundColor: t.ctaFg,
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              color: t.cardBorder,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '체험 안내',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.titleFg,
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
    );
  }
}

class SingleLoginCard extends StatelessWidget {
  const SingleLoginCard({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final title = _selectorCardTitle(context, 'WorkFlow D');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.access_time_filled_rounded,
        titleWidget: title,
        featureText: '출/퇴근 · 휴게시간',
        traceName: 'WorkFlow D',
        traceMeta: {
          'to': AppRoutes.singleLogin,
          'redirectAfterLogin': AppRoutes.singleCommute,
          'requiredMode': 'single',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.singleLogin,
          arguments: {
            'redirectAfterLogin': AppRoutes.singleCommute,
            'requiredMode': 'single',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 single일 때만 선택할 수 있어요',
      ),
    );
  }
}

class DoubleLoginCard extends StatelessWidget {
  const DoubleLoginCard({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final title = _selectorCardTitle(context, 'WorkFlow A');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.bolt_rounded,
        titleWidget: title,
        featureText: '입차 완료 · 출차 완료',
        traceName: 'WorkFlow A',
        traceMeta: {'to': AppRoutes.doubleLogin, 'requiredMode': 'double'},
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.doubleLogin,
          arguments: {'requiredMode': 'double'},
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 double일 때만 선택할 수 있어요',
      ),
    );
  }
}

class MinorLoginCard extends StatelessWidget {
  const MinorLoginCard({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final title = _selectorCardTitle(context, 'WorkFlow C');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.tune_rounded,
        titleWidget: title,
        featureText: '입차 요청 · 입차 완료 · 출차 요청 · 출차 완료',
        traceName: 'WorkFlow C',
        traceMeta: {
          'to': AppRoutes.minorLogin,
          'redirectAfterLogin': AppRoutes.minorCommute,
          'requiredMode': 'minor',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.minorLogin,
          arguments: {
            'redirectAfterLogin': AppRoutes.minorCommute,
            'requiredMode': 'minor',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 minor일 때만 선택할 수 있어요',
      ),
    );
  }
}

class TabletCard extends StatelessWidget {
  const TabletCard({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final title = _selectorCardTitle(context, 'Tablet Mode');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.tablet_mac_rounded,
        titleWidget: title,
        traceName: '태블릿 로그인',
        traceMeta: {'to': AppRoutes.tabletLogin, 'requiredMode': 'tablet'},
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.tabletLogin,
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 tablet일 때만 선택할 수 있어요',
      ),
    );
  }
}

class DevCard extends StatelessWidget {
  const DevCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = _selectorCardTitle(context, '개발');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.developer_mode_rounded,
        titleWidget: title,
        traceName: '개발',
        traceMeta: {'to': 'dev'},
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
    final title = _selectorCardTitle(context, 'WorkFlow B');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.apps_rounded,
        titleWidget: title,
        featureText: '입차 완료 · 출차 요청 · 출차 완료',
        traceName: 'WorkFlow B',
        traceMeta: {
          'to': AppRoutes.tripleLogin,
          'redirectAfterLogin': AppRoutes.tripleCommute,
          'requiredMode': 'triple',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.tripleLogin,
          arguments: {
            'redirectAfterLogin': AppRoutes.tripleCommute,
            'requiredMode': 'triple',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 triple일 때만 선택할 수 있어요',
      ),
    );
  }
}

class ParkingCard extends StatelessWidget {
  const ParkingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final title = _selectorCardTitle(context, 'Practice Space');

    return _selectorCardShell(
      context: context,
      child: CardBody(
        icon: Icons.location_city,
        titleWidget: title,
        traceName: 'Practice Space',
        traceMeta: {'to': AppRoutes.practiceSpaceLab},
        onPressed: () => Navigator.of(context).pushNamed(
          AppRoutes.practiceSpaceLab,
        ),
      ),
    );
  }
}
