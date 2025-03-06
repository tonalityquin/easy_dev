import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../utils/fee_calculator.dart';
import '../../states/plate_state.dart';
import '../../states/user_state.dart';
import '../../utils/date_utils.dart'; // 날짜 관련 유틸리티
import '../../utils/show_snackbar.dart'; // ✅ showSnackbar 유틸 추가
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
  List<PlateModel> _filterData(List<PlateModel> data, String searchQuery) {
    final seenIds = <String>{};

    return data.where((request) {
      if (seenIds.contains(request.id)) {
        return false;
      }
      seenIds.add(request.id);

      // 🔹 plate_number 마지막 4자리를 검색어와 비교
      if (searchQuery.isNotEmpty) {
        String lastFourDigits = request.plateNumber.length >= 4
            ? request.plateNumber.substring(request.plateNumber.length - 4)
            : request.plateNumber;

        if (lastFourDigits != searchQuery) {
          return false;
        }
      }

      return filterCondition == null || filterCondition!(request);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final plateState = Provider.of<PlateState>(context); // ✅ `build` 내부에서 접근
    final filteredData = _filterData(data, plateState.searchQuery); // ✅ `searchQuery` 전달
    final userName = Provider.of<UserState>(context, listen: false).name;

    // 데이터가 없을 경우 표시할 UI
    if (filteredData.isEmpty) {
      return const Center(
        child: Text(
          '현재 조건에 맞는 데이터가 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    // 필터링된 데이터를 기반으로 UI 생성
    return Column(
      children: filteredData.map((item) {
        final backgroundColor = item.isSelected ? Colors.greenAccent : Colors.white;
        final displayUser = item.isSelected ? item.selectedBy : item.userName;

        // ✅ Firestore에서 가져온 데이터가 `String`일 경우 `int`로 변환 (null인 경우 기본값 0 설정)
        int basicStandard = (item.basicStandard is String)
            ? int.tryParse(item.basicStandard as String) ?? 0
            : (item.basicStandard ?? 0);

        int basicAmount =
            (item.basicAmount is String) ? int.tryParse(item.basicAmount as String) ?? 0 : (item.basicAmount ?? 0);

        int addStandard =
            (item.addStandard is String) ? int.tryParse(item.addStandard as String) ?? 0 : (item.addStandard ?? 0);

        int addAmount =
            (item.addAmount is String) ? int.tryParse(item.addAmount as String) ?? 0 : (item.addAmount ?? 0);

        // 🚗 주차 요금 계산
        int currentFee = calculateParkingFee(
          entryTimeInMinutes: item.requestTime.hour * 60 + item.requestTime.minute,
          currentTimeInMinutes: DateTime.now().hour * 60 + DateTime.now().minute,
          basicStandard: basicStandard,
          // ✅ 변환된 값 사용
          basicAmount: basicAmount,
          // ✅ 변환된 값 사용
          addStandard: addStandard,
          // ✅ 변환된 값 사용
          addAmount: addAmount, // ✅ 변환된 값 사용
        ).toInt();

        // ✅ 경과 시간 복구
        int elapsedMinutes = DateTime.now().difference(item.requestTime).inMinutes;

        return Column(
          children: [
            PlateCustomBox(
              topLeftText: item.plateNumber,
              topRightUpText: "${item.adjustmentType ?? '없음'}",
              topRightDownText: "${currentFee}원",
              midLeftText: item.location,
              midCenterText: displayUser ?? '기본 사용자',
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftLeftText: item.statusList.isNotEmpty ? item.statusList.join(", ") : "주의사항 없음",
              bottomLeftCenterText: "주의사항 수기",
              bottomRightText: "경과 시간: ${elapsedMinutes}분",
              // ✅ 경과 시간 복구
              backgroundColor: backgroundColor,
              onTap: () {
                final plateState = Provider.of<PlateState>(context, listen: false);
                plateState.toggleIsSelected(
                  collection: collection,
                  plateNumber: item.plateNumber,
                  area: item.area,
                  userName: userName,
                  onError: (errorMessage) {
                    showSnackbar(context, errorMessage); // ✅ showSnackbar 유틸 적용
                  },
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
