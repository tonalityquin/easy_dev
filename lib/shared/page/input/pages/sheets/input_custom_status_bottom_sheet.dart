import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../plate/domain/repositories/plate_repository.dart';
import '../../../../plate/domain/services/plate_status_record.dart';

String _formatDate(DateTime? value, String? raw) {
  if (value != null) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
  }
  final text = raw?.trim();
  if (text != null && text.isNotEmpty) {
    return text;
  }
  return '시간 정보 없음';
}

String _formatWon(int? value) {
  if (value == null) return '';
  return '₩${NumberFormat('#,###', 'ko_KR').format(value)}';
}

String _durationLabel(String? regularType, int? durationValue, String? periodUnit) {
  if (durationValue == null || durationValue <= 0) return '';
  final type = regularType?.trim() ?? '';
  final unit = periodUnit?.trim() ?? '';
  if (type == '주말권' && unit == '주') return '주말 $durationValue회';
  if (unit.isEmpty) return '$durationValue';
  return '$durationValue$unit';
}

String _paymentExtendedLabel(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return '';
  if (text == 'true') return '예';
  if (text == 'false') return '아니오';
  return text;
}

Widget _infoRow(BuildContext context, String label, String? value) {
  final cs = Theme.of(context).colorScheme;
  if (value == null || value.trim().isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: cs.onSurface,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 16, color: cs.onSurface),
          ),
        ),
      ],
    ),
  );
}

