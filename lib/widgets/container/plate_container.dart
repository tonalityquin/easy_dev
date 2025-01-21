import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../states/plate_state.dart';
import '../../utils/date_utils.dart'; // 날짜 관련 유틸리티
import 'plate_custom_box.dart'; // 커스텀 박스 위젯

/// PlateContainer
/// - 번호판 데이터를 기반으로 필터링 및 UI를 생성하는 위젯
/// - 선택된 번호판, 필터 조건, 클릭 이벤트 등을 처리
class PlateContainer extends StatelessWidget {
  final List<PlateModel> data; // 번호판 데이터 리스트
  final bool Function(PlateModel)? filterCondition; // 데이터 필터 조건
  final String collection; // 컬렉션 이름
  final void Function(String plateNumber, String area) onPlateTap; // 번호판 클릭 이벤트

  const PlateContainer({
    required this.data,
    required this.collection,
    required this.onPlateTap,
    this.filterCondition,
    super.key,
  });

  /// 데이터 필터링 및 중복 제거
  List<PlateModel> _filterData(List<PlateModel> data) {
    final seenIds = <String>{};
    return data.where((request) {
      if (seenIds.contains(request.id)) {
        return false; // 중복 제거
      }
      seenIds.add(request.id);
      return filterCondition == null || filterCondition!(request); // 필터 조건 적용
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _filterData(data); // 데이터 필터링

    // 데이터가 없을 경우 표시할 UI
    if (filteredData.isEmpty) {
      return Center(
        child: const Text(
          '현재 조건에 맞는 데이터가 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    // 필터링된 데이터를 기반으로 UI 생성
    return Column(
      children: filteredData.map((item) {
        final backgroundColor = item.isSelected ? Colors.greenAccent : Colors.white; // 선택 여부에 따른 배경색

        return Column(
          children: [
            PlateCustomBox(
              topLeftText: item.plateNumber,
              topRightText: "정산 영역",
              midLeftText: item.location,
              midCenterText: item.userName, // 생성자 이름 (PlateModel에서 가져옴)
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftText: "주의사항",
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime),
              backgroundColor: backgroundColor,
              onTap: () {
                final newSelectedState = !item.isSelected; // 상태 반전
                Provider.of<PlateState>(context, listen: false).updateIsSelected(
                  collection: collection, // 동적 컬렉션 이름
                  id: item.id,
                  isSelected: newSelectedState,
                );
              },
            ),
            const SizedBox(height: 5), // 간격 추가
          ],
        );
      }).toList(),
    );
  }
}
