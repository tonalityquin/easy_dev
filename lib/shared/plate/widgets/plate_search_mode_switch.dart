import 'package:flutter/material.dart';

enum PlateSearchMode { plates, plateStatus }

extension PlateSearchModeText on PlateSearchMode {
  String get label {
    switch (this) {
      case PlateSearchMode.plates:
        return '현재 차량';
      case PlateSearchMode.plateStatus:
        return '상태 메모';
    }
  }

  String get collectionLabel {
    switch (this) {
      case PlateSearchMode.plates:
        return 'plates';
      case PlateSearchMode.plateStatus:
        return 'plate_status';
    }
  }
}

class PlateSearchModeSwitch extends StatelessWidget {
  final PlateSearchMode value;
  final ValueChanged<PlateSearchMode> onChanged;

  const PlateSearchModeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSegment(
              selected: value == PlateSearchMode.plates,
              label: PlateSearchMode.plates.label,
              collectionLabel: PlateSearchMode.plates.collectionLabel,
              icon: Icons.directions_car_filled_outlined,
              onTap: () => onChanged(PlateSearchMode.plates),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeSegment(
              selected: value == PlateSearchMode.plateStatus,
              label: PlateSearchMode.plateStatus.label,
              collectionLabel: PlateSearchMode.plateStatus.collectionLabel,
              icon: Icons.assignment_outlined,
              onTap: () => onChanged(PlateSearchMode.plateStatus),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  final bool selected;
  final String label;
  final String collectionLabel;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeSegment({
    required this.selected,
    required this.label,
    required this.collectionLabel,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    final bg = selected ? cs.primaryContainer : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      collectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withOpacity(0.82),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
