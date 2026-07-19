import 'package:flutter/material.dart';

const Map<String, Color> googleEventColors = <String, Color>{
  '1': Color(0xFF7986CB),
  '2': Color(0xFF33B679),
  '3': Color(0xFF8E24AA),
  '4': Color(0xFFE67C73),
  '5': Color(0xFFF6BF26),
  '6': Color(0xFFF4511E),
  '7': Color(0xFF039BE5),
  '8': Color(0xFF616161),
  '9': Color(0xFF3F51B5),
  '10': Color(0xFF0B8043),
  '11': Color(0xFFD50000),
};

const List<String> googleEventColorIds = <String>[
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '10',
  '11',
];

Color googleEventColor(String? colorId, Color fallback) {
  return googleEventColors[colorId] ?? fallback;
}

Color googleEventForegroundColor(String? colorId, Color fallback) {
  final color = googleEventColors[colorId];
  if (color == null) return fallback;
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

class GoogleEventColorPicker extends StatelessWidget {
  const GoogleEventColorPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    required this.duration,
    this.disabledColorIds = const <String>{},
    this.disabledLabels = const <String, String>{},
  });

  final String? selectedId;
  final ValueChanged<String> onSelected;
  final Duration duration;
  final Set<String> disabledColorIds;
  final Map<String, String> disabledLabels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: googleEventColorIds.map((colorId) {
        final selected = selectedId == colorId;
        final disabled = disabledColorIds.contains(colorId);
        final color = googleEventColors[colorId]!;
        final label = disabledLabels[colorId];
        final control = Semantics(
          button: true,
          selected: selected,
          enabled: !disabled,
          label: label == null
              ? '프로젝트 색상 $colorId'
              : '프로젝트 색상 $colorId, $label 사용 중',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: disabled ? null : () => onSelected(colorId),
            child: AnimatedScale(
              duration: duration,
              curve: Curves.easeOutBack,
              scale: selected ? 1.12 : 1,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: disabled ? color.withOpacity(0.28) : color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.onSurface : colors.surface,
                    width: selected ? 4 : 2,
                  ),
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: AnimatedSwitcher(
                  duration: duration,
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          key: ValueKey<String>('selected-$colorId'),
                          color: googleEventForegroundColor(
                            colorId,
                            colors.onPrimary,
                          ),
                        )
                      : disabled
                          ? Icon(
                              Icons.lock_rounded,
                              key: ValueKey<String>('disabled-$colorId'),
                              size: 18,
                              color: colors.onSurfaceVariant,
                            )
                          : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        if (label == null) return control;
        return Tooltip(message: label, child: control);
      }).toList(growable: false),
    );
  }
}
