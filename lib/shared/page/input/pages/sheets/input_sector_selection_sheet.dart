import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../features/sector/domain/models/sector_model.dart';

class InputSectorSelectionSheet extends StatefulWidget {
  const InputSectorSelectionSheet({
    super.key,
    required this.area,
    required this.sectors,
  });

  final String area;
  final List<SectorModel> sectors;

  static Future<SectorModel?> show({
    required BuildContext context,
    required String area,
    required List<SectorModel> sectors,
  }) async {
    final sorted = List<SectorModel>.from(sectors)
      ..sort((a, b) => a.name.compareTo(b.name));
    debugPrint(
      '[InputSectorSelectionSheet] open area=${area.trim()} count=${sorted.length}',
    );
    final result = await showPromptOverlayBottomSheet<SectorModel>(
      context: context,
      useSafeArea: false,
      enableDrag: false,
      isDismissible: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .72,
        child: InputSectorSelectionSheet(
          area: area.trim(),
          sectors: sorted,
        ),
      ),
    );
    debugPrint(
      '[InputSectorSelectionSheet] close area=${area.trim()} '
      "result=${result == null ? 'cancel' : '${result.id}|${result.name}'}",
    );
    return result;
  }

  @override
  State<InputSectorSelectionSheet> createState() =>
      _InputSectorSelectionSheetState();
}

class _InputSectorSelectionSheetState
    extends State<InputSectorSelectionSheet> {
  String? _selectedId;

  SectorModel? get _selectedSector {
    final id = _selectedId;
    if (id == null) return null;
    for (final sector in widget.sectors) {
      if (sector.id == id) return sector;
    }
    return null;
  }

  Future<void> _select(SectorModel sector) async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _selectedId = sector.id);
    debugPrint(
      '[InputSectorSelectionSheet] selected '
      'area=${widget.area} id=${sector.id} name=${sector.name}',
    );
  }

  void _confirm() {
    final selected = _selectedSector;
    if (selected == null) return;
    debugPrint(
      '[InputSectorSelectionSheet] confirm '
      'area=${widget.area} id=${selected.id} name=${selected.name}',
    );
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final selected = _selectedSector;

    return PromptSheetScaffold(
      title: '어디에 왔나요?',
      icon: Icons.place_rounded,
      onClose: () => Navigator.of(context).pop(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
              curve: PromptUiMotion.standard,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected == null
                    ? tokens.surfaceOverlay
                    : tokens.accentContainer,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(
                  color: selected == null
                      ? tokens.borderSubtle
                      : tokens.accent,
                ),
              ),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : PromptUiMotion.selection,
                    child: Icon(
                      selected == null
                          ? Icons.touch_app_rounded
                          : Icons.check_circle_rounded,
                      key: ValueKey<bool>(selected != null),
                      color: selected == null
                          ? tokens.iconSecondary
                          : tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : PromptUiMotion.selection,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        selected == null
                            ? '${widget.area} 방문처를 선택해주세요.'
                            : selected.name,
                        key: ValueKey<String>(selected?.id ?? 'none'),
                        style: textTheme.titleSmall?.copyWith(
                          color: selected == null
                              ? tokens.textSecondary
                              : tokens.onAccentContainer,
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
                physics: const ClampingScrollPhysics(),
                itemCount: widget.sectors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final sector = widget.sectors[index];
                  final isSelected = sector.id == _selectedId;
                  return AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : PromptUiMotion.selection,
                    curve: PromptUiMotion.standard,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? tokens.surfaceSelected
                          : tokens.surfaceRaised,
                      borderRadius: BorderRadius.circular(PromptUiShapes.card),
                      border: Border.all(
                        color: isSelected
                            ? tokens.accent
                            : tokens.borderSubtle,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: tokens.shadow,
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : const [],
                    ),
                    child: Material(
                      color: tokens.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.card),
                        onTap: () => _select(sector),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : PromptUiMotion.selection,
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? tokens.accent
                                      : tokens.surfaceOverlay,
                                  borderRadius: BorderRadius.circular(
                                    PromptUiShapes.control,
                                  ),
                                ),
                                child: Icon(
                                  Icons.location_city_rounded,
                                  color: isSelected
                                      ? tokens.onAccent
                                      : tokens.iconSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  sector.name,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : PromptUiMotion.selection,
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  key: ValueKey<bool>(isSelected),
                                  color: isSelected
                                      ? tokens.accent
                                      : tokens.iconSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            PromptButton(
              label: '선택 완료',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              haptic: PromptHaptic.medium,
              onPressed: selected == null ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
