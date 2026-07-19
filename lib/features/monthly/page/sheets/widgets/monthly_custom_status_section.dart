import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../controllers/monthly_plate_controller.dart';
import '../../widgets/monthly_prompt_ui.dart';

class MonthlyCustomStatusSection extends StatefulWidget {
  const MonthlyCustomStatusSection({
    super.key,
    required this.controller,
    required this.fetchedCustomStatus,
    required this.onDeleted,
    required this.onStatusCleared,
    required this.statusSectionKey,
  });

  final MonthlyPlateController controller;
  final String? fetchedCustomStatus;
  final VoidCallback onDeleted;
  final VoidCallback onStatusCleared;
  final Key statusSectionKey;

  @override
  State<MonthlyCustomStatusSection> createState() =>
      _MonthlyCustomStatusSectionState();
}

class _MonthlyCustomStatusSectionState
    extends State<MonthlyCustomStatusSection> {
  bool _deleting = false;

  Future<void> _deleteFetchedStatus() async {
    FocusScope.of(context).unfocus();
    setState(() => _deleting = true);
    try {
      await widget.controller.deleteCustomStatusFromFirestore(context);
      if (!mounted) return;
      widget.onDeleted();
      widget.onStatusCleared();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return KeyedSubtree(
      key: widget.statusSectionKey,
      child: MonthlyPromptSection(
        title: '운영 메모',
        subtitle: '현장 인수인계에 필요한 짧은 상태 메모를 기록합니다.',
        icon: Icons.sticky_note_2_outlined,
        delay: const Duration(milliseconds: 165),
        trailing: const MonthlyPromptBadge(
          label: '20자',
          icon: Icons.text_fields_rounded,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.controller.customStatusController,
              maxLength: 20,
              maxLengthEnforcement:
                  MaxLengthEnforcement.truncateAfterCompositionEnds,
              style: textTheme.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              decoration: monthlyPromptInputDecoration(
                context,
                label: '상태 메모',
                prefixIcon: Icon(
                  Icons.edit_note_rounded,
                  color: tokens.iconSecondary,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
              switchInCurve: PromptUiMotion.enter,
              switchOutCurve: PromptUiMotion.exit,
              child: widget.fetchedCustomStatus == null
                  ? const SizedBox.shrink(
                      key: ValueKey<String>('no-fetched-status'),
                    )
                  : Container(
                      key: const ValueKey<String>('fetched-status'),
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.warningContainer,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                        border: Border.all(
                          color: tokens.warning.withOpacity(0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: tokens.onWarningContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '자동 저장된 메모: ${widget.fetchedCustomStatus}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: tokens.onWarningContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PromptIconButton(
                            icon: Icons.delete_outline_rounded,
                            tooltip: '자동 메모 삭제',
                            destructive: true,
                            loading: _deleting,
                            haptic: PromptHaptic.heavy,
                            onPressed: _deleting ? null : _deleteFetchedStatus,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
