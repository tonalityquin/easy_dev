import 'package:flutter/material.dart';

class PersonalStickyNoticeBar extends StatelessWidget {
  final List<String> plates;
  final Set<String> selectedPlates;
  final void Function(String plateNumber) onToggleSelect;
  final void Function(String plateNumber) onRemove;

  const PersonalStickyNoticeBar({
    super.key,
    required this.plates,
    required this.selectedPlates,
    required this.onToggleSelect,
    required this.onRemove,
  });

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  @override
  Widget build(BuildContext context) {
    final hasChips = plates.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final dark = cs.brightness == Brightness.dark;
    final barBg = _tintOnSurface(cs, opacity: dark ? 0.14 : 0.06);
    final barBorder = cs.primary.withOpacity(dark ? 0.35 : 0.20);

    final infoIconColor = hasChips ? cs.tertiary : cs.primary;
    final titleColor = cs.onSurface;
    final bodyColor = cs.onSurface.withOpacity(.85);

    return Material(
      color: barBg,
      borderOnForeground: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: barBorder)),
        ),
        child: Row(
          children: [
            Icon(
              hasChips ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: infoIconColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: hasChips
                  ? Row(
                      children: [
                        Text(
                          '출차 완료:',
                          style: (text.bodySmall ?? const TextStyle()).copyWith(
                            fontSize: 13,
                            color: titleColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: plates.map((p) {
                                final selected = selectedPlates.contains(p);

                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InputChip(
                                    label: Text(
                                      p,
                                      style: (text.labelMedium ??
                                              const TextStyle())
                                          .copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: selected
                                            ? cs.onPrimary
                                            : cs.onSurface,
                                      ),
                                    ),
                                    selected: selected,
                                    showCheckmark: false,
                                    onSelected: (_) => onToggleSelect(p),
                                    onDeleted:
                                        selected ? () => onRemove(p) : null,
                                    deleteIcon: selected
                                        ? Icon(Icons.close,
                                            size: 16, color: cs.onPrimary)
                                        : null,
                                    backgroundColor: cs.surface,
                                    selectedColor: cs.primary,
                                    side: BorderSide(
                                      color: selected
                                          ? cs.primary
                                          : cs.outline.withOpacity(.18),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '출차 요청 처리 후 완료 이벤트가 수신되면 이 영역에 번호가 표시됩니다.',
                      style: (text.bodySmall ?? const TextStyle()).copyWith(
                        fontSize: 13,
                        color: bodyColor,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
