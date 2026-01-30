// lib/screens/tablet_mode/body_panels/tablet_left_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../models/plate_model.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/plate_state.dart';

/// 좌측 패널: plates 컬렉션에서 type=출차 요청만 실시간으로 받아 "번호판만" 렌더링.
/// ✅ 리팩터링 목표: 하드코딩 팔레트 제거, ColorScheme 기반(브랜드 테마)으로만 색 구성
class LeftPaneDeparturePlates extends StatelessWidget {
  const LeftPaneDeparturePlates({super.key});

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    // primary를 surface 위에 아주 얇게 얹어서 브랜드 톤 “힌트”만 주는 용도
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final currentArea = context.select<AreaState, String?>((s) => s.currentArea) ?? '';

    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        // PlateState가 현재 지역(currentArea)로 구독 중인 출차 요청 목록
        List<PlateModel> plates = plateState.getPlatesByCollection(PlateType.departureRequests);

        // 안전장치로 type/area 재확인
        plates = plates
            .where((p) => p.type == PlateType.departureRequests.firestoreValue && p.area == currentArea)
            .toList();

        // 최신순 정렬(요청시간 내림차순)
        plates.sort((a, b) => b.requestTime.compareTo(a.requestTime));

        final isEmpty = plates.isEmpty;
        final count = plates.length;

        // 아이콘 컨테이너(기존 deep blue 느낌) → primary를 아주 얇게 surface에 블렌딩
        final iconBg = _tintOnSurface(cs, opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outline.withOpacity(.10)),
                  ),
                  child: Icon(Icons.directions_car, color: cs.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '출차 요청 번호판',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (text.titleMedium ?? const TextStyle()).copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentArea.isEmpty ? '지역: -' : '지역: $currentArea',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (text.bodySmall ?? const TextStyle()).copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _CountPill(count: count),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: isEmpty
                  ? const _EmptyState(message: '출차 요청이 없습니다.')
                  : Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outline.withOpacity(.12)),
                ),
                child: Scrollbar(
                  child: ListView.separated(
                    itemCount: plates.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outline.withOpacity(.10),
                    ),
                    itemBuilder: (_, idx) {
                      final p = plates[idx];

                      // 행 배경도 하드코딩 제거
                      // - 짝수: surface
                      // - 홀수: surface에 primary 아주 약하게 얹기 (기존 base.withOpacity(.02) 역할)
                      final rowBg = idx.isEven
                          ? cs.surface
                          : _tintOnSurface(
                        cs,
                        opacity: cs.brightness == Brightness.dark ? 0.06 : 0.03,
                      );

                      return Material(
                        color: rowBg,
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minVerticalPadding: 0,
                          leading: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cs.outline.withOpacity(.10)),
                            ),
                            child: Icon(Icons.directions_car, color: cs.primary, size: 18),
                          ),
                          title: Text(
                            p.plateNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (text.bodyLarge ?? const TextStyle()).copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          // 원래 요구사항이 "번호판만" 표시였으므로 subtitle은 제거(높이 오버플로우 방지)
                          // onTap: null 유지 (단순 표시)
                          onTap: null,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;

  const _CountPill({required this.count});

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final bg = _tintOnSurface(cs, opacity: cs.brightness == Brightness.dark ? 0.16 : 0.08);
    final border = cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.28 : 0.20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list_alt_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: (text.labelMedium ?? const TextStyle()).copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ 핵심 수정 포인트:
/// - 아주 작은 높이 제약에서도 overflow가 나지 않도록
///   LayoutBuilder + SingleChildScrollView로 흡수
/// - 하드코딩 색상(_Palette) 제거 → ColorScheme 기반으로만 표현
class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 높이가 너무 작을 때(예: 분할/축소) 컴팩트 모드로 자동 전환
        final compact = constraints.maxHeight < 120;

        final iconSize = compact ? 26.0 : 40.0;
        final gap1 = compact ? 6.0 : 10.0;
        final gap2 = compact ? 4.0 : 6.0;
        final padV = compact ? 10.0 : 22.0;

        final titleStyle = (text.titleSmall ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurface,
          fontSize: compact ? 14 : (text.titleSmall?.fontSize ?? 16),
        );

        final bodyStyle = (text.bodySmall ?? const TextStyle()).copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          height: 1.25,
          fontSize: compact ? 11 : (text.bodySmall?.fontSize ?? 12),
        );

        return Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: padV),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: iconSize, color: cs.outline),
                  SizedBox(height: gap1),
                  Text('기록이 없습니다', style: titleStyle, textAlign: TextAlign.center),
                  SizedBox(height: gap2),
                  Text(message, style: bodyStyle, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
