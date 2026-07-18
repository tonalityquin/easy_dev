import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../app/init/app_exit_service.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../sheets/service_bottom_sheet.dart';

const String _kPrivacyUrl = 'https://forms.gle/hDTkX1p6U9jMMuySA';

class Header extends StatefulWidget {
  const Header({super.key});

  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  Future<void> _openPrivacy() async {
    try {
      await launchUrlString(
        _kPrivacyUrl,
        mode: LaunchMode.externalApplication,
      );
      return;
    } catch (_) {}

    try {
      await launchUrlString(
        _kPrivacyUrl,
        mode: LaunchMode.platformDefault,
      );
    } catch (_) {}
  }

  Widget _buildDetailSection(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
      curve: PromptUiMotion.standard,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderStrong.withOpacity(0.58)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
            ),
            child: Icon(
              Icons.privacy_tip_outlined,
              size: 19,
              color: tokens.onAccentContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '앱 이용 문의',
                  style: text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '외부 설문조사 화면으로 이동합니다.',
                  style: text.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PromptButton(
            label: 'Shortcut',
            icon: Icons.open_in_new_rounded,
            onPressed: _openPrivacy,
            variant: PromptButtonVariant.secondary,
            haptic: PromptHaptic.selection,
            minHeight: 42,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        _TopRow(
          expanded: _expanded,
          onToggle: _toggleExpanded,
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: PromptUiMotion.component,
          switchInCurve: PromptUiMotion.enter,
          switchOutCurve: PromptUiMotion.exit,
          child: Text(
            '환영합니다',
            key: const ValueKey<String>('welcome'),
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const DbConnectionStatusSection(usePromptUi: true),
        const SizedBox(height: 12),
        _buildDetailSection(context),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  Future<void> _openServiceSheet(BuildContext context) async {
    if (!expanded) return;
    await ServiceBottomSheet.show(context: context);
  }

  Future<void> _exitApp(BuildContext context) async {
    await AppExitService.exitApp(context, usePromptUi: true);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AnimatedSide(
          show: expanded,
          axisAlignment: -1,
          child: PromptButton(
            label: '앱 설정',
            icon: Icons.settings_outlined,
            onPressed: () => _openServiceSheet(context),
            variant: PromptButtonVariant.secondary,
            haptic: PromptHaptic.selection,
            minHeight: 44,
          ),
        ),
        const SizedBox(width: 12),
        HeaderBadge(
          size: 64,
          ring: 3,
          onToggle: onToggle,
        ),
        const SizedBox(width: 12),
        _AnimatedSide(
          show: expanded,
          axisAlignment: 1,
          child: PromptButton(
            label: '앱 종료',
            icon: Icons.power_settings_new,
            onPressed: () => _exitApp(context),
            variant: PromptButtonVariant.destructive,
            haptic: PromptHaptic.heavy,
            minHeight: 44,
          ),
        ),
      ],
    );
  }
}

class _AnimatedSide extends StatelessWidget {
  const _AnimatedSide({
    required this.show,
    required this.child,
    this.axisAlignment = 0,
  });

  final bool show;
  final Widget child;
  final double axisAlignment;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Flexible(
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
        switchInCurve: PromptUiMotion.enter,
        switchOutCurve: PromptUiMotion.exit,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              axis: Axis.horizontal,
              sizeFactor: animation,
              axisAlignment: axisAlignment,
              child: ClipRect(child: child),
            ),
          );
        },
        child: show
            ? Container(
                key: const ValueKey<String>('side-on'),
                alignment: Alignment.center,
                child: child,
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('side-off'),
              ),
      ),
    );
  }
}

class HeaderBadge extends StatelessWidget {
  const HeaderBadge({
    super.key,
    this.size = 64,
    this.ring = 3,
    this.onToggle,
  });

  final double size;
  final double ring;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return TweenAnimationBuilder<double>(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
      tween: Tween<double>(begin: 0.94, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.accent,
          ),
          child: Padding(
            padding: EdgeInsets.all(ring),
            child: _HeaderBadgeInner(onToggle: onToggle),
          ),
        ),
      ),
    );
  }
}

class _HeaderBadgeInner extends StatefulWidget {
  const _HeaderBadgeInner({this.onToggle});

  final VoidCallback? onToggle;

  @override
  State<_HeaderBadgeInner> createState() => _HeaderBadgeInnerState();
}

class _HeaderBadgeInnerState extends State<_HeaderBadgeInner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  bool _pressed = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: PromptUiMotion.layout,
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _rotationController.value = 1;
    } else {
      _rotationController.forward(from: 0);
    }
    widget.onToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      button: true,
      label: '허브 메뉴',
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
        curve: PromptUiMotion.enter,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          decoration: BoxDecoration(
            color: tokens.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: _focused ? tokens.focusRing : tokens.transparent,
              width: _focused ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: tokens.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _onTap,
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              onFocusChange: (value) {
                if (_focused == value) return;
                setState(() => _focused = value);
              },
              customBorder: const CircleBorder(),
              child: Center(
                child: RotationTransition(
                  turns: Tween<double>(begin: 0, end: 1).animate(
                    CurvedAnimation(
                      parent: _rotationController,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: Icon(
                    Icons.dashboard_customize_rounded,
                    color: tokens.iconPrimary,
                    size: 28,
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
