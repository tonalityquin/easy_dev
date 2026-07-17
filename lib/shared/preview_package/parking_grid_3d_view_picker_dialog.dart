import 'dart:math';
import 'package:flutter/material.dart';

enum ParkingGridPreviewPickerItemKind { structured, text }

@immutable
class ParkingGridPreviewPickerItem {
  final String title;
  final String? subtitle;
  final ParkingGridPreviewPickerItemKind kind;

  const ParkingGridPreviewPickerItem({
    required this.title,
    this.subtitle,
    required this.kind,
  });
}

Future<int?> showParkingGrid3DViewPickerDialog({
  required BuildContext context,
  required String title,
  required List<ParkingGridPreviewPickerItem> items,
  required int selectedIndex,
}) async {
  int temp = selectedIndex.clamp(0, max(0, items.length - 1));
  String query = '';
  ParkingGridPreviewPickerItemKind? filter;

  bool match(ParkingGridPreviewPickerItem item, String q) {
    final qq = q.trim().toLowerCase();
    if (qq.isEmpty) return true;
    final title = item.title.trim().toLowerCase();
    final subtitle = (item.subtitle ?? '').trim().toLowerCase();
    return title.contains(qq) || subtitle.contains(qq);
  }

  List<int> filteredIndexes() {
    final out = <int>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (filter != null && item.kind != filter) continue;
      if (match(item, query)) out.add(i);
    }
    return out;
  }

  IconData iconFor(ParkingGridPreviewPickerItemKind kind) {
    switch (kind) {
      case ParkingGridPreviewPickerItemKind.structured:
        return Icons.account_tree_rounded;
      case ParkingGridPreviewPickerItemKind.text:
        return Icons.text_fields_rounded;
    }
  }

  String labelFor(ParkingGridPreviewPickerItemKind kind) {
    switch (kind) {
      case ParkingGridPreviewPickerItemKind.structured:
        return '구조형';
      case ParkingGridPreviewPickerItemKind.text:
        return '텍스트형';
    }
  }

  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final tt = theme.textTheme;

      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final filtered = filteredIndexes();
          final canOpen = items.isNotEmpty;
          final hasStructured = items.any(
                (e) => e.kind == ParkingGridPreviewPickerItemKind.structured,
          );
          final hasText = items.any(
                (e) => e.kind == ParkingGridPreviewPickerItemKind.text,
          );
          final showKindFilter = hasStructured && hasText;

          if (filtered.isNotEmpty && !filtered.contains(temp)) {
            temp = filtered.first;
          }

          final dialogMaxH = min(
            MediaQuery.of(ctx).size.height * 0.76,
            560.0,
          );

          final showSearch = items.length >= 8;

          Widget searchBox() {
            final border = OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
            );

            return SizedBox(
              height: 44,
              child: TextField(
                onChanged: (v) => setLocal(() => query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(

                  hintStyle: (tt.bodyMedium ?? const TextStyle()).copyWith(
                    color: cs.onSurfaceVariant.withOpacity(0.75),
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: cs.primary.withOpacity(0.85), width: 1.3),
                  ),
                ),
              ),
            );
          }

          Widget kindFilterChips() {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: filter == null,
                  label: const Text('전체'),
                  showCheckmark: false,
                  onSelected: (_) => setLocal(() => filter = null),
                ),
                if (hasStructured)
                  ChoiceChip(
                    selected: filter == ParkingGridPreviewPickerItemKind.structured,
                    label: const Text('구조형'),
                    showCheckmark: false,
                    avatar: const Icon(Icons.account_tree_rounded, size: 16),
                    onSelected: (_) => setLocal(
                          () => filter = ParkingGridPreviewPickerItemKind.structured,
                    ),
                  ),
                if (hasText)
                  ChoiceChip(
                    selected: filter == ParkingGridPreviewPickerItemKind.text,
                    label: const Text('텍스트형'),
                    showCheckmark: false,
                    avatar: const Icon(Icons.text_fields_rounded, size: 16),
                    onSelected: (_) => setLocal(
                          () => filter = ParkingGridPreviewPickerItemKind.text,
                    ),
                  ),
              ],
            );
          }

          Widget itemTile(int originalIndex) {
            final item = items[originalIndex];
            final selected = originalIndex == temp;
            final subtitle = (item.subtitle ?? '').trim();
            final badgeBg = item.kind == ParkingGridPreviewPickerItemKind.structured
                ? cs.primaryContainer.withOpacity(0.65)
                : cs.tertiaryContainer.withOpacity(0.65);
            final badgeFg = item.kind == ParkingGridPreviewPickerItemKind.structured
                ? cs.onPrimaryContainer
                : cs.onTertiaryContainer;

            final tileShape = RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: selected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.55),
              ),
            );

            final bg = selected ? cs.primaryContainer.withOpacity(0.40) : cs.surfaceContainerLowest;

            return Material(
              color: bg,
              shape: tileShape,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setLocal(() => temp = originalIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Radio<int>(
                        value: originalIndex,
                        groupValue: temp,
                        onChanged: (v) => setLocal(() => temp = v ?? temp),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  iconFor(item.kind),
                                  size: 16,
                                  color: selected ? cs.primary : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: (tt.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
                                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: badgeBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    labelFor(item.kind),
                                    style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: badgeFg,
                                    ),
                                  ),
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 18,
                        color: selected ? cs.primary : cs.onSurfaceVariant.withOpacity(0.55),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          double computeListHeightEstimate() {
            if (filtered.isEmpty) return 92.0;

            const tileH = 92.0;
            const gap = 10.0;
            const pad = 20.0;

            final est = (filtered.length * tileH) + max(0, filtered.length - 1) * gap + pad;
            return est;
          }

          final contentMaxH = dialogMaxH;
          final listPreferredH = min(max(160.0, computeListHeightEstimate()), dialogMaxH);

          Widget listBody() {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: filtered.isEmpty
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '검색 결과가 없습니다.',
                      style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                    : Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => itemTile(filtered[i]),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            titlePadding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: Row(
              children: [
                Icon(Icons.layers_rounded, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  icon: const Icon(Icons.close_rounded),
                  splashRadius: 20,
                  tooltip: '닫기',
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: contentMaxH,
                minWidth: double.maxFinite,
              ),
              child: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSearch) searchBox(),
                    if (showSearch) const SizedBox(height: 12),
                    if (showKindFilter) kindFilterChips(),
                    if (showKindFilter) const SizedBox(height: 12),
                    Flexible(
                      fit: FlexFit.loose,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 140,
                          maxHeight: listPreferredH,
                        ),
                        child: listBody(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: canOpen ? () => Navigator.of(ctx).pop(temp) : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                child: const Text('열기'),
              ),
            ],
          );
        },
      );
    },
  );
}
