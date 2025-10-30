import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../states/plate/filter_plate.dart';
import '../../utils/plate_container_fee_calculator.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/date_utils.dart';
import '../../utils/snackbar_helper.dart';
import '../dialog/billing_bottom_sheet/fee_calculator.dart'; // billTypeFromString 가져오기 위해 필요
import 'plate_custom_box.dart';

class PlateContainer extends StatelessWidget {
  final List<PlateModel> data;
  final bool Function(PlateModel)? filterCondition;
  final PlateType collection;
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
      if (seenIds.contains(request.id)) return false;
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

  String formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours시간 $minutes분';
    } else if (minutes > 0) {
      return '$minutes분 $seconds초';
    } else {
      return '$seconds초';
    }
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

        final billType = billTypeFromString(item.billingType);
        final bool isRegular = billType == BillType.fixed;

        int basicStandard = item.basicStandard ?? 0;
        int basicAmount = item.basicAmount ?? 0;
        int addStandard = item.addStandard ?? 0;
        int addAmount = item.addAmount ?? 0;

        int currentFee = 0;
        if (!isRegular) {
          if (item.isLockedFee && item.lockedFeeAmount != null) {
            currentFee = item.lockedFeeAmount!;
          } else {
            currentFee = calculateParkingFee(
              entryTimeInSeconds: item.requestTime.millisecondsSinceEpoch ~/ 1000,
              currentTimeInSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              basicStandard: basicStandard,
              basicAmount: basicAmount,
              addStandard: addStandard,
              addAmount: addAmount,
              isLockedFee: item.isLockedFee,
              lockedAtTimeInSeconds: item.lockedAtTimeInSeconds,
              userAdjustment: item.userAdjustment ?? 0,
              mode: _parseFeeMode(item.feeMode),
            ).toInt();
          }
        }

        final feeText = isRegular
            ? '${item.isLockedFee ? (item.lockedFeeAmount ?? 0) : (item.regularAmount ?? 0)}원'
            : '$currentFee원';

        // ✅ 출차 완료(미정산 목록)에서는 시간이 흐르지 않도록 endTime(또는 updatedAt) 기준으로 고정
        final DateTime endForElapsed = (collection == PlateType.departureCompleted)
            ? (item.endTime ?? item.updatedAt ?? item.requestTime)
            : DateTime.now();
        final duration = endForElapsed.difference(item.requestTime);
        final elapsedText = formatElapsed(duration);

        final backgroundColor =
        ((item.billingType?.trim().isNotEmpty ?? false) && item.isLockedFee) ? Colors.orange[50] : Colors.white;

        return Column(
          children: [
            PlateCustomBox(
              key: ValueKey(item.id),
              topLeftText: '소속', // ✅ 요구사항: 하드코딩
              topCenterText: '${item.region ?? '전국'} ${item.plateNumber}', // ✅ 기존 내용 이동
              topRightUpText: item.billingType ?? '없음',
              topRightDownText: feeText,
              midLeftText: item.location,
              midCenterText: displayUser,
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftLeftText: item.statusList.isNotEmpty ? item.statusList.join(", ") : "",
              bottomLeftCenterText: item.customStatus ?? '',
              bottomRightText: elapsedText,
              isSelected: isSelected,
              backgroundColor: backgroundColor,
              onTap: () {
                final plateState = Provider.of<PlateState>(context, listen: false);

                final isOtherUserSelected = item.isSelected && item.selectedBy != userName;
                final isAnotherPlateSelected = data.any(
                      (p) => p.isSelected && p.selectedBy == userName && p.id != item.id,
                );

                if (isOtherUserSelected) {
                  showFailedSnackbar(context, "⚠️ 이미 다른 사용자가 선택한 번호판입니다.");
                  return;
                }

                if (isAnotherPlateSelected && !item.isSelected) {
                  showFailedSnackbar(context, "⚠️ 이미 다른 번호판을 선택한 상태입니다.");
                  return;
                }

                plateState.togglePlateIsSelected(
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

  FeeMode _parseFeeMode(String? modeString) {
    switch (modeString) {
      case 'plus':
        return FeeMode.plus;
      case 'minus':
        return FeeMode.minus;
      default:
        return FeeMode.normal;
    }
  }
}
