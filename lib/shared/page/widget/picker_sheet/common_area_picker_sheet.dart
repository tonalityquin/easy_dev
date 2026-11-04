import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/headquarter/application/area/area_master_cache.dart';
import '../../../../app/models/account_role_diagnostics.dart';
import 'area_denied_bubble.dart';

Future<void> showCommonAreaPickerSheet({
  required BuildContext context,
  required Future<AreaMasterSelectableData> future,
  required String currentArea,
  required Future<void> Function(
    String selected,
    AreaMasterSelectableData data,
  ) onConfirm,
}) async {
  await showCommonOverlayBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.94,
        child: CommonSheetScaffold(
          title: '지역 선택',
          icon: Icons.location_on_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          body: _CommonAreaPickerBody(
            future: future,
            currentArea: currentArea,
            onConfirm: onConfirm,
          ),
        ),
      );
    },
  );
}

class _CommonAreaPickerBody extends StatelessWidget {
  const _CommonAreaPickerBody({
    required this.future,
    required this.currentArea,
    required this.onConfirm,
  });

  final Future<AreaMasterSelectableData> future;
  final String currentArea;
  final Future<void> Function(
    String selected,
    AreaMasterSelectableData data,
  ) onConfirm;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AreaMasterSelectableData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _CommonAreaPickerState(
            icon: Icons.sync_rounded,
            title: '지역 목록을 불러오는 중입니다.',
            loading: true,
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const _CommonAreaPickerState(
            icon: Icons.error_outline_rounded,
            title: '지역 목록을 불러오지 못했습니다.',
            description: '잠시 후 다시 시도해 주세요.',
          );
        }

        final data = snapshot.data!;
        if (!data.hasCache) {
          return _CommonAreaPickerState(
            icon: Icons.cloud_download_outlined,
            title: '지역 마스터가 없습니다.',
            description: '업무 메뉴에서 지역 마스터 갱신을 먼저 실행하세요.',
            action: CommonButton(
              label: '닫기',
              icon: Icons.close_rounded,
              variant: CommonButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          );
        }

        if (data.visibleAreas.isEmpty) {
          return _CommonAreaPickerState(
            icon: Icons.location_off_rounded,
            title: '선택 가능한 지역이 없습니다.',
            description: '현재 모드에서 사용할 수 있는 지역을 확인하세요.',
            action: CommonButton(
              label: '닫기',
              icon: Icons.close_rounded,
              variant: CommonButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          );
        }

        final initial = data.selectableAreas.contains(currentArea.trim())
            ? currentArea.trim()
            : data.selectableAreas.isEmpty ? '' : data.selectableAreas.first;

        return _CommonAreaPickerSelection(
          data: data,
          initialSelected: initial,
          onConfirm: onConfirm,
        );
      },
    );
  }
}

class _CommonAreaPickerState extends StatelessWidget {
  const _CommonAreaPickerState({
    required this.icon,
    required this.title,
    this.description,
    this.loading = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: CommonAnimatedReveal(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(CommonUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(CommonUiShapes.card),
                    ),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(17),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: tokens.accent,
                            ),
                          )
                        : Icon(icon, color: tokens.onAccentContainer, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      description!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: 18),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommonAreaPickerSelection extends StatefulWidget {
  const _CommonAreaPickerSelection({
    required this.data,
    required this.initialSelected,
    required this.onConfirm,
  });

  final AreaMasterSelectableData data;
  final String initialSelected;
  final Future<void> Function(
    String selected,
    AreaMasterSelectableData data,
  ) onConfirm;

  @override
  State<_CommonAreaPickerSelection> createState() =>
      _CommonAreaPickerSelectionState();
}

class _CommonAreaPickerSelectionState
    extends State<_CommonAreaPickerSelection> {
  late String _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected;
  }

  Future<void> _confirm() async {
    if (_submitting || !widget.data.selectableAreas.contains(_selected)) return;
    setState(() => _submitting = true);
    try {
      await widget.onConfirm(_selected, widget.data);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        children: [
          AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(Icons.location_city_rounded, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: Text(
                      _selected.isEmpty ? '업무 지역' : _selected,
                      key: ValueKey<String>(_selected),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: widget.data.visibleAreas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final area = widget.data.visibleAreas[index];
                final allowed = widget.data.selectableAreas.contains(area);
                final selected = _selected == area && allowed;
                return AreaDeniedBubble(
                  child: Builder(
                    builder: (bubbleContext) => Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (!allowed) {
                        final reason = widget.data.rejectionReason(area);
                        AccountRoleDiagnostics.record(
                          'picker_area_denied modeSupported=${widget.data.modeSupportedAreas.contains(area)}',
                        );
                        AreaDeniedBubble.show(bubbleContext, reason);
                        return;
                      }
                      AreaDeniedBubble.dismissAll();
                      AccountRoleDiagnostics.record('picker_area_allowed');
                      setState(() {
                        _selected = area;
                      });
                    },
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    child: AnimatedOpacity(
                      duration: duration,
                      opacity: allowed ? 1 : 0.44,
                      child: AnimatedContainer(
                        duration: duration,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected ? tokens.surfaceSelected : tokens.surface,
                          borderRadius: BorderRadius.circular(CommonUiShapes.control),
                          border: Border.all(
                            color: selected ? tokens.accent : tokens.borderSubtle,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              allowed ? Icons.location_on_rounded : Icons.lock_outline_rounded,
                              color: allowed ? tokens.accent : tokens.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                area,
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check_circle_rounded, color: tokens.accent)
                            else if (!allowed)
                              Icon(Icons.lock_rounded, color: tokens.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          CommonButton(
            label: '선택 적용',
            icon: Icons.check_rounded,
            expand: true,
            loading: _submitting,
            haptic: CommonHaptic.selection,
            onPressed: _submitting ||
                    !widget.data.selectableAreas.contains(_selected)
                ? null
                : _confirm,
          ),
        ],
      ),
    );
  }
}
