import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../controllers/input_plate_controller.dart';
import '../common_input_ui.dart';

class InputCustomStatusSection extends StatelessWidget {
  const InputCustomStatusSection({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onStoredStatusDeleted,
  });

  final InputPlateController controller;
  final VoidCallback onChanged;
  final VoidCallback onStoredStatusDeleted;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final fetchedMemo = controller.fetchedCustomStatus?.trim() ?? '';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final lookupInProgress = controller.statusLookupInProgress;

    return CommonInputSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CommonInputSectionTitle(
            icon: Icons.note_alt_rounded,
            title: '상태 메모',
            subtitle: '차량별 자유형 상태 메모를 관리합니다.',
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: lookupInProgress
                ? Container(
                    key: const ValueKey<String>('memo-lookup-loading'),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.infoContainer,
                      borderRadius: BorderRadius.circular(
                        CommonUiShapes.control,
                      ),
                      border: Border.all(
                        color: tokens.info.withOpacity(.32),
                      ),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('기존 상태 메모를 확인하고 있습니다.'),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('memo-lookup-complete'),
                  ),
          ),
          AnimatedOpacity(
            opacity: lookupInProgress ? .55 : 1,
            duration: duration,
            child: IgnorePointer(
              ignoring: lookupInProgress,
              child: TextField(
                enabled: !lookupInProgress,
                controller: controller.customStatusController,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '차량 상태 메모',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
                onChanged: (_) {
                  controller.markStatusDraftEdited();
                  onChanged();
                },
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: fetchedMemo.isNotEmpty
                ? Container(
                    key: ValueKey<String>(fetchedMemo),
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.infoContainer,
                      border: Border.all(
                        color: tokens.info.withOpacity(.36),
                      ),
                      borderRadius: BorderRadius.circular(
                        CommonUiShapes.control,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          color: tokens.info,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '불러온 상태 메모',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: tokens.onInfoContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                fetchedMemo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: tokens.onInfoContainer,
                                      height: 1.35,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        CommonIconButton(
                          icon: Icons.delete_outline_rounded,
                          tooltip: '저장된 상태 메모 삭제',
                          destructive: true,
                          onPressed: lookupInProgress
                              ? null
                              : () async {
                                  try {
                                    await controller
                                        .deleteCustomStatusFromFirestore(
                                      context,
                                    );
                                    onStoredStatusDeleted();
                                  } catch (_) {}
                                },
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('no-loaded-status'),
                  ),
          ),
        ],
      ),
    );
  }
}
