import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../controllers/modify_plate_controller.dart';

class ModifyBillingWorkspace extends StatelessWidget {
  const ModifyBillingWorkspace({
    super.key,
    required this.controller,
    required this.onExit,
  });

  final ModifyPlateController controller;
  final VoidCallback onExit;

  Widget _row(BuildContext context, String label, String value) {
    final tokens = CommonUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final countType = controller.selectedBillCountType?.trim().isNotEmpty == true
        ? controller.selectedBillCountType!.trim()
        : controller.selectedBill?.trim().isNotEmpty == true
            ? controller.selectedBill!.trim()
            : '-';
    final regular = controller.selectedBillType == '정기';

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '차량 정보로',
                  size: 36,
                  iconSize: 18,
                  onPressed: onExit,
                ),
                const SizedBox(width: 6),
                Icon(Icons.receipt_long_rounded,
                    color: tokens.accent, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '정산 상세',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '현재 차량에 적용된 정산 기준을 확인합니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(context, '정산 유형', controller.selectedBillType),
                  Divider(height: 1, color: tokens.borderSubtle),
                  _row(context, '적용 기준', countType),
                  const SizedBox(height: 12),
                  Text(
                    regular ? '정기' : '기본',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  if (regular) ...[
                    _row(
                      context,
                      '시간',
                      '${controller.selectedRegularDurationHours}시간',
                    ),
                    _row(
                      context,
                      '금액',
                      '${controller.selectedRegularAmount}원',
                    ),
                  ] else ...[
                    _row(
                      context,
                      '시간',
                      '${controller.selectedBasicStandard}분',
                    ),
                    _row(
                      context,
                      '금액',
                      '${controller.selectedBasicAmount}원',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '추가',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    _row(
                      context,
                      '시간',
                      '${controller.selectedAddStandard}분',
                    ),
                    _row(
                      context,
                      '금액',
                      '${controller.selectedAddAmount}원',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