Future<Map<String, dynamic>?> inputCustomStatusBottomSheet(
  BuildContext context,
  String plateNumber,
  String area, {
  required String selectedBillType,
}) async {
  final bool isMonthly = selectedBillType.trim() == '정기';
  final String collectionName =
      isMonthly ? 'monthly_plate_status' : 'plate_status';

  PlateStatusRecord? data;
  try {
    final plateRepository = context.read<PlateRepository>();
    data = isMonthly
        ? await plateRepository.fetchMonthlyPlateStatus(
            plateNumber: plateNumber,
            area: area,
          )
        : await plateRepository.fetchLatestPlateStatus(
            plateNumber: plateNumber,
            area: area,
          );
  } on PlateStatusRepositoryException catch (e) {
    debugPrint('[InputCustomStatusBottomSheet] repository error: $e');
    data = null;
  } catch (e) {
    debugPrint('[InputCustomStatusBottomSheet] error: $e');
    data = null;
  } finally {
  }

  if (data == null) return null;

  final String? customStatus = data.customStatus;
  final List<String> statusList = data.statusList;
  final String? countType = data.countType;
  final String? type = data.type;
  final String? periodUnit = data.periodUnit;
  final String? regularType = data.regularType;
  final String? startDate = data.startDate;
  final String? endDate = data.endDate;
  final int? regularAmount = data.regularAmount;
  final int? regularDurationValue = data.regularDurationValue ?? data.regularDurationHours;
  final List<PlateStatusPaymentRecord> paymentHistory = data.paymentHistory;

  final formattedUpdatedAt = _formatDate(data.updatedAt, data.updatedAtRaw);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final cs2 = Theme.of(context).colorScheme;

      final bool hasWarning = customStatus != null && customStatus.isNotEmpty;

      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: cs2.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: cs2.outlineVariant.withOpacity(0.85)),
            ),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: cs2.outlineVariant.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      hasWarning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      color: hasWarning ? cs2.error : cs2.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      hasWarning ? '주의사항' : '상세 정보',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: cs2.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '데이터 출처: $collectionName',
                  style: TextStyle(fontSize: 13, color: cs2.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (hasWarning) ...[
                  Text(
                    customStatus,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs2.onSurface,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 20, color: cs2.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      '최종 수정: $formattedUpdatedAt',
                      style:
                          TextStyle(fontSize: 14, color: cs2.onSurfaceVariant),
                    ),
                  ],
                ),
                if (statusList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    '저장된 상태',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: cs2.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: statusList
                        .map(
                          (s) => Chip(
                            label: Text(
                              s,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: cs2.onSurface,
                              ),
                            ),
                            backgroundColor:
                                cs2.tertiaryContainer.withOpacity(0.55),
                            side: BorderSide(
                              color: cs2.outlineVariant.withOpacity(0.85),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  '상세 정보',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: cs2.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _infoRow(context, '정산 유형', type),
                _infoRow(context, '정산명', countType),
                _infoRow(context, '상품', regularType),
                _infoRow(context, '상품 금액', _formatWon(regularAmount)),
                _infoRow(
                  context,
                  '기간',
                  _durationLabel(regularType, regularDurationValue, periodUnit),
                ),
                _infoRow(context, '기간 단위', periodUnit),
                _infoRow(context, '시작일', startDate),
                _infoRow(context, '종료일', endDate),
                if (paymentHistory.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    '결제 내역',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: cs2.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...paymentHistory.map((payment) {
                    final paidAt =
                        _formatDate(payment.paidAt, payment.paidAtRaw);
                    final paymentAmountText = payment.paymentAmountText ?? payment.amountText;
                    final paymentAmount = int.tryParse(paymentAmountText ?? '');
                    final paymentDuration = payment.durationValue ?? payment.regularDurationValue;
                    final paymentDurationText = _durationLabel(
                      payment.regularType,
                      paymentDuration,
                      payment.periodUnit,
                    );
                    final productText = [
                      payment.regularType,
                      paymentDurationText,
                    ].where((e) => e != null && e.trim().isNotEmpty).join(' · ');
                    final rangeText = (payment.startDate != null &&
                            payment.startDate!.isNotEmpty &&
                            payment.endDate != null &&
                            payment.endDate!.isNotEmpty)
                        ? '${payment.startDate} ~ ${payment.endDate}'
                        : '';
                    final extendedText = _paymentExtendedLabel(payment.extendedText);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: cs2.outlineVariant.withOpacity(0.85),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: cs2.surfaceContainerLow,
                      ),
                      child: ListTile(
                        title: Text(
                          '결제 금액: ${paymentAmount != null ? _formatWon(paymentAmount) : paymentAmountText ?? '-'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs2.onSurface,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (paidAt.isNotEmpty)
                              Text(
                                '결제시간: $paidAt',
                                style: TextStyle(color: cs2.onSurfaceVariant),
                              ),
                            if (payment.paidBy != null &&
                                payment.paidBy!.isNotEmpty)
                              Text(
                                '결제자: ${payment.paidBy}',
                                style: TextStyle(color: cs2.onSurfaceVariant),
                              ),
                            if (extendedText.isNotEmpty)
                              Text(
                                '연장결제: $extendedText',
                                style: TextStyle(color: cs2.onSurfaceVariant),
                              ),
                            if (productText.isNotEmpty)
                              Text(
                                '상품: $productText',
                                style: TextStyle(color: cs2.onSurfaceVariant),
                              ),
                            if (rangeText.isNotEmpty)
                              Text(
                                '적용 기간: $rangeText',
                                style: TextStyle(color: cs2.onSurfaceVariant),
                              ),
                            if (payment.note != null &&
                                payment.note!.isNotEmpty)
                              Text(
                                '비고: ${payment.note}',
                                style: TextStyle(color: cs2.onSurfaceVariant),
                              ),
                          ],
                        ),
                        dense: true,
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs2.primary,
                      foregroundColor: cs2.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('확인'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  return {
    'customStatus': customStatus ?? '',
    'statusList': statusList,
    'type': type,
    'countType': countType,
    'regularType': regularType,
    'regularAmount': regularAmount,
    'regularDurationValue': regularDurationValue,
    'regularDurationHours': regularDurationValue,
    'periodUnit': periodUnit,
    'startDate': startDate,
    'endDate': endDate,
    'payment_history': paymentHistory
        .map((payment) => payment.toMap())
        .toList(growable: false),
    'collection': collectionName,
  };
}
