import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

enum LocationCreationType { plain, diagram }

class LocationCreationTypePickerDialog extends StatelessWidget {
  const LocationCreationTypePickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.surfaceRaised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '주차구역 생성 방식',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '운영 방식에 맞는 구역 유형을 선택하세요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _LocationCreationTypeCard(
                        type: LocationCreationType.plain,
                        icon: Icons.view_headline_rounded,
                        title: '텍스트형 주차구역',
                        description: '구역명과 수용 가능 차량 수만으로 빠르게 운영 구역을 생성합니다.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _LocationCreationTypeCard(
                        type: LocationCreationType.diagram,
                        icon: Icons.grid_view_rounded,
                        title: '도면형 주차구역',
                        description: 'Parking Grid와 자식구역을 이용해 실제 공간 구조를 상세하게 구성합니다.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCreationTypeCard extends StatefulWidget {
  const _LocationCreationTypeCard({
    required this.type,
    required this.icon,
    required this.title,
    required this.description,
  });

  final LocationCreationType type;
  final IconData icon;
  final String title;
  final String description;

  @override
  State<_LocationCreationTypeCard> createState() =>
      _LocationCreationTypeCardState();
}

class _LocationCreationTypeCardState
    extends State<_LocationCreationTypeCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  Future<void> _select() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(widget.type);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.title,
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        scale: _pressed ? .985 : 1,
        child: Material(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            onTap: _select,
            onHighlightChanged: _setPressed,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius:
                          BorderRadius.circular(CommonUiShapes.control),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, color: tokens.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.description,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: tokens.textSecondary,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 17,
                    color: tokens.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
