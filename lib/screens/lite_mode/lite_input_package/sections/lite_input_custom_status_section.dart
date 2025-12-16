import 'package:flutter/material.dart';
import '../../../../utils/snackbar_helper.dart';
import '../lite_input_plate_controller.dart';

class LiteInputCustomStatusSection extends StatelessWidget {
  final LiteInputPlateController controller;
  final String? fetchedCustomStatus;
  final VoidCallback onDeleted;
  final List<String> selectedStatusNames;
  final VoidCallback onStatusCleared;
  final Key statusSectionKey;

  const LiteInputCustomStatusSection({
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
    // ✅ 정기(월정기)에서는 "자동 저장된 메모" 블록을 출력하지 않음
    final bool isMonthly = controller.selectedBillType == '정기';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('추가 상태 메모 (최대 10자)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller.customStatusController,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: '예: 뒷범퍼 손상',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),

        // ✅ 핵심 변경:
        // - 정기(isMonthly == true)면 fetchedCustomStatus가 있어도 "자동 저장된 메모" UI를 노출하지 않음
        if (!isMonthly && fetchedCustomStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '자동 저장된 메모: "$fetchedCustomStatus"',
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
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
