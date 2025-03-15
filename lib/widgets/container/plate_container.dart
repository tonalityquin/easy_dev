import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../utils/fee_calculator.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/date_utils.dart';
import '../../utils/show_snackbar.dart';
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
    final plateState = Provider.of<PlateState>(context);
    final filteredData = _filterData(data, plateState.searchQuery);
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

        int basicStandard = (item.basicStandard is String)
            ? int.tryParse(item.basicStandard as String) ?? 0
            : (item.basicStandard ?? 0);
        int basicAmount =
            (item.basicAmount is String) ? int.tryParse(item.basicAmount as String) ?? 0 : (item.basicAmount ?? 0);
        int addStandard =
            (item.addStandard is String) ? int.tryParse(item.addStandard as String) ?? 0 : (item.addStandard ?? 0);
        int addAmount =
            (item.addAmount is String) ? int.tryParse(item.addAmount as String) ?? 0 : (item.addAmount ?? 0);

        int currentFee = calculateParkingFee(
          entryTimeInMinutes: item.requestTime.hour * 60 + item.requestTime.minute,
          currentTimeInMinutes: DateTime.now().hour * 60 + DateTime.now().minute,
          basicStandard: basicStandard,
          basicAmount: basicAmount,
          addStandard: addStandard,
          addAmount: addAmount,
        ).toInt();
        int elapsedMinutes = DateTime.now().difference(item.requestTime).inMinutes;

        return Column(
          children: [
            PlateCustomBox(
              topLeftText: item.plateNumber,
              topRightUpText: "${item.adjustmentType ?? '없음'}",
              topRightDownText: "${currentFee}원",
              midLeftText: item.location,
              midCenterText: displayUser,
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftLeftText: item.statusList.isNotEmpty ? item.statusList.join(", ") : "주의사항 없음",
              bottomLeftCenterText: "주의사항 수기",
              bottomRightText: "경과 시간: ${elapsedMinutes}분",
              isSelected: isSelected,
              onTap: () {
                final plateState = Provider.of<PlateState>(context, listen: false);
                plateState.toggleIsSelected(
                  collection: collection,
                  plateNumber: item.plateNumber,
                  area: item.area,
                  userName: userName,
                  onError: (errorMessage) {
                    showSnackbar(context, errorMessage);
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
