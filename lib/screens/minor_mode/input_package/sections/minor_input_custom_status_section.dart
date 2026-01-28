import 'package:flutter/material.dart';
import '../../../../utils/snackbar_helper.dart';
import '../minor_input_plate_controller.dart';

class MinorInputCustomStatusSection extends StatelessWidget {
  final MinorInputPlateController controller;
  final String? fetchedCustomStatus;
  final VoidCallback onDeleted;
  final List<String> selectedStatusNames;
  final VoidCallback onStatusCleared;
  final Key statusSectionKey;

  const MinorInputCustomStatusSection({
    super.key,
    required this.controller,
    required this.fetchedCustomStatus,
    required this.onDeleted,
    required this.selectedStatusNames,
    required this.onStatusCleared,
    required this.statusSectionKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // ✅ 정기(월정기)에서는 plate_status 기반 "자동 저장된 메모" 블록을 출력하지 않음
    final bool isMonthly = controller.selectedBillType == '정기';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '추가 상태 메모 (최대 20자)',
          style: (tt.titleSmall ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.customStatusController,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: '예: 뒷범퍼 손상',
            hintStyle: TextStyle(color: cs.onSurfaceVariant),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.6),
            ),
          ),
        ),

        // ✅ 비정기(plate_status)에서만 노출
        if (!isMonthly && fetchedCustomStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.95)),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '자동 저장된 메모: "$fetchedCustomStatus"',
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: () async {
                      try {
                        await controller.deleteCustomStatusFromFirestore(context);

                        onDeleted();
                        onStatusCleared();

                        showSuccessSnackbar(context, '자동 메모가 삭제되었습니다');
                      } catch (e) {
                        showFailedSnackbar(context, '삭제 실패. 다시 시도해주세요');
                      }
                    },
                  )
                ],
              ),
            ),
          ),
      ],
    );
  }
}
