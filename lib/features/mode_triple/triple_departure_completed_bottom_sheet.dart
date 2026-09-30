import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/plate/application/triple/triple_plate_state.dart';
import '../../shared/plate/domain/enums/plate_type.dart';
import '../../shared/plate/widgets/departure_completed_operations_dock.dart';
import '../../shared/plate/widgets/parking_completed_status_widgets.dart';
import '../account/applications/user_state.dart';
import '../dev/application/area_state.dart';
import '../dev/application/field_calendar_state.dart';
import 'departure_completed_package/widgets/triple_departure_completed_plate_image_dialog.dart';
import 'departure_completed_package/widgets/triple_departure_completed_status_bottom_sheet.dart';

class TripleDepartureCompletedBottomSheet extends StatefulWidget {
  const TripleDepartureCompletedBottomSheet({super.key});

  @override
  State<TripleDepartureCompletedBottomSheet> createState() =>
      _TripleDepartureCompletedBottomSheetState();
}

class _TripleDepartureCompletedBottomSheetState
    extends State<TripleDepartureCompletedBottomSheet> {
  bool _areaEquals(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  Future<void> _close() async {
    final plateState = context.read<TriplePlateState>();
    final userName = context.read<UserState>().name;
    final selected = plateState.tripleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    if (selected != null && selected.id.isNotEmpty) {
      await plateState.tripleTogglePlateIsSelected(
        collection: PlateType.departureCompleted,
        plateNumber: selected.plateNumber,
        userName: userName,
        onError: debugPrint,
      );
    }
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _openImage(BuildContext context, String plateNumber) async {
    await showTripleDepartureCompletedPlateImageDialog<void>(
      context,
      plateNumber: plateNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<TriplePlateState>();
    final areaState = context.watch<AreaState>();
    final selectedDateRaw =
        context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(
      selectedDateRaw.year,
      selectedDateRaw.month,
      selectedDateRaw.day,
    );
    final area = areaState.currentArea.trim();
    final division = areaState.currentDivision;
    final userName = context.read<UserState>().name;
    final plates = plateState
        .tripleGetPlatesByCollection(
          PlateType.departureCompleted,
          selectedDate: selectedDate,
        )
        .where(
          (plate) =>
              _areaEquals(plate.area, area) &&
              resolveParkingCompletedBillingState(
                    billingType: plate.billingType,
                    billingPlanType: plate.billingPlanType,
                    isLocked: plate.isLockedFee,
                  ) ==
                  ParkingCompletedBillingState.unsettled,
        )
        .toList()
      ..sort((a, b) => b.requestTime.compareTo(a.requestTime));

    return DepartureCompletedOperationsDock(
      modeLabel: '트리플',
      area: area,
      division: division,
      selectedDate: selectedDate,
      unsettledPlates: plates,
      refreshing: plateState.isLoadingType(PlateType.departureCompleted),
      onRefresh: () =>
          plateState.tripleRefreshType(PlateType.departureCompleted),
      onDateChanged: (date) =>
          context.read<FieldSelectedDateState>().setSelectedDate(date),
      onOpenStatus: (context, plate) =>
          showTripleDepartureCompletedStatusBottomSheet(
        context: context,
        plate: plate,
        performedBy: userName,
      ),
      onOpenImage: _openImage,
      onClose: _close,
    );
  }
}
