import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import 'tablet_prompt_components.dart';

class TabletPlateSearchResultSection extends StatelessWidget {
  const TabletPlateSearchResultSection({
    super.key,
    required this.results,
    required this.onSelect,
    this.onRefresh,
    this.compact = false,
  });

  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;
  final bool compact;

  String _formatDateTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  _StatusColors _statusColors(PromptUiTokens tokens, PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return _StatusColors(
          foreground: tokens.info,
          background: tokens.infoContainer,
          onBackground: tokens.onInfoContainer,
        );
      case PlateType.parkingCompleted:
        return _StatusColors(
          foreground: tokens.statusParkingCompleted,
          background: tokens.statusParkingCompletedContainer,
          onBackground: tokens.onStatusParkingCompletedContainer,
        );
      case PlateType.departureRequests:
        return _StatusColors(
          foreground: tokens.statusDepartureRequested,
          background: tokens.statusDepartureRequestedContainer,
          onBackground: tokens.onStatusDepartureRequestedContainer,
        );
      case PlateType.departureCompleted:
        return _StatusColors(
          foreground: tokens.statusSynchronized,
          background: tokens.statusSynchronizedContainer,
          onBackground: tokens.onStatusSynchronizedContainer,
        );
      case null:
        return _StatusColors(
          foreground: tokens.iconSecondary,
          background: tokens.surfaceOverlay,
          onBackground: tokens.textSecondary,
        );
    }
  }

  IconData _leadingIcon(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return Icons.login_rounded;
      case PlateType.parkingCompleted:
        return Icons.check_circle_outline_rounded;
      case PlateType.departureRequests:
        return Icons.logout_rounded;
      case PlateType.departureCompleted:
        return Icons.task_alt_rounded;
      case null:
        return Icons.directions_car_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final showMultiple = results.length >= 2;
    final extra = showMultiple ? 1 : 0;
    final outerPadding = compact ? 12.0 : 16.0;
    final itemGap = compact ? 10.0 : 12.0;
    final cardRadius = compact ? 16.0 : 18.0;
    final iconBox = compact ? 40.0 : 46.0;
    final cardHorizontal = compact ? 14.0 : 18.0;
    final cardVertical = compact ? 14.0 : 16.0;
    final plateStyle = (compact ? text.titleMedium : text.titleLarge)?.copyWith(
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
      height: 1.12,
    );
    final metaStyle = (compact ? text.bodyMedium : text.bodyLarge)?.copyWith(
      color: tokens.textSecondary,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );

    return ListView.separated(
      padding: EdgeInsets.all(outerPadding),
      itemCount: results.length + extra,
      separatorBuilder: (_, __) => SizedBox(height: itemGap),
      itemBuilder: (context, index) {
        if (showMultiple && index == 0) {
          return PromptAnimatedReveal(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14,
                vertical: compact ? 12 : 14,
              ),
              decoration: BoxDecoration(
                color: tokens.infoContainer,
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(color: tokens.info),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: compact ? 20 : 22,
                    color: tokens.info,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '동일 뒷번호로 ${results.length}건이 조회되었습니다. 아래에서 전체 번호판을 선택하세요.',
                      style: (compact ? text.bodyMedium : text.bodyLarge)
                          ?.copyWith(
                        color: tokens.onInfoContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final plate = results[index - extra];
        final type = plate.typeEnum;
        final typeLabel = type?.label ?? plate.type;
        final colors = _statusColors(tokens, type);
        final selected = plate.isSelected;
        final meta =
            '${_formatDateTime(plate.requestTime)} · ${plate.location.isEmpty ? '위치 미지정' : plate.location}';
        return PromptAnimatedReveal(
          key: ValueKey<String>('plate-${plate.id}-$selected'),
          delay: Duration(milliseconds: (index - extra).clamp(0, 6).toInt() * 28),
          offset: const Offset(0, 0.025),
          child: Semantics(
            button: true,
            selected: selected,
            label: '${plate.plateNumber}, $typeLabel, $meta',
            child: AnimatedContainer(
              duration: tabletPromptDuration(context, PromptUiMotion.selection),
              curve: PromptUiMotion.standard,
              decoration: BoxDecoration(
                color: selected ? tokens.surfaceSelected : tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(cardRadius),
                border: Border.all(
                  color: selected ? tokens.accent : tokens.borderSubtle,
                  width: selected ? 2 : 1,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: selected ? 16 : 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: tokens.transparent,
                borderRadius: BorderRadius.circular(cardRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(plate),
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: cardHorizontal,
                      vertical: cardVertical,
                    ),
                    child: Row(
                      children: <Widget>[
                        AnimatedContainer(
                          duration: tabletPromptDuration(
                            context,
                            PromptUiMotion.selection,
                          ),
                          width: iconBox,
                          height: iconBox,
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(
                              compact ? 14 : 16,
                            ),
                            border: Border.all(color: colors.foreground),
                          ),
                          child: Icon(
                            _leadingIcon(type),
                            size: compact ? 20 : 22,
                            color: colors.foreground,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                plate.plateNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: plateStyle?.copyWith(
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _TypeChip(
                          label: typeLabel,
                          foreground: colors.onBackground,
                          background: colors.background,
                          border: colors.foreground,
                          compact: compact,
                          selected: selected,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusColors {
  const _StatusColors({
    required this.foreground,
    required this.background,
    required this.onBackground,
  });

  final Color foreground;
  final Color background;
  final Color onBackground;
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.compact,
    required this.selected,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.selection),
      curve: PromptUiMotion.standard,
      constraints: BoxConstraints(minHeight: compact ? 32 : 38),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: border, width: selected ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (selected) ...<Widget>[
            Icon(Icons.check_rounded, size: 15, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.labelLarge
                      : Theme.of(context).textTheme.titleSmall)
                  ?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
