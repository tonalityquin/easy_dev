import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../routes.dart';
import '../../utils/google_auth_session.dart';

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

  @override
  State<CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<CardBody> {
  static const _pressScale = 0.96;
  static const _duration = Duration(milliseconds: 160);
  static const _frame = Duration(milliseconds: 16);

  bool _pressed = false;
  bool _animating = false;

  Future<void> _animateThenNavigate() async {
    if (!widget.enabled || widget.onPressed == null || _animating) return;
    _animating = true;
    setState(() => _pressed = true);
    await Future<void>.delayed(_frame);
    await Future<void>.delayed(_duration);
    HapticFeedback.selectionClick();
    widget.onPressed!.call();
    _animating = false;
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LeadingIcon(bg: widget.bg, icon: widget.icon, iconColor: widget.iconColor),
          const SizedBox(height: 12),
          widget.titleWidget,
          const SizedBox(height: 12),
          Tooltip(
            message: widget.enabled ? '이동' : (widget.disabledHint ?? '현재 저장된 모드에서만 선택할 수 있어요'),
            child: IconButton.filled(
              onPressed: widget.enabled ? _animateThenNavigate : null,
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
          onTap: widget.enabled ? _animateThenNavigate : null,
          child: content,
        ),
      ),
    );
  }
}

class LeadingIcon extends StatelessWidget {
  const LeadingIcon({super.key, required this.bg, required this.icon, required this.iconColor});

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

/// 개별 카드들 (기존 색 팔레트 유지)
class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, this.enabled = true});

  final bool enabled;

  static const Color _base = Color(0xFF0D47A1);
  static const Color _dark = Color(0xFF09367D);
  static const Color _light = Color(0xFF5472D3);

  @override
  Widget build(BuildContext context) {
    final title = Text('서비스 로그인',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.local_parking,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.serviceLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 service일 때만 선택할 수 있어요',
      ),
    );
  }
}

class TabletCard extends StatelessWidget {
  const TabletCard({super.key, this.enabled = true});

  final bool enabled;

  static const Color _base = Color(0xFF00ACC1);
  static const Color _dark = Color(0xFF00838F);
  static const Color _light = Color(0xFF4DD0E1);

  @override
  Widget build(BuildContext context) {
    final title = Text('태블릿 로그인',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.tablet_mac_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.tabletLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 tablet일 때만 선택할 수 있어요',
      ),
    );
  }
}

class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key});

  static const Color _base = Color(0xFF26A69A);
  static const Color _dark = Color(0xFF1E8077);
  static const Color _light = Color(0xFF64D8CB);

  @override
  Widget build(BuildContext context) {
    final title = Text('커뮤니티',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.groups_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.communityStub),
      ),
    );
  }
}

class FaqCard extends StatelessWidget {
  const FaqCard({super.key});

  static const Color _base = Color(0xFF3949AB);
  static const Color _dark = Color(0xFF283593);
  static const Color _light = Color(0xFF7986CB);

  @override
  Widget build(BuildContext context) {
    final title = Text('FAQ / 문의',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.help_center_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.faq),
      ),
    );
  }
}

class HeadquarterCard extends StatelessWidget {
  const HeadquarterCard({super.key});

  static const Color _base = Color(0xFF1E88E5);
  static const Color _dark = Color(0xFF1565C0);
  static const Color _light = Color(0xFF64B5F6);

  static const Set<String> _allowedEmails = {
    'belivus02@gmail.com',
    'belivus150119@gmail.com',
    'surge1868@gmail.com',
    'gyoshinc@gmail.com',
  };

  @override
  Widget build(BuildContext context) {
    final title =
        Text('본사', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.apartment_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: () async {
          try {
            // 1) 필요 시 이 시점에 계정 인증/선택(최초 1회만 동의창)
            await GoogleAuthSession.instance.safeClient();

            // 2) 현재 Google 계정 이메일 확인
            final email = GoogleAuthSession.instance.currentUser?.email.toLowerCase() ?? '';

            // 3) 화이트리스트 검사
            if (_allowedEmails.contains(email)) {
              Navigator.of(context).pushReplacementNamed(AppRoutes.headStub);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('본사 접근 권한이 없는 계정입니다. 관리자에게 문의하세요.')),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Google 인증에 실패했습니다: $e')),
            );
          }
        },
      ),
    );
  }
}

class DevCard extends StatelessWidget {
  const DevCard({super.key, required this.onTap});

  final VoidCallback onTap;

  static const Color _base = Color(0xFF6A1B9A);
  static const Color _dark = Color(0xFF4A148C);
  static const Color _light = Color(0xFFCE93D8);

  @override
  Widget build(BuildContext context) {
    final title =
        Text('개발', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.developer_mode_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: onTap,
      ),
    );
  }
}

class ParkingCard extends StatelessWidget {
  const ParkingCard({super.key});

  static const Color _base = Color(0xFFF4511E);
  static const Color _dark = Color(0xFFD84315);
  static const Color _light = Color(0xFFFFAB91);

  @override
  Widget build(BuildContext context) {
    final title = Text('오프라인 서비스',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark));

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: CardBody(
        icon: Icons.location_city,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: title,
        buttonBg: _base,
        buttonFg: Colors.white,
        onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.offlineLogin),
      ),
    );
  }
}
