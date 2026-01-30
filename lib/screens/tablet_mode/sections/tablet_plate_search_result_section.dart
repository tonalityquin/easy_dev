import 'package:easydev/enums/plate_type.dart';
import 'package:flutter/material.dart';
import '../../../models/plate_model.dart';

class TabletPlateSearchResultSection extends StatelessWidget {
  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;

  const TabletPlateSearchResultSection({
    super.key,
    required this.results,
    required this.onSelect,
    this.onRefresh,
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
    // 태블릿 검색 결과는 보통 completed 계열이 대부분(요청/완료 둘 다 대응은 유지)
    final Color base = switch (type) {
      PlateType.parkingRequests => cs.primary,
      PlateType.parkingCompleted => cs.tertiary,
      PlateType.departureRequests => cs.secondary,
      PlateType.departureCompleted => cs.primary,
      null => cs.primary,
    };

    final bg = _tintOnSurface(cs, base, opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10);
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

    // 이 검색은 뒷 4자리 기준이라 “가끔” 다건이 나올 수 있음.
    // 다만 사용자가 말한 것처럼 흔치/많지 않으니, 2건 이상일 때만 아주 가벼운 안내 배너를 노출.
    final showMultiHint = results.length >= 2;
    final extra = showMultiHint ? 1 : 0;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: results.length + extra,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (showMultiHint && index == 0) {
          final bg = _tintOnSurface(cs, cs.primary, opacity: cs.brightness == Brightness.dark ? 0.14 : 0.08);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.40 : 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '동일 뒷번호로 ${results.length}건이 조회되었습니다. 아래에서 전체 번호판을 선택하세요.',
                    style: (text.bodySmall ?? const TextStyle()).copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
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
            ? _tintOnSurface(cs, cs.primary, opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10)
            : cs.surface;

        final borderColor = selected
            ? cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.65 : 0.55)
            : cs.outlineVariant.withOpacity(cs.brightness == Brightness.dark ? 0.55 : 0.42);

        final shadowColor = cs.shadow.withOpacity(cs.brightness == Brightness.dark ? 0.20 : 0.06);

        final meta = '${_formatDateTime(plate.requestTime)} · ${plate.location.isEmpty ? '위치 미지정' : plate.location}';

        return Material(
          color: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _tintOnSurface(cs, chip.fg, opacity: cs.brightness == Brightness.dark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: chip.border.withOpacity(.55)),
                    ),
                    child: Icon(
                      _leadingIcon(type),
                      size: 18,
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
                          style: (text.titleMedium ?? const TextStyle()).copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            height: 1.05,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          meta,
                          style: (text.bodySmall ?? const TextStyle()).copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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

  const _TypeChip({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: (t.labelMedium ?? const TextStyle()).copyWith(
          color: fg,
          fontWeight: FontWeight.w900,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
