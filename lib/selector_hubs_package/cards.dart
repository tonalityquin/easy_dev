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

class CardBody extends StatefulWidget {
  const CardBody({
    super.key,
    required this.icon,
    required this.bg,
    required this.iconColor,
    this.buttonBg,
    this.buttonFg,
    required this.titleWidget,
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
          const SizedBox(height: 12),
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
  const ServiceCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, '서비스 로그인', p.serviceDark);

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
        traceMeta: {'to': AppRoutes.serviceLogin, 'requiredMode': 'service'},
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.serviceLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 service일 때만 선택할 수 있어요',
      ),
    );
  }
}

class SimpleLoginCard extends StatelessWidget {
  const SimpleLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, '약식 로그인', p.simpleDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.simpleLight,
      child: CardBody(
        icon: Icons.access_time_filled_rounded,
        bg: p.simpleBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.simpleBase,
        buttonFg: onBase,
        traceName: '약식 로그인',
        traceMeta: {
          'to': AppRoutes.simpleLogin,
          'redirectAfterLogin': AppRoutes.simpleCommute,
          'requiredMode': 'simple',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.simpleLogin,
          arguments: {
            'redirectAfterLogin': AppRoutes.simpleCommute,
            'requiredMode': 'simple',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 simple일 때만 선택할 수 있어요',
      ),
    );
  }
}

class LiteLoginCard extends StatelessWidget {
  const LiteLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, '경량 로그인', p.liteDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.liteLight,
      child: CardBody(
        icon: Icons.bolt_rounded,
        bg: p.liteBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.liteBase,
        buttonFg: onBase,
        traceName: '경량 로그인',
        traceMeta: {'to': AppRoutes.liteLogin, 'requiredMode': 'lite'},
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.liteLogin,
          arguments: {
            'requiredMode': 'lite',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 lite일 때만 선택할 수 있어요',
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

    final title = _selectorCardTitle(context, '태블릿 로그인', p.tabletDark);

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

    final title = _selectorCardTitle(context, '커뮤니티', p.communityDark);

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
        traceName: '커뮤니티',
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

    final title = _selectorCardTitle(context, 'FAQ / 문의', p.faqDark);

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
        traceName: 'FAQ / 문의',
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

      // ✅ mode 조건 삭제 (요청 반영)
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

    final title = _selectorCardTitle(context, '본사', p.headquarterDark);

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
        traceName: '본사',
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

/// ✅ 노말 로그인 카드 (다른 모드 카드와 동일 패턴)
/// - enabled/disabledHint 지원
/// - AppRoutes.normalLogin 으로 이동
/// - requiredMode/redirectAfterLogin 인자 전달
class NormalLoginCard extends StatelessWidget {
  const NormalLoginCard({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = AppCardPalette.of(context);
    final onBase = Theme.of(context).colorScheme.onPrimary;

    final title = _selectorCardTitle(context, '노말 로그인', p.normalDark);

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: p.normalLight,
      child: CardBody(
        icon: Icons.apps_rounded,
        bg: p.normalBase,
        iconColor: onBase,
        titleWidget: title,
        buttonBg: p.normalBase,
        buttonFg: onBase,
        traceName: '노말 로그인',
        traceMeta: {
          'to': AppRoutes.normalLogin,
          'redirectAfterLogin': AppRoutes.normalCommute,
          'requiredMode': 'normal',
        },
        onPressed: () => Navigator.of(context).pushReplacementNamed(
          AppRoutes.normalLogin,
          arguments: {
            'redirectAfterLogin': AppRoutes.normalCommute,
            'requiredMode': 'normal',
          },
        ),
        enabled: enabled,
        disabledHint: '저장된 모드가 normal일 때만 선택할 수 있어요',
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

    final title = _selectorCardTitle(context, '오프라인 서비스', p.parkingDark);

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
