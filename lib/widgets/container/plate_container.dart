import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../states/plate/filter_plate.dart';
import '../../utils/fee_calculator.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/date_utils.dart';
import '../../utils/snackbar_helper.dart';
import 'plate_custom_box.dart';

class PlateContainer extends StatelessWidget {
  final List<PlateModel> data;
  final bool Function(PlateModel)? filterCondition;
  final String collection;
  final void Function(String plateNumber, String area) onPlateTap;

  const PlateContainer({
    required this.data,
    required this.collection,
    required this.onPlateTap,
    this.filterCondition,
    super.key,
  });

  List<PlateModel> _filterData(List<PlateModel> data, String searchQuery) {
    final seenIds = <String>{};
    return data.where((request) {
      if (seenIds.contains(request.id)) {
        return false;
      }
      seenIds.add(request.id);
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
    final filterPlate = context.watch<FilterPlate>();
    final searchQuery = filterPlate.searchQuery;
    final filteredData = _filterData(data, searchQuery);

    final userName = Provider.of<UserState>(context, listen: false).name;

    if (filteredData.isEmpty) {
      return const Center(
        child: Text(
          '현재 조건에 맞는 데이터가 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return Column(
      children: filteredData.map((item) {
        final bool isSelected = item.isSelected;
        final String displayUser = isSelected ? item.selectedBy! : item.userName;

        int basicStandard = item.basicStandard ?? 0;
        int basicAmount = item.basicAmount ?? 0;
        int addStandard = item.addStandard ?? 0;
        int addAmount = item.addAmount ?? 0;

        int currentFee = calculateParkingFee(
          entryTimeInSeconds: item.requestTime.millisecondsSinceEpoch ~/ 1000,
          currentTimeInSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          basicStandard: basicStandard,
          basicAmount: basicAmount,
          addStandard: addStandard,
          addAmount: addAmount,
          isLockedFee: item.isLockedFee,
          lockedAtTimeInSeconds: item.lockedAtTimeInSeconds,
        ).toInt();

        final duration = DateTime.now().difference(item.requestTime);
        final elapsedText = "${duration.inMinutes}분 ${duration.inSeconds % 60}초";

        // ✅ 배경색 조건 처리
        Color? backgroundColor;
        if (item.adjustmentType == null || item.adjustmentType!.trim().isEmpty) {
          backgroundColor = Colors.white;
        } else {
          backgroundColor = item.isLockedFee ? Colors.orange[50] : Colors.white;
        }

        return Column(
          children: [
            PlateCustomBox(
              topLeftText: '${item.region ?? '전국'} ${item.plateNumber}',
              topRightUpText: "${item.adjustmentType ?? '없음'}",
              topRightDownText: "${currentFee}원",
              midLeftText: item.location,
              midCenterText: displayUser,
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftLeftText: item.statusList.isNotEmpty ? item.statusList.join(", ") : "주의사항 없음",
              bottomLeftCenterText: "주의사항 수기",
              bottomRightText: elapsedText,
              isSelected: isSelected,
              backgroundColor: backgroundColor,
              onTap: () {
                final plateState = Provider.of<PlateState>(context, listen: false);

                if (item.isSelected && item.selectedBy != userName) {
                  showFailedSnackbar(context, "⚠️ 이미 다른 사용자가 선택한 번호판입니다.");
                  return;
                }

                final alreadySelected = data.any(
                  (p) => p.isSelected && p.selectedBy == userName && p.id != item.id,
                );

                if (alreadySelected && !item.isSelected) {
                  showFailedSnackbar(context, "⚠️ 이미 다른 번호판을 선택한 상태입니다.");
                  return;
                }

                plateState.toggleIsSelected(
                  collection: collection,
                  plateNumber: item.plateNumber,
                  userName: userName,
                  onError: (errorMessage) {
                    showFailedSnackbar(context, errorMessage);
                  },
                );
              },
            ),
            const SizedBox(height: 5),
          ],
        );
      }).toList(),
    );
  }
}
