// lib/screens/tablet_left_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';

/// 좌측 패널: plates 컬렉션에서 type=출차 요청만 실시간으로 받아 "번호판만" 렌더링.
/// 기존 _LeftPaneDeparturePlates를 별도 파일로 분리하고, 퍼블릭 클래스명으로 변경했습니다.
class LeftPaneDeparturePlates extends StatelessWidget {
  const LeftPaneDeparturePlates({super.key});

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        // PlateState가 현재 지역(currentArea)로 구독 중인 출차 요청 목록
        List<PlateModel> plates = plateState.getPlatesByCollection(PlateType.departureRequests);

        // 혹시 모를 안전장치로 type/area 재확인
        plates =
            plates.where((p) => p.type == PlateType.departureRequests.firestoreValue && p.area == currentArea).toList();

        // 최신순 정렬(요청시간 내림차순)
        plates.sort((a, b) => b.requestTime.compareTo(a.requestTime));

        final isEmpty = plates.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '출차 요청 번호판',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isEmpty
                  ? const Center(
                      child: Text(
                        '출차 요청이 없습니다.',
                        style: TextStyle(color: Colors.black45),
                      ),
                    )
                  : ListView.separated(
                      itemCount: plates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final p = plates[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.directions_car, color: Colors.blueAccent),
                          title: Text(
                            p.plateNumber,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: null,
                          // 좌측 패널은 단순 표시만
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
