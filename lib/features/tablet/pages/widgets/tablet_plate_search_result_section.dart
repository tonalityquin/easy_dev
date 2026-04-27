import 'package:flutter/material.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/models/plate_model.dart';

class TabletPlateSearchResultSection extends StatelessWidget {
  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;

  
  final bool compact;

  const TabletPlateSearchResultSection({
    super.key,
    required this.results,
    required this.onSelect,
    this.onRefresh,
    this.compact = false,
  });

  Color _tintOnSurface(ColorScheme cs, Color tint, {required double opacity}) {
    return Color.alphaBlend(tint.withOpacity(opacity), cs.surface);
  }

  String _formatDateTime(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$m-$d $hh:$mm';
  }

  ({Color fg, Color bg, Color border}) _chipColors(ColorScheme cs, PlateType? type) {
    final Color base = switch (type) {
      PlateType.parkingRequests => cs.primary,
      PlateType.parkingCompleted => cs.tertiary,
      PlateType.departureRequests => cs.secondary,
      PlateType.departureCompleted => cs.primary,
      null => cs.primary,
    };

    final bg = _tintOnSurface(
      cs,
      base,
      opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10,
    );
    final border = base.withOpacity(cs.brightness == Brightness.dark ? 0.55 : 0.45);
    return (fg: base, bg: bg, border: border);
  }

  IconData _leadingIcon(PlateType? type) {
    return switch (type) {
      PlateType.parkingRequests => Icons.login,
      PlateType.parkingCompleted => Icons.check_circle_outline,
      PlateType.departureRequests => Icons.logout,
      PlateType.departureCompleted => Icons.check_circle_outline,
      null => Icons.directions_car,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final showMultiHint = results.length >= 2;
    final extra = showMultiHint ? 1 : 0;

    final outerPadding = compact ? 12.0 : 16.0;
    final itemGap = compact ? 10.0 : 12.0;

    final cardRadius = compact ? 16.0 : 18.0;
    final iconBox = compact ? 40.0 : 46.0;
    final iconRadius = compact ? 14.0 : 16.0;
    final iconSize = compact ? 20.0 : 22.0;

    final cardPadH = compact ? 14.0 : 18.0;
    final cardPadV = compact ? 14.0 : 16.0;

    
    final TextStyle plateBase =
    compact ? (text.titleMedium ?? const TextStyle()) : (text.titleLarge ?? const TextStyle());
    final TextStyle metaBase =
    compact ? (text.bodyMedium ?? const TextStyle()) : (text.bodyLarge ?? const TextStyle());

    final plateStyle = plateBase.copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
      height: 1.05,
    );

    final metaStyle = metaBase.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );

    return ListView.separated(
      padding: EdgeInsets.all(outerPadding),
      itemCount: results.length + extra,
      separatorBuilder: (_, __) => SizedBox(height: itemGap),
      itemBuilder: (context, index) {
        if (showMultiHint && index == 0) {
          final bg = _tintOnSurface(
            cs,
            cs.primary,
            opacity: cs.brightness == Brightness.dark ? 0.14 : 0.08,
          );

          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(compact ? 14 : 16),
              border: Border.all(
                color: cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.40 : 0.22),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: compact ? 20 : 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '동일 뒷번호로 ${results.length}건이 조회되었습니다.\n아래에서 전체 번호판을 선택하세요.',
                    style: (compact ? (text.bodyMedium ?? const TextStyle()) : (text.bodyLarge ?? const TextStyle()))
                        .copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final plate = results[index - extra];
        final type = plate.typeEnum;
        final typeLabel = type?.label ?? plate.type;

        final chip = _chipColors(cs, type);

        final selected = plate.isSelected;
        final cardBg = selected
            ? _tintOnSurface(
          cs,
          cs.primary,
          opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10,
        )
            : cs.surface;

        final borderColor = selected
            ? cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.65 : 0.55)
            : cs.outlineVariant.withOpacity(cs.brightness == Brightness.dark ? 0.55 : 0.42);

        final shadowColor = cs.shadow.withOpacity(cs.brightness == Brightness.dark ? 0.20 : 0.06);

        final meta =
            '${_formatDateTime(plate.requestTime)} · ${plate.location.isEmpty ? '위치 미지정' : plate.location}';

        return Material(
          color: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: InkWell(
            onTap: () => onSelect(plate),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(horizontal: cardPadH, vertical: cardPadV),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: iconBox,
                    height: iconBox,
                    decoration: BoxDecoration(
                      color: _tintOnSurface(
                        cs,
                        chip.fg,
                        opacity: cs.brightness == Brightness.dark ? 0.20 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(iconRadius),
                      border: Border.all(color: chip.border.withOpacity(.55)),
                    ),
                    child: Icon(
                      _leadingIcon(type),
                      size: iconSize,
                      color: chip.fg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plate.plateNumber,
                          style: plateStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          meta,
                          style: metaStyle,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _TypeChip(
                    label: typeLabel,
                    fg: chip.fg,
                    bg: chip.bg,
                    border: chip.border,
                    compact: compact,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  final Color border;
  final bool compact;

  const _TypeChip({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    
    final TextStyle base =
    compact ? (t.labelLarge ?? const TextStyle()) : (t.titleSmall ?? const TextStyle());

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 32 : 38),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: base.copyWith(
          color: fg,
          fontWeight: FontWeight.w900,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
