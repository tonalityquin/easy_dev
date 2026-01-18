import 'package:easydev/enums/plate_type.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../../../models/plate_model.dart';

class MinorParkingCompletedPlateSearchResults extends StatelessWidget {
  // ✅ 요청 팔레트 (BlueGrey)
  static const Color _base = Color(0xFF546E7A); // BlueGrey 600
  static const Color _dark = Color(0xFF37474F); // BlueGrey 800
  static const Color _light = Color(0xFFB0BEC5); // BlueGrey 200

  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;

  const MinorParkingCompletedPlateSearchResults({
    super.key,
    required this.results,
    required this.onSelect,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat("#,###", "ko_KR");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '검색 결과',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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

            final backgroundColor = plate.isSelected ? Colors.green.shade50 : Colors.white;
            final borderColor = plate.isSelected ? Colors.green : Colors.black12;

            final labelColor = _getLabelColor(plate.typeEnum);
            final labelBgColor = _getLabelBackground(plate.typeEnum);

            final typeChip = _buildChip(
              text: typeLabel,
              fg: labelColor,
              bg: labelBgColor,
              borderColor: labelColor.withOpacity(0.55),
            );

            final settledChip = isLocked
                ? _buildChip(
              text: lockedFeeAmount != null
                  ? '사전 정산 ₩${currency.format(lockedFeeAmount)}'
                  : '사전 정산',
              fg: Colors.teal,
              bg: Colors.teal.shade50,
              borderColor: Colors.teal.withOpacity(0.55),
              icon: Icons.lock,
            )
                : _buildChip(
              text: '미정산',
              fg: Colors.grey.shade700,
              bg: Colors.grey.shade200,
              borderColor: Colors.grey.shade500.withOpacity(0.7),
              icon: Icons.lock_open,
            );

            final showDetailSection = plate.isSelected ||
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
                        color: Colors.black.withOpacity(0.03),
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
                              color: _base.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _base.withOpacity(0.25)),
                            ),
                            child: Icon(Icons.directions_car, size: 18, color: _base),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plate.plateNumber,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
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

                      // 요약 정보(요청시간 / 주차구역)
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
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (plate.isSelected)
                                const Text(
                                  '✅ 선택됨',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),

                              if (plate.selectedBy != null && plate.selectedBy!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _LabeledPill(
                                  icon: Icons.person,
                                  label: '선택자',
                                  value: plate.selectedBy!,
                                  toneColor: _dark,
                                ),
                              ],

                              if (plate.billingType != null && plate.billingType!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('과금 유형: ${plate.billingType}', style: const TextStyle(fontSize: 13)),
                              ],

                              if (plate.customStatus != null && plate.customStatus!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('커스텀 상태: ${plate.customStatus}', style: const TextStyle(fontSize: 13)),
                              ],

                              if (isLocked) ...[
                                const SizedBox(height: 10),
                                _InfoRow(
                                  icon: Icons.receipt_long,
                                  iconColor: Colors.teal,
                                  text:
                                  '정산 금액: ${lockedFeeAmount != null ? '₩${currency.format(lockedFeeAmount)}' : '-'}',
                                  strong: true,
                                ),
                                if (paymentMethod != null && paymentMethod.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _InfoRow(
                                    icon: Icons.payment,
                                    iconColor: Colors.teal,
                                    text: '결제 수단: $paymentMethod',
                                  ),
                                ],
                                if (lockedAtText != null) ...[
                                  const SizedBox(height: 4),
                                  _InfoRow(
                                    icon: Icons.lock_clock,
                                    iconColor: Colors.teal,
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

  Color _getLabelColor(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return _base;
      case PlateType.parkingCompleted:
        return Colors.green;
      case PlateType.departureRequests:
        return Colors.orange;
      case PlateType.departureCompleted:
        return Colors.grey;
      default:
        return _base;
    }
  }

  Color _getLabelBackground(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return _light.withOpacity(0.35);
      case PlateType.parkingCompleted:
        return Colors.green.shade50;
      case PlateType.departureRequests:
        return Colors.orange.shade50;
      case PlateType.departureCompleted:
        return Colors.grey.shade200;
      default:
        return _light.withOpacity(0.35);
    }
  }

  Widget _buildChip({
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
    final c = iconColor ?? Colors.grey;
    return Row(
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: Colors.black.withOpacity(strong ? 0.90 : 0.75),
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
