import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/plate/application/double/double_plate_state.dart';
import '../../shared/plate/domain/enums/plate_type.dart';
import '../../shared/plate/widgets/departure_completed_operations_dock.dart';
import '../account/applications/user_state.dart';
import '../dev/application/area_state.dart';
import '../dev/application/field_calendar_state.dart';
import 'departure_completed_package/widgets/double_departure_completed_plate_image_dialog.dart';
import 'departure_completed_package/widgets/double_departure_completed_status_bottom_sheet.dart';

class DoubleDepartureCompletedBottomSheet extends StatefulWidget {
  const DoubleDepartureCompletedBottomSheet({super.key});

  @override
  State<DoubleDepartureCompletedBottomSheet> createState() =>
      _DoubleDepartureCompletedBottomSheetState();
}

class _DoubleDepartureCompletedBottomSheetState
    extends State<DoubleDepartureCompletedBottomSheet> {
  bool _areaEquals(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  Future<void> _close() async {
    final plateState = context.read<DoublePlateState>();
    final userName = context.read<UserState>().name;
    final selected = plateState.doubleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    if (selected != null && selected.id.isNotEmpty) {
      await plateState.doubleTogglePlateIsSelected(
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
    final tokens = Theme.of(context).colorScheme;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '사진 보기',
      barrierColor: tokens.scrim.withOpacity(.35),
      transitionDuration:
          MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) =>
          DoubleDepartureCompletedPlateImageDialog(plateNumber: plateNumber),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .97, end: 1).animate(animation),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<DoublePlateState>();
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
        .doubleGetPlatesByCollection(
          PlateType.departureCompleted,
          selectedDate: selectedDate,
        )
        .where(
          (plate) => !plate.isLockedFee && _areaEquals(plate.area, area),
        )
        .toList()
      ..sort((a, b) => b.requestTime.compareTo(a.requestTime));

    return DepartureCompletedOperationsDock(
      modeLabel: '더블',
      area: area,
      division: division,
      selectedDate: selectedDate,
      unsettledPlates: plates,
      refreshing: plateState.isLoadingType(PlateType.departureCompleted),
      onRefresh: () =>
          plateState.doubleRefreshType(PlateType.departureCompleted),
      onDateChanged: (date) =>
          context.read<FieldSelectedDateState>().setSelectedDate(date),
      onOpenStatus: (context, plate) =>
          showDoubleDepartureCompletedStatusBottomSheet(
        context: context,
        plate: plate,
        performedBy: userName,
      ),
      onOpenImage: _openImage,
      onClose: _close,
    );
  }
}
