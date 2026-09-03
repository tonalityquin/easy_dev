import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';

class MinorParkingCompletedPlateSearchResults extends StatelessWidget {
  const MinorParkingCompletedPlateSearchResults({
    super.key,
    required this.results,
    required this.onSelect,
    this.selectedPlateNumber,
  });

  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final String? selectedPlateNumber;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return OpsDockListSurface(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: results.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: tokens.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final plate = results[index];
          return _PlateManagementRow(
            plate: plate,
            selected: plate.isSelected == true ||
                selectedPlateNumber == plate.plateNumber,
            onTap: () => onSelect(plate),
          );
        },
      ),
    );
  }
}

class _PlateManagementRow extends StatelessWidget {
  const _PlateManagementRow({
    required this.plate,
    required this.selected,
    required this.onTap,
  });

  final PlateModel plate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final type = plate.typeEnum;
    final typeLabel = type?.label ?? plate.type;
    final tone = _typeTone(tokens, type);
    final location = plate.location.trim().isEmpty ? '위치 미지정' : plate.location.trim();
    final requestTime = _formatTime(plate.requestTime);
    final settlement = _settlementText(plate);
    final auxiliary = <String>[
      if ((plate.selectedBy ?? '').trim().isNotEmpty)
        '선택자 ${(plate.selectedBy ?? '').trim()}',
      if ((plate.billingType ?? '').trim().isNotEmpty)
        (plate.billingType ?? '').trim(),
      if ((plate.customStatus ?? '').trim().isNotEmpty)
        (plate.customStatus ?? '').trim(),
    ];

    return Semantics(
      button: true,
      selected: selected,
      label: '${plate.plateNumber}, $typeLabel, $location, $settlement',
      child: OpsDockSelectableRowSurface(
        selected: selected,
        selectionColor: tone,
        selectedContainer: tokens.accentContainer,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    plate.plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 5),
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    key: ValueKey<bool>(selected),
                    size: 18,
                    color: selected ? tone : tokens.iconSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '$location · $requestTime',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              settlement,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: plate.isLockedFee == true
                    ? tokens.success
                    : tokens.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (auxiliary.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                auxiliary.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _typeTone(CommonUiTokens tokens, PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return tokens.statusParkingRequested;
      case PlateType.parkingCompleted:
        return tokens.statusParkingCompleted;
      case PlateType.departureRequests:
        return tokens.statusDepartureRequested;
      case PlateType.departureCompleted:
        return tokens.textSecondary;
      default:
        return tokens.accent;
    }
  }

  String _settlementText(PlateModel plate) {
    if (plate.isLockedFee != true) return '미정산';
    final amount = plate.lockedFeeAmount;
    final payment = (plate.paymentMethod ?? '').trim();
    final lockedAt = plate.lockedAtTimeInSeconds;
    final lockedAtText = lockedAt is int
        ? DateFormat('MM.dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(lockedAt * 1000).toLocal(),
          )
        : '';
    final parts = <String>[
      amount == null
          ? '사전 정산'
          : '사전 정산 ₩${NumberFormat('#,###', 'ko_KR').format(amount)}',
      if (payment.isNotEmpty) payment,
      if (lockedAtText.isNotEmpty) lockedAtText,
    ];
    return parts.join(' · ');
  }

  String _formatTime(DateTime value) {
    return DateFormat('MM.dd HH:mm').format(value.toLocal());
  }
}
