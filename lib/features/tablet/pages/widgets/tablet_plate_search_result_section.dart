import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import 'tablet_common_components.dart';

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

  Color _statusColor(CommonUiTokens tokens, PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return tokens.statusParkingRequested;
      case PlateType.parkingCompleted:
        return tokens.statusParkingCompleted;
      case PlateType.departureRequests:
        return tokens.statusDepartureRequested;
      case PlateType.departureCompleted:
        return tokens.statusSynchronized;
      case null:
        return tokens.iconSecondary;
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
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final showMultiple = results.length >= 2;
    final outerPadding = compact ? 10.0 : 14.0;
    final rowHorizontal = compact ? 12.0 : 16.0;
    final rowVertical = compact ? 12.0 : 15.0;
    final plateStyle = (compact ? text.titleMedium : text.titleLarge)?.copyWith(
      fontWeight: FontWeight.w800,
      color: tokens.textPrimary,
      height: 1.12,
    );
    final metaStyle = (compact ? text.bodySmall : text.bodyMedium)?.copyWith(
      color: tokens.textSecondary,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );

    final children = <Widget>[];
    if (showMultiple) {
      children.add(
        CommonAnimatedReveal(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              rowHorizontal,
              rowVertical,
              rowHorizontal,
              rowVertical,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: compact ? 19 : 21,
                  color: tokens.info,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '동일 뒷번호 ${results.length}건',
                    style: (compact ? text.bodyMedium : text.bodyLarge)
                        ?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      children.add(Divider(height: 1, color: tokens.borderSubtle));
    }

    for (var index = 0; index < results.length; index++) {
      final plate = results[index];
      final type = plate.typeEnum;
      final typeLabel = type?.label ?? plate.type;
      final statusColor = _statusColor(tokens, type);
      final selected = plate.isSelected;
      final meta =
          '${_formatDateTime(plate.requestTime)} · ${plate.location.isEmpty ? '위치 미지정' : plate.location}';
      children.add(
        CommonAnimatedReveal(
          key: ValueKey<String>('plate-${plate.id}-$selected'),
          delay: Duration(milliseconds: index.clamp(0, 6).toInt() * 24),
          offset: const Offset(0, 0.018),
          child: Semantics(
            button: true,
            selected: selected,
            label: '${plate.plateNumber}, $typeLabel, $meta',
            child: AnimatedContainer(
              duration: tabletCommonDuration(
                context,
                CommonUiMotion.selection,
              ),
              curve: CommonUiMotion.standard,
              decoration: BoxDecoration(
                color: selected ? tokens.surfaceSelected : tokens.transparent,
                border: Border(
                  left: BorderSide(
                    color: selected ? tokens.accent : tokens.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Material(
                color: tokens.transparent,
                child: InkWell(
                  onTap: () => onSelect(plate),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: rowHorizontal,
                      vertical: rowVertical,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _leadingIcon(type),
                          size: compact ? 21 : 24,
                          color: statusColor,
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
                              const SizedBox(height: 6),
                              Text(
                                meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedSwitcher(
                          duration: tabletCommonDuration(
                            context,
                            CommonUiMotion.selection,
                          ),
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  key: const ValueKey<String>('selected'),
                                  size: 20,
                                  color: tokens.accent,
                                )
                              : Text(
                                  typeLabel,
                                  key: ValueKey<String>('type-$typeLabel'),
                                  style: text.labelMedium?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
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
        ),
      );
      if (index != results.length - 1) {
        children.add(Divider(height: 1, color: tokens.borderSubtle));
      }
    }

    return ListView(
      padding: EdgeInsets.all(outerPadding),
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
