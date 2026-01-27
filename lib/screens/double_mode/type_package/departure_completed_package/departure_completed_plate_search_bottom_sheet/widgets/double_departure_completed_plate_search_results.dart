import 'package:easydev/enums/plate_type.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../../../models/plate_model.dart';

class DoubleDepartureCompletedPlateSearchResults extends StatelessWidget {
  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;

  const DoubleDepartureCompletedPlateSearchResults({
    super.key,
    required this.results,
    required this.onSelect,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat("#,###", "ko_KR");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '검색 결과',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final plate = results[index];
            final typeLabel = plate.typeEnum?.label ?? plate.type;
            final formattedTime = _formatTime(plate.requestTime);

            final isLocked = plate.isLockedFee == true;
            final lockedFeeAmount = plate.lockedFeeAmount;
            final paymentMethod = plate.paymentMethod;
            final lockedAtSec = plate.lockedAtTimeInSeconds;

            final locationText = plate.location.trim().isEmpty ? '-' : plate.location.trim();

            final selected = plate.isSelected == true;
            final backgroundColor = selected ? cs.tertiaryContainer.withOpacity(0.45) : cs.surface;
            final borderColor = selected ? cs.tertiary.withOpacity(0.75) : cs.outlineVariant.withOpacity(0.85);

            final (typeFg, typeBg) = _typeChipColors(cs, plate.typeEnum);

            final typeChip = _buildChip(
              cs: cs,
              text: typeLabel,
              fg: typeFg,
              bg: typeBg,
              borderColor: typeFg.withOpacity(0.55),
            );

            final settledChip = isLocked
                ? _buildChip(
              cs: cs,
              text: lockedFeeAmount != null
                  ? '사전 정산 ₩${currency.format(lockedFeeAmount)}'
                  : '사전 정산',
              fg: cs.tertiary,
              bg: cs.tertiaryContainer.withOpacity(0.55),
              borderColor: cs.tertiary.withOpacity(0.55),
              icon: Icons.lock,
            )
                : _buildChip(
              cs: cs,
              text: '미정산',
              fg: cs.onSurfaceVariant,
              bg: cs.surfaceContainerLow,
              borderColor: cs.outlineVariant.withOpacity(0.85),
              icon: Icons.lock_open,
            );

            final showDetailSection = selected ||
                (plate.selectedBy?.isNotEmpty ?? false) ||
                (plate.billingType?.isNotEmpty ?? false) ||
                (plate.customStatus?.isNotEmpty ?? false) ||
                isLocked;

            final lockedAtText = (lockedAtSec is int)
                ? _formatTime(DateTime.fromMillisecondsSinceEpoch(lockedAtSec * 1000).toLocal())
                : null;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(plate),
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 상단: 번호 + 칩
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.primary.withOpacity(0.25)),
                            ),
                            child: Icon(Icons.directions_car, size: 18, color: cs.primary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plate.plateNumber,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: cs.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [typeChip, settledChip],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      _InfoRow(
                        icon: Icons.access_time,
                        text: '요청 시간: $formattedTime',
                      ),
                      const SizedBox(height: 6),
                      _InfoRow(
                        icon: Icons.location_on,
                        text: '주차 구역: $locationText',
                      ),

                      if (showDetailSection) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (selected)
                                Text(
                                  '✅ 선택됨',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.tertiary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),

                              if (plate.selectedBy != null && plate.selectedBy!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _LabeledPill(
                                  icon: Icons.person,
                                  label: '선택자',
                                  value: plate.selectedBy!,
                                  toneColor: cs.onSurface,
                                ),
                              ],

                              if (plate.billingType != null && plate.billingType!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '과금 유형: ${plate.billingType}',
                                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                                ),
                              ],

                              if (plate.customStatus != null && plate.customStatus!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '커스텀 상태: ${plate.customStatus}',
                                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                                ),
                              ],

                              if (isLocked) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.receipt_long,
                                  iconColor: cs.tertiary,
                                  text: '정산 금액: ${lockedFeeAmount != null ? '₩${currency.format(lockedFeeAmount)}' : '-'}',
                                  strong: true,
                                ),
                                if (paymentMethod != null && paymentMethod.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _InfoRow(
                                    icon: Icons.payment,
                                    iconColor: cs.tertiary,
                                    text: '결제 수단: $paymentMethod',
                                  ),
                                ],
                                if (lockedAtText != null) ...[
                                  const SizedBox(height: 4),
                                  _InfoRow(
                                    icon: Icons.lock_clock,
                                    iconColor: cs.tertiary,
                                    text: '정산 시각: $lockedAtText',
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  (Color fg, Color bg) _typeChipColors(ColorScheme cs, PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return (cs.primary, cs.primary.withOpacity(0.10));
      case PlateType.parkingCompleted:
        return (cs.tertiary, cs.tertiaryContainer.withOpacity(0.55));
      case PlateType.departureRequests:
        return (cs.error, cs.errorContainer.withOpacity(0.55));
      case PlateType.departureCompleted:
        return (cs.onSurfaceVariant, cs.surfaceContainerLow);
      default:
        return (cs.primary, cs.primary.withOpacity(0.10));
    }
  }

  Widget _buildChip({
    required ColorScheme cs,
    required String text,
    required Color fg,
    required Color bg,
    required Color borderColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;
  final bool strong;

  const _InfoRow({
    required this.icon,
    required this.text,
    this.iconColor,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = iconColor ?? cs.onSurfaceVariant;

    return Row(
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              color: strong ? cs.onSurface : cs.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LabeledPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color toneColor;

  const _LabeledPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.toneColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: toneColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: toneColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: toneColor),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: toneColor),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: toneColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
