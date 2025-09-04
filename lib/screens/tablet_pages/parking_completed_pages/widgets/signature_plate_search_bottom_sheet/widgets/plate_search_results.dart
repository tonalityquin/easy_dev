import 'package:easydev/enums/plate_type.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 추가: 통화 포맷을 위해
import '../../../../../../models/plate_model.dart';

class PlateSearchResults extends StatelessWidget {
  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;

  const PlateSearchResults({
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final plate = results[index];
            final typeLabel = plate.typeEnum?.label ?? plate.type;
            final formattedTime = _formatTime(plate.requestTime);

            final isLocked = plate.isLockedFee == true;
            final lockedFeeAmount = plate.lockedFeeAmount; // int?로 가정
            final paymentMethod = plate.paymentMethod; // String?로 가정
            final lockedAtSec = plate.lockedAtTimeInSeconds; // int? (UTC seconds)

            final locationText = plate.location.trim().isEmpty ? '-' : plate.location.trim();

            final backgroundColor = plate.isSelected ? Colors.green.shade50 : Colors.white;
            final borderColor = plate.isSelected ? Colors.green : Colors.grey.shade300;

            final labelColor = _getLabelColor(plate.typeEnum);
            final labelBgColor = _getLabelBackground(plate.typeEnum);

            // 상단 칩(타입/정산) — location 칩 제거
            final typeChip = _buildChip(
              text: typeLabel,
              fg: labelColor,
              bg: labelBgColor,
              borderColor: labelColor,
            );

            final settledChip = isLocked
                ? _buildChip(
              text: lockedFeeAmount != null
                  ? '사전 정산 ₩${currency.format(lockedFeeAmount)}'
                  : '사전 정산',
              fg: Colors.teal,
              bg: Colors.teal.shade50,
              borderColor: Colors.teal,
              icon: Icons.lock,
            )
                : _buildChip(
              text: '미정산',
              fg: Colors.grey.shade700,
              bg: Colors.grey.shade200,
              borderColor: Colors.grey.shade500,
              icon: Icons.lock_open,
            );

            // 상세 정보(선택/선택자/과금유형/커스텀상태/정산정보)
            final showDetailSection = plate.isSelected ||
                (plate.selectedBy?.isNotEmpty ?? false) ||
                (plate.billingType?.isNotEmpty ?? false) ||
                (plate.customStatus?.isNotEmpty ?? false) ||
                isLocked; // 잠금 상태면 무조건 상세 영역 노출

            final lockedAtText = (lockedAtSec is int)
                ? _formatTime(DateTime.fromMillisecondsSinceEpoch(lockedAtSec * 1000).toLocal())
                : null;

            return GestureDetector(
              onTap: () => onSelect(plate),
              child: Card(
                elevation: 1,
                color: backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor),
                ),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 상단: 번호 + 칩들(타입/정산)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.directions_car, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              plate.plateNumber,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                typeChip,
                                settledChip,
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 요청 시간 (기존 형식)
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            '요청 시간: $formattedTime',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // ✅ 주차 구역 — 요청 시간과 동일한 형식(Row + grey icon + Text)
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '주차 구역: $locationText',
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      if (showDetailSection)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (plate.isSelected)
                                const Text(
                                  '✅ 선택됨',
                                  style: TextStyle(fontSize: 13, color: Colors.green),
                                ),
                              if (plate.selectedBy != null && plate.selectedBy!.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.person, size: 16, color: Colors.deepPurple),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.deepPurple),
                                      ),
                                      child: Text(
                                        '선택자: ${plate.selectedBy}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.deepPurple,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (plate.billingType != null && plate.billingType!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '과금 유형: ${plate.billingType}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                              if (plate.customStatus != null && plate.customStatus!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '커스텀 상태: ${plate.customStatus}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],

                              // === 정산 상세 ===
                              if (isLocked) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.receipt_long, size: 16, color: Colors.teal),
                                    const SizedBox(width: 6),
                                    Text(
                                      '정산 금액: ${lockedFeeAmount != null ? '₩${currency.format(lockedFeeAmount)}' : '-'}',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                if (paymentMethod != null && paymentMethod.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.payment, size: 16, color: Colors.teal),
                                        const SizedBox(width: 6),
                                        Text('결제 수단: $paymentMethod', style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                if (lockedAtText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.lock_clock, size: 16, color: Colors.teal),
                                        const SizedBox(width: 6),
                                        Text('정산 시각: $lockedAtText', style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
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
        return Colors.blueAccent;
      case PlateType.parkingCompleted:
        return Colors.green;
      case PlateType.departureRequests:
        return Colors.orange;
      case PlateType.departureCompleted:
        return Colors.grey;
      default:
        return Colors.blueAccent;
    }
  }

  Color _getLabelBackground(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return Colors.blue.shade50;
      case PlateType.parkingCompleted:
        return Colors.green.shade50;
      case PlateType.departureRequests:
        return Colors.orange.shade50;
      case PlateType.departureCompleted:
        return Colors.grey.shade200;
      default:
        return Colors.blue.shade50;
    }
  }

  // 공통 칩 위젯 헬퍼
  Widget _buildChip({
    required String text,
    required Color fg,
    required Color bg,
    required Color borderColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
