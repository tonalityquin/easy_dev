import 'package:flutter/material.dart';
import '../../../../screens/common_package/type_page/type_page.dart';
import '../../../../screens/minor_mode/type_package/common_widgets/dashboard_bottom_sheet/minor_home_dash_board_bottom_sheet.dart';
import '../../../../screens/minor_mode/type_package/minor_parking_completed_page.dart';
import '../../../../screens/minor_mode/type_package/parking_completed_package/minor_parking_completed_control_buttons.dart';
import '../../../plate/application/common/driving_recovery_gate.dart';
import '../../../plate/application/minor/minor_plate_state.dart';
import '../../application/minor/minor_page_state.dart';
import '../../input/pages/input_plate_screen.dart';

class MinorRealtimeViewsRefreshService {
  static final TypePageRealtimeViewsRefreshService _service =
      TypePageRealtimeViewsRefreshService(
    collections: const [
      'parking_requests_view',
      'parking_completed_view',
      'departure_requests_view',
    ],
  );

  static Future<void> refreshAllForArea(
    BuildContext context,
    String area,
  ) {
    return _service.refreshAllForArea(context, area);
  }

  static Future<void> refreshAllForCurrentArea(BuildContext context) {
    return _service.refreshAllForCurrentArea(context);
  }
}

class MinorTypePage extends StatelessWidget {
  const MinorTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return TypePageShell<MinorPlateState, MinorPageState>(
      config: TypePageConfig<MinorPlateState, MinorPageState>(
        createPageState: () => MinorPageState(),
        enableForTypePages: (plateState) {
          plateState.minorEnableForTypePages(withDefaults: true);
        },
        disableAll: (plateState) {
          plateState.minorDisableAll();
        },
        isLoading: (plateState) => plateState.isLoading,
        clearCurrentSelection:
            (plateState, pageState, userName, onError) async {
          final currentPage = pageState.pages[pageState.selectedIndex];
          final collection = currentPage.collectionKey;
          final selected =
              plateState.minorGetSelectedPlate(collection, userName);

          if (selected != null && selected.id.isNotEmpty) {
            await plateState.minorTogglePlateIsSelected(
              collection: collection,
              plateNumber: selected.plateNumber,
              userName: userName,
              onError: onError,
            );
          }
        },
        buildCurrentPage: (context, pageState) {
          final pageInfo = pageState.pages[pageState.selectedIndex];
          return pageInfo.builder(context);
        },
        buildParkingCompletedControlBar: (context, pageState) {
          return MinorParkingCompletedControlButtons(
            showSearchDialog: () {
              MinorParkingCompletedPage.openSearchDialog(
                pageState.parkingCompletedKey,
                context,
              );
            },
          );
        },
        buildDashboardBottomSheet: () => const MinorHomeDashBoardBottomSheet(),
        buildInputScreen: () => const InputPlateScreen(isMinorMode: true),
        debugMeta: const <String, dynamic>{
          'screen': 'minor_type_page',
          'action': 'open_minor_input_plate_screen',
          'isMinorMode': true,
        },
        recoveryMode: DrivingRecoveryMode.minor,
      ),
    );
  }
}
