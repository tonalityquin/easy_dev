import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../controllers/input_plate_controller.dart';
import '../prompt_input_ui.dart';

class InputCustomStatusSection extends StatelessWidget {
  final InputPlateController controller;
  final String? fetchedCustomStatus;
  final VoidCallback onDeleted;
  final List<String> selectedStatusNames;
  final VoidCallback onStatusCleared;
  final Key statusSectionKey;

  const InputCustomStatusSection({
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
    final tokens = PromptUiTheme.of(context);
    final isMonthly = controller.selectedBillType == '정기';
    return PromptInputSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PromptInputSectionTitle(
            icon: Icons.note_alt_rounded,
            title: '추가 상태 메모',
            subtitle: '차량 상태를 최대 20자까지 기록합니다.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller.customStatusController,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '차량 상태 메모',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
          if (!isMonthly && fetchedCustomStatus != null) ...[
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : PromptUiMotion.selection,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.infoContainer,
                border: Border.all(color: tokens.info.withOpacity(.36)),
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: tokens.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '자동 저장된 메모: "$fetchedCustomStatus"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.onInfoContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PromptIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: '자동 메모 삭제',
                    destructive: true,
                    onPressed: () async {
                      try {
                        await controller.deleteCustomStatusFromFirestore(context);
                        onDeleted();
                        onStatusCleared();
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
