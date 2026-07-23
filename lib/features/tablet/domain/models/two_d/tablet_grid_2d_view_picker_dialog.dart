import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../pages/widgets/tablet_prompt_components.dart';

enum ParkingGridPreviewPickerItemKind { structured, text }

@immutable
class ParkingGridPreviewPickerItem {
  const ParkingGridPreviewPickerItem({
    required this.title,
    this.subtitle,
    required this.kind,
  });

  final String title;
  final String? subtitle;
  final ParkingGridPreviewPickerItemKind kind;
}

Future<int?> showTabletGrid2DViewPickerDialog({
  required BuildContext context,
  required String title,
  required List<ParkingGridPreviewPickerItem> items,
  required int selectedIndex,
}) async {
  var selected = selectedIndex.clamp(0, max(0, items.length - 1));
  var query = '';
  ParkingGridPreviewPickerItemKind? filter;

  bool matches(ParkingGridPreviewPickerItem item) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return item.title.toLowerCase().contains(normalized) ||
        (item.subtitle ?? '').toLowerCase().contains(normalized);
  }

  List<int> visibleIndexes() {
    return List<int>.generate(items.length, (index) => index)
        .where((index) {
      final item = items[index];
      return (filter == null || item.kind == filter) && matches(item);
    }).toList(growable: false);
  }

  String kindLabel(ParkingGridPreviewPickerItemKind kind) {
    return kind == ParkingGridPreviewPickerItemKind.structured
        ? '구조형'
        : '텍스트형';
  }

  IconData kindIcon(ParkingGridPreviewPickerItemKind kind) {
    return kind == ParkingGridPreviewPickerItemKind.structured
        ? Icons.account_tree_rounded
        : Icons.text_fields_rounded;
  }

  return showPromptOverlayDialog<int>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          final tokens = PromptUiTheme.of(context);
          final text = Theme.of(context).textTheme;
          final visible = visibleIndexes();
          final hasStructured = items.any(
            (item) =>
                item.kind == ParkingGridPreviewPickerItemKind.structured,
          );
          final hasText = items.any(
            (item) => item.kind == ParkingGridPreviewPickerItemKind.text,
          );
          final showFilters = hasStructured && hasText;
          final showSearch = items.length >= 8;
          if (visible.isNotEmpty && !visible.contains(selected)) {
            selected = visible.first;
          }
          final maxHeight = min(
            MediaQuery.sizeOf(context).height * 0.82,
            640.0,
          );

          Widget filterChip({
            required String label,
            required bool active,
            required VoidCallback onPressed,
            IconData? icon,
          }) {
            return Semantics(
              button: true,
              selected: active,
              label: label,
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Text(label),
                  ],
                ),
                selected: active,
                showCheckmark: false,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setLocalState(onPressed);
                },
              ),
            );
          }

          Widget itemTile(int index) {
            final item = items[index];
            final active = index == selected;
            final subtitle = (item.subtitle ?? '').trim();
            final kindTone =
                item.kind == ParkingGridPreviewPickerItemKind.structured
                    ? tokens.info
                    : tokens.warning;
            return PromptAnimatedReveal(
              key: ValueKey<String>('picker-item-$index-${filter?.name}-$query'),
              duration: PromptUiMotion.component,
              child: Semantics(
                button: true,
                selected: active,
                label: subtitle.isEmpty
                    ? '${item.title}, ${kindLabel(item.kind)}'
                    : '${item.title}, ${kindLabel(item.kind)}, $subtitle',
                child: AnimatedContainer(
                  duration: tabletPromptDuration(
                    context,
                    PromptUiMotion.selection,
                  ),
                  curve: PromptUiMotion.standard,
                  decoration: BoxDecoration(
                    color: active
                        ? tokens.surfaceSelected
                        : tokens.surfaceRaised,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: active ? tokens.accent : tokens.borderSubtle,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Material(
                    color: tokens.transparent,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setLocalState(() => selected = index);
                      },
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            AnimatedContainer(
                              duration: tabletPromptDuration(
                                context,
                                PromptUiMotion.selection,
                              ),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: active
                                    ? tokens.accentContainer
                                    : tokens.surfaceOverlay,
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                                border: Border.all(
                                  color: active
                                      ? tokens.accent
                                      : tokens.borderSubtle,
                                ),
                              ),
                              child: Icon(
                                kindIcon(item.kind),
                                color: active
                                    ? tokens.onAccentContainer
                                    : kindTone,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyLarge?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: <Widget>[
                                      TabletPromptStatusPill(
                                        label: kindLabel(item.kind),
                                        icon: kindIcon(item.kind),
                                        tone: kindTone,
                                        selected: active,
                                      ),
                                      if (subtitle.isNotEmpty)
                                        Text(
                                          subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.bodySmall?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedSwitcher(
                              duration: tabletPromptDuration(
                                context,
                                PromptUiMotion.selection,
                              ),
                              child: active
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      key: const ValueKey<String>('active'),
                                      color: tokens.accent,
                                    )
                                  : Icon(
                                      Icons.circle_outlined,
                                      key: const ValueKey<String>('inactive'),
                                      color: tokens.iconDisabled,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return PromptDialogFrame(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: maxHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.control),
                          border: Border.all(
                            color: tokens.accent.withOpacity(
                              tokens.isDark ? 0.56 : 0.38,
                            ),
                          ),
                        ),
                        child: Icon(
                          Icons.layers_rounded,
                          color: tokens.onAccentContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PromptIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).pop(),
                        haptic: PromptHaptic.selection,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (showSearch) ...<Widget>[
                    TextField(
                      onChanged: (value) =>
                          setLocalState(() => query = value),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: '구역 검색',
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showFilters) ...<Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        filterChip(
                          label: '전체',
                          active: filter == null,
                          onPressed: () => filter = null,
                        ),
                        if (hasStructured)
                          filterChip(
                            label: '구조형',
                            icon: Icons.account_tree_rounded,
                            active: filter ==
                                ParkingGridPreviewPickerItemKind.structured,
                            onPressed: () => filter =
                                ParkingGridPreviewPickerItemKind.structured,
                          ),
                        if (hasText)
                          filterChip(
                            label: '텍스트형',
                            icon: Icons.text_fields_rounded,
                            active: filter ==
                                ParkingGridPreviewPickerItemKind.text,
                            onPressed: () => filter =
                                ParkingGridPreviewPickerItemKind.text,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Flexible(
                    child: TabletPromptAnimatedSwap(
                      child: visible.isEmpty
                          ? const TabletPromptEmptyState(
                              key: ValueKey<String>('empty-picker'),
                              title: '검색 결과가 없습니다',
                              message: '검색어 또는 유형 필터를 변경하세요.',
                              icon: Icons.search_off_rounded,
                            )
                          : Scrollbar(
                              key: ValueKey<String>(
                                'picker-list-${filter?.name}-$query',
                              ),
                              thumbVisibility: true,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, index) =>
                                    itemTile(visible[index]),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      PromptButton(
                        label: '취소',
                        variant: PromptButtonVariant.tertiary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      PromptButton(
                        label: '열기',
                        icon: Icons.open_in_new_rounded,
                        onPressed: items.isEmpty
                            ? null
                            : () => Navigator.of(context).pop(selected),
                        haptic: PromptHaptic.light,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
