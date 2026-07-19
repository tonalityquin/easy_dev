import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../plate/domain/repositories/plate_repository.dart';
import '../../../../plate/domain/services/plate_status_record.dart';

String _formatDate(DateTime? value, String? raw) {
  if (value != null) return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
  final text = raw?.trim();
  return text == null || text.isEmpty ? '시간 정보 없음' : text;
}

String _formatWon(int? value) {
  if (value == null) return '';
  return '₩${NumberFormat('#,###', 'ko_KR').format(value)}';
}

String _durationLabel(
  String? regularType,
  int? durationValue,
  String? periodUnit,
) {
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
  final text = value?.trim() ?? '';
  if (text.isEmpty) return const SizedBox.shrink();
  final tokens = PromptUiTheme.of(context);
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: tokens.surfaceOverlay,
      borderRadius: BorderRadius.circular(PromptUiShapes.control),
      border: Border.all(color: tokens.borderSubtle),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
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
  final isMonthly = selectedBillType.trim() == '정기';
  final collectionName = isMonthly ? 'monthly_plate_status' : 'plate_status';

  PlateStatusRecord? data;
  try {
    final repository = context.read<PlateRepository>();
    data = isMonthly
        ? await repository.fetchMonthlyPlateStatus(
            plateNumber: plateNumber,
            area: area,
          )
        : await repository.fetchLatestPlateStatus(
            plateNumber: plateNumber,
            area: area,
          );
  } on PlateStatusRepositoryException catch (e) {
    debugPrint('[InputCustomStatusBottomSheet] repository error: $e');
  } catch (e) {
    debugPrint('[InputCustomStatusBottomSheet] error: $e');
  }

  if (data == null || !context.mounted) return null;

  final customStatus = data.customStatus;
  final statusList = data.statusList;
  final countType = data.countType;
  final type = data.type;
  final periodUnit = data.periodUnit;
  final regularType = data.regularType;
  final startDate = data.startDate;
  final endDate = data.endDate;
  final regularAmount = data.regularAmount;
  final regularDurationValue =
      data.regularDurationValue ?? data.regularDurationHours;
  final paymentHistory = data.paymentHistory;
  final formattedUpdatedAt = _formatDate(data.updatedAt, data.updatedAtRaw);
  final hasWarning = customStatus != null && customStatus.trim().isNotEmpty;

  await showPromptOverlayBottomSheet<void>(
    context: context,
    useSafeArea: false,
    builder: (sheetContext) {
      final tokens = PromptUiTheme.of(sheetContext);
      return DraggableScrollableSheet(
        initialChildSize: .68,
        minChildSize: .42,
        maxChildSize: .95,
        builder: (sheetContext, scrollController) {
          return PromptSheetScaffold(
            title: hasWarning ? '차량 주의사항' : '차량 상세 정보',
            icon: hasWarning
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            onClose: () => Navigator.of(sheetContext).pop(),
            body: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasWarning
                        ? tokens.warningContainer
                        : tokens.infoContainer,
                    borderRadius: BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: (hasWarning ? tokens.warning : tokens.info)
                          .withOpacity(.36),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasWarning
                            ? customStatus.trim()
                            : '저장된 차량 정보를 확인합니다.',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                              color: hasWarning
                                  ? tokens.onWarningContainer
                                  : tokens.onInfoContainer,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '데이터 출처: $collectionName · 최종 수정: $formattedUpdatedAt',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: hasWarning
                                  ? tokens.onWarningContainer
                                  : tokens.onInfoContainer,
                            ),
                      ),
                    ],
                  ),
                ),
                if (statusList.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    '저장된 상태',
                    style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: statusList
                        .map(
                          (value) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.accentContainer,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.pill),
                              border: Border.all(
                                color: tokens.accent.withOpacity(.36),
                              ),
                            ),
                            child: Text(
                              value,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: tokens.onAccentContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  '상세 정보',
                  style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                _infoRow(sheetContext, '정산 유형', type),
                _infoRow(sheetContext, '정산명', countType),
                _infoRow(sheetContext, '상품', regularType),
                _infoRow(sheetContext, '상품 금액', _formatWon(regularAmount)),
                _infoRow(
                  sheetContext,
                  '기간',
                  _durationLabel(
                    regularType,
                    regularDurationValue,
                    periodUnit,
                  ),
                ),
                _infoRow(sheetContext, '기간 단위', periodUnit),
                _infoRow(sheetContext, '시작일', startDate),
                _infoRow(sheetContext, '종료일', endDate),
                if (paymentHistory.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    '결제 내역',
                    style:
                        Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(height: 10),
                  ...paymentHistory.map((payment) {
                    final paidAt =
                        _formatDate(payment.paidAt, payment.paidAtRaw);
                    final paymentAmountText =
                        payment.paymentAmountText ?? payment.amountText;
                    final paymentAmount =
                        int.tryParse(paymentAmountText ?? '');
                    final paymentDuration =
                        payment.durationValue ?? payment.regularDurationValue;
                    final paymentDurationText = _durationLabel(
                      payment.regularType,
                      paymentDuration,
                      payment.periodUnit,
                    );
                    final productText = [
                      payment.regularType,
                      paymentDurationText,
                    ].where((e) => e != null && e.trim().isNotEmpty).join(' · ');
                    final rangeText = payment.startDate != null &&
                            payment.startDate!.isNotEmpty &&
                            payment.endDate != null &&
                            payment.endDate!.isNotEmpty
                        ? '${payment.startDate} ~ ${payment.endDate}'
                        : '';
                    final extendedText =
                        _paymentExtendedLabel(payment.extendedText);
                    final details = <String>[
                      if (paidAt.isNotEmpty) '결제시간: $paidAt',
                      if (payment.paidBy != null && payment.paidBy!.isNotEmpty)
                        '결제자: ${payment.paidBy}',
                      if (extendedText.isNotEmpty) '연장결제: $extendedText',
                      if (productText.isNotEmpty) '상품: $productText',
                      if (rangeText.isNotEmpty) '적용 기간: $rangeText',
                      if (payment.note != null && payment.note!.isNotEmpty)
                        '비고: ${payment.note}',
                    ];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.surfaceOverlay,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '결제 금액: ${paymentAmount != null ? _formatWon(paymentAmount) : paymentAmountText ?? '-'}',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ...details.map(
                              (line) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  line,
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: tokens.textSecondary,
                                        height: 1.35,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 14),
                PromptButton(
                  label: '확인',
                  icon: Icons.check_rounded,
                  expand: true,
                  onPressed: () => Navigator.of(sheetContext).pop(),
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
