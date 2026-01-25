// lib/screens/tablet_mode/body_panels/tablet_left_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../models/plate_model.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/plate_state.dart';

class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

/// 좌측 패널: plates 컬렉션에서 type=출차 요청만 실시간으로 받아 "번호판만" 렌더링.
class LeftPaneDeparturePlates extends StatelessWidget {
  const LeftPaneDeparturePlates({super.key});

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
                    color: _Palette.base.withOpacity(.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.directions_car, color: _Palette.base, size: 18),
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
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: _Palette.dark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentArea.isEmpty ? '지역: -' : '지역: $currentArea',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: cs.outline,
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
                  ? const _EmptyState(
                message: '출차 요청이 없습니다.',
              )
                  : Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
                      final rowBg = idx.isEven ? Colors.white : _Palette.base.withOpacity(.02);

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
                              color: _Palette.base.withOpacity(.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.directions_car, color: _Palette.base, size: 18),
                          ),
                          title: Text(
                            p.plateNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyLarge?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _Palette.dark,
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list_alt_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
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
          color: _Palette.dark,
          fontSize: compact ? 14 : (text.titleSmall?.fontSize ?? 16),
        );

        final bodyStyle = (text.bodySmall ?? const TextStyle()).copyWith(
          color: cs.outline,
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
