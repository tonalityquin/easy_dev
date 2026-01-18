import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes.dart';
import '../theme.dart';

// ✅ Trace 기록용 Recorder
import '../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

Text _selectorCardTitle(BuildContext context, String text, Color color) {
  return Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: color,
    ),
  );
}

/// ✅ 카드에 표시할 기능 요약(서브 타이틀) 스타일
Widget _selectorCardFeatureText(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Text(
    text,
    textAlign: TextAlign.center,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: cs.onSurface.withOpacity(0.62),
    ),
  );
}

class CardBody extends StatefulWidget {
  const CardBody({
    super.key,
    required this.icon,
    required this.bg,
    required this.iconColor,
    this.buttonBg,
    this.buttonFg,
    required this.titleWidget,

    // ✅ 기능 안내 문구(선택)
    this.featureText,

    required this.onPressed,
    this.enabled = true,
    this.disabledHint,

    // ✅ Trace 기록용
    required this.traceName,
    this.traceMeta,
  });

  final IconData icon;
  final Color bg;
  final Color iconColor;
  final Color? buttonBg;
  final Color? buttonFg;

  final Widget titleWidget;

  /// ✅ 카드에 “제공 기능”을 보여주기 위한 서브 타이틀(없으면 표시하지 않음)
  final String? featureText;

  final VoidCallback? onPressed;
  final bool enabled;
  final String? disabledHint;

  // ✅ Trace 기록용
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

      // ✅ Trace 기록: 기록 중이 아닐 때는 Recorder 내부에서 무시됨
      DebugActionRecorder.instance.recordAction(
        widget.traceName,
        route: ModalRoute.of(context)?.settings.name,
        meta: <String, dynamic>{
          'source': source, // 'card' or 'arrow'
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
    final hasFeature = widget.featureText != null && widget.featureText!.trim().isNotEmpty;

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LeadingIcon(
            bg: widget.bg,
            icon: widget.icon,
            iconColor: widget.iconColor,
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
              onPressed: widget.enabled ? () => _animateThenNavigate(source: 'arrow') : null,
              style: IconButton.styleFrom(
                backgroundColor: widget.buttonBg ?? Theme.of(context).colorScheme.primary,
                foregroundColor: widget.buttonFg ?? Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.48,
      child: AnimatedScale(
        scale: _pressed ? _pressScale : 1.0,
        duration: _duration,
        curve: Curves.easeOut,
        child: InkWell(
          onTap: widget.enabled ? () => _animateThenNavigate(source: 'card') : null,
          child: content,
        ),
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

/// 개별 카드들 (팔레트는 theme.dart(AppCardPalette)에서 주입)

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    this.enabled = true,
    this.devAuthorized = false,
  });

  final bool enabled;
  final bool devAuthorized;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, '서비스 로그인', p.serviceDark);

    final bool effectiveEnabled = enabled && devAuthorized;
    final String hint = !devAuthorized
        ? '개발자 인증 후 사용할 수 있어요'
        : '저장된 모드가 service일 때만 선택할 수 있어요';

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.serviceLight,
      child: CardBody(
        icon: Icons.local_parking,
        bg: p.serviceBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.serviceBase,
        buttonFg: onBase,
        traceName: '서비스 로그인',
        traceMeta: {
          'to': AppRoutes.serviceLogin,
          'requiredMode': 'service',
          'requiresDevAuth': true,
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.serviceLogin),
        enabled: effectiveEnabled,
        disabledHint: hint,
      ),
    );
  }
}

class SingleLoginCard extends StatelessWidget {
  const SingleLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'WorkFlow D', p.singleDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.singleLight,
      child: CardBody(
        icon: Icons.access_time_filled_rounded,
        bg: p.singleBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.singleBase,
        buttonFg: onBase,
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
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'WorkFlow A', p.doubleDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.doubleLight,
      child: CardBody(
        icon: Icons.bolt_rounded,
        bg: p.doubleBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.doubleBase,
        buttonFg: onBase,
        featureText: '입차 완료 · 출차 완료',
        traceName: 'WorkFlow A',
        traceMeta: {'to': AppRoutes.doubleLogin, 'requiredMode': 'double'},
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.doubleLogin,
          arguments: {
            'requiredMode': 'double',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 double일 때만 선택할 수 있어요',
      ),
    );
  }
}

/// ✅ 마이너 로그인 카드 (WorkFlow C) - 정합 완료
/// - requiredMode: 'minor'
/// - redirectAfterLogin: AppRoutes.minorCommute
class MinorLoginCard extends StatelessWidget {
  const MinorLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    // ✅ minor 색상 적용
    final title = _selectorCardTitle(context, 'WorkFlow C', p.minorDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.minorLight,
      child: CardBody(
        icon: Icons.tune_rounded,
        bg: p.minorBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.minorBase,
        buttonFg: onBase,
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
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'Tablet Mode', p.tabletDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.tabletLight,
      child: CardBody(
        icon: Icons.tablet_mac_rounded,
        bg: p.tabletBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.tabletBase,
        buttonFg: onBase,
        traceName: '태블릿 로그인',
        traceMeta: {'to': AppRoutes.tabletLogin, 'requiredMode': 'tablet'},
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.tabletLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 tablet일 때만 선택할 수 있어요',
      ),
    );
  }
}

class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'Community', p.communityDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.communityLight,
      child: CardBody(
        icon: Icons.groups_rounded,
        bg: p.communityBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.communityBase,
        buttonFg: onBase,
        traceName: 'Community',
        traceMeta: {'to': AppRoutes.communityStub},
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.communityStub),
      ),
    );
  }
}

class FaqCard extends StatelessWidget {
  const FaqCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'FAQ', p.faqDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.faqLight,
      child: CardBody(
        icon: Icons.help_center_rounded,
        bg: p.faqBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.faqBase,
        buttonFg: onBase,
        traceName: 'FAQ',
        traceMeta: {'to': AppRoutes.faq},
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.faq),
      ),
    );
  }
}

class HeadquarterCard extends StatelessWidget {
  const HeadquarterCard({super.key});

  Future<void> _handleTap(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final division = prefs.getString('division') ?? '';
      final selectedArea = prefs.getString('selectedArea') ?? '';

      final allowed = division.isNotEmpty && selectedArea.isNotEmpty && division == selectedArea;

      if (allowed) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.headStub);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('본사 접근 권한이 없는 계정입니다. 관리자에게 문의하세요.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('본사 접근 여부 확인 중 오류가 발생했습니다: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'HeadQuarter', p.headquarterDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.headquarterLight,
      child: CardBody(
        icon: Icons.apartment_rounded,
        bg: p.headquarterBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.headquarterBase,
        buttonFg: onBase,
        traceName: 'HeadQuarter',
        traceMeta: {'to': AppRoutes.headStub},
        onPressed: () => _handleTap(context),
      ),
    );
  }
}

class DevCard extends StatelessWidget {
  const DevCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, '개발', p.devDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.devLight,
      child: CardBody(
        icon: Icons.developer_mode_rounded,
        bg: p.devBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.devBase,
        buttonFg: onBase,
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
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'WorkFlow B', p.tripleDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.tripleLight,
      child: CardBody(
        icon: Icons.apps_rounded,
        bg: p.tripleBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.tripleBase,
        buttonFg: onBase,
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
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, 'Practice Space', p.parkingDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.parkingLight,
      child: CardBody(
        icon: Icons.location_city,
        bg: p.parkingBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.parkingBase,
        buttonFg: onBase,
        traceName: '오프라인 서비스',
        traceMeta: {'to': AppRoutes.offlineLogin},
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.offlineLogin),
      ),
    );
  }
}
