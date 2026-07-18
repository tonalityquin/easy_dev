import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../account/applications/user_state.dart';

class PromptHqUserInfoCard extends StatefulWidget {
  const PromptHqUserInfoCard({super.key});

  @override
  State<PromptHqUserInfoCard> createState() => _PromptHqUserInfoCardState();
}

class _PromptHqUserInfoCardState extends State<PromptHqUserInfoCard> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = _pressed || _hovered
        ? tokens.surfaceSelected
        : tokens.surfaceRaised;

    return Semantics(
      button: true,
      label: '근무자 정보',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(
            color: _focused ? tokens.focusRing : tokens.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: [
            if (_hovered)
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
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            onTap: HapticFeedback.selectionClick,
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
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AnimatedScale(
                scale: _pressed ? 0.992 : 1,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.badge_rounded,
                          size: 16,
                          color: tokens.iconSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '근무자 정보',
                          style: textTheme.labelMedium?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: tokens.accentContainer,
                            borderRadius:
                                BorderRadius.circular(PromptUiShapes.control),
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person_rounded,
                            color: tokens.onAccentContainer,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _safe(userState.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _safe(userState.position),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: tokens.surfaceOverlay,
                            borderRadius:
                                BorderRadius.circular(PromptUiShapes.control),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.qr_code_rounded,
                            color: tokens.iconSecondary,
                            size: 21,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: tokens.borderSubtle, height: 1),
                    const SizedBox(height: 10),
                    _PromptHqInfoRow(
                      icon: Icons.phone_rounded,
                      value: _safe(userState.phone),
                    ),
                    const SizedBox(height: 8),
                    _PromptHqInfoRow(
                      icon: Icons.location_on_rounded,
                      value: _safe(userState.area),
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

  String _safe(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '-' : trimmed;
  }
}

class _PromptHqInfoRow extends StatelessWidget {
  const _PromptHqInfoRow({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.iconSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
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
