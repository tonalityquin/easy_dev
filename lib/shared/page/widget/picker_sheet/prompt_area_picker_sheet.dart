import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../features/headquarter/application/area/area_master_cache.dart';

Future<void> showPromptAreaPickerSheet({
  required BuildContext context,
  required Future<AreaMasterSelectableData> future,
  required String currentArea,
  required Future<void> Function(
    String selected,
    AreaMasterSelectableData data,
  ) onConfirm,
}) async {
  await showPromptOverlayBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.94,
        child: PromptSheetScaffold(
          title: '지역 선택',
          icon: Icons.location_on_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          body: _PromptAreaPickerBody(
            future: future,
            currentArea: currentArea,
            onConfirm: onConfirm,
          ),
        ),
      );
    },
  );
}

class _PromptAreaPickerBody extends StatelessWidget {
  const _PromptAreaPickerBody({
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
          return const _PromptAreaPickerState(
            icon: Icons.sync_rounded,
            title: '지역 목록을 불러오는 중입니다.',
            loading: true,
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const _PromptAreaPickerState(
            icon: Icons.error_outline_rounded,
            title: '지역 목록을 불러오지 못했습니다.',
            description: '잠시 후 다시 시도해 주세요.',
          );
        }

        final data = snapshot.data!;
        if (!data.hasCache) {
          return _PromptAreaPickerState(
            icon: Icons.cloud_download_outlined,
            title: '지역 마스터가 없습니다.',
            description: '업무 메뉴에서 지역 마스터 갱신을 먼저 실행하세요.',
            action: PromptButton(
              label: '닫기',
              icon: Icons.close_rounded,
              variant: PromptButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          );
        }

        if (data.selectableAreas.isEmpty) {
          return _PromptAreaPickerState(
            icon: Icons.location_off_rounded,
            title: '선택 가능한 지역이 없습니다.',
            description: '현재 모드에서 사용할 수 있는 지역을 확인하세요.',
            action: PromptButton(
              label: '닫기',
              icon: Icons.close_rounded,
              variant: PromptButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          );
        }

        final initial = data.selectableAreas.contains(currentArea.trim())
            ? currentArea.trim()
            : data.selectableAreas.first;

        return _PromptAreaPickerSelection(
          data: data,
          initialSelected: initial,
          onConfirm: onConfirm,
        );
      },
    );
  }
}

class _PromptAreaPickerState extends StatelessWidget {
  const _PromptAreaPickerState({
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
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: PromptAnimatedReveal(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
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
                      borderRadius: BorderRadius.circular(PromptUiShapes.card),
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

class _PromptAreaPickerSelection extends StatefulWidget {
  const _PromptAreaPickerSelection({
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
  State<_PromptAreaPickerSelection> createState() =>
      _PromptAreaPickerSelectionState();
}

class _PromptAreaPickerSelectionState
    extends State<_PromptAreaPickerSelection> {
  late String _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected;
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onConfirm(_selected, widget.data);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final initialIndex = widget.data.selectableAreas.indexOf(_selected);
    final headquarter = widget.data.isHeadquarterByName[_selected] == true;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        children: [
          PromptAnimatedReveal(
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
              curve: PromptUiMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(
                    headquarter
                        ? Icons.apartment_rounded
                        : Icons.location_city_rounded,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration:
                          reduceMotion ? Duration.zero : PromptUiMotion.selection,
                      child: Text(
                        _selected,
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: headquarter
                          ? tokens.infoContainer
                          : tokens.accentContainer,
                      borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                    ),
                    child: Text(
                      headquarter ? '본사' : '지사',
                      style: text.labelSmall?.copyWith(
                        color: headquarter
                            ? tokens.onInfoContainer
                            : tokens.onAccentContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  primaryColor: tokens.accent,
                  brightness: tokens.brightness,
                  textTheme: CupertinoTextThemeData(
                    pickerTextStyle: text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: initialIndex < 0 ? 0 : initialIndex,
                  ),
                  itemExtent: 50,
                  magnification: 1.06,
                  useMagnifier: true,
                  squeeze: 1.08,
                  selectionOverlay: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceSelected,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(color: tokens.accent),
                    ),
                  ),
                  onSelectedItemChanged: (index) {
                    setState(() {
                      _selected = widget.data.selectableAreas[index];
                    });
                  },
                  children: widget.data.selectableAreas
                      .map(
                        (area) => Center(
                          child: Text(
                            area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PromptButton(
            label: '선택 적용',
            icon: Icons.check_rounded,
            expand: true,
            loading: _submitting,
            haptic: PromptHaptic.selection,
            onPressed: _submitting ? null : _confirm,
          ),
        ],
      ),
    );
  }
}
