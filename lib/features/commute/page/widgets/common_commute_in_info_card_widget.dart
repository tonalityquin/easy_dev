import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../account/applications/user_state.dart';

class CommonCommuteInInfoCardWidget extends StatefulWidget {
  const CommonCommuteInInfoCardWidget({super.key});

  @override
  State<CommonCommuteInInfoCardWidget> createState() =>
      _CommonCommuteInInfoCardWidgetState();
}

class _CommonCommuteInInfoCardWidgetState
    extends State<CommonCommuteInInfoCardWidget> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = _pressed || _hovered
        ? tokens.surfaceSelected
        : tokens.surfaceRaised;
    final border = _focused ? tokens.focusRing : tokens.borderSubtle;

    return Semantics(
      button: true,
      label: '근무자 상세 정보',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(
            color: border,
            width: _focused ? 2 : 1,
          ),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: tokens.focusRing.withOpacity(0.24),
                blurRadius: 0,
                spreadRadius: 2,
              )
            else if (_hovered)
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
          ],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              debugPrint('📄 사용자 상세 정보 보기');
            },
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
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(_pressed ? 0.10 : 0.05),
            ),
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            child: AnimatedScale(
              scale: _pressed ? 0.992 : 1,
              duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
              curve: PromptUiMotion.enter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: tokens.accentContainer,
                            borderRadius: BorderRadius.circular(
                              PromptUiShapes.control,
                            ),
                          ),
                          child: Icon(
                            Icons.badge_outlined,
                            size: 18,
                            color: tokens.onAccentContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '근무자 카드',
                            style: text.labelLarge?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tokens.surfaceOverlay,
                            borderRadius: BorderRadius.circular(
                              PromptUiShapes.control,
                            ),
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          child: Icon(
                            Icons.qr_code_rounded,
                            size: 20,
                            color: tokens.iconSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: tokens.accentContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: tokens.accent.withOpacity(
                                tokens.isDark ? 0.58 : 0.36,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: tokens.onAccentContainer,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userState.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleLarge?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                userState.position,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Divider(height: 1, color: tokens.borderSubtle),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.phone_rounded,
                      label: 'Tel.',
                      value: _formatPhoneNumber(userState.phone),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      label: 'Sector.',
                      value: userState.area,
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

  String _formatPhoneNumber(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}-${phone.substring(3, 7)}-${phone.substring(7)}';
    }
    if (phone.length == 10) {
      return '${phone.substring(0, 3)}-${phone.substring(3, 6)}-${phone.substring(6)}';
    }
    return phone;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.iconSecondary),
          const SizedBox(width: 9),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
