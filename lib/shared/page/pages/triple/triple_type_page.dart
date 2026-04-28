import 'package:flutter/material.dart';
import '../../../../screens/common_package/type_page/type_page.dart';
import '../../../../screens/triple_mode/type_package/common_widgets/dashboard_bottom_sheet/triple_home_dash_board_bottom_sheet.dart';
import '../../../../screens/triple_mode/type_package/parking_completed_package/triple_parking_completed_control_buttons.dart';
import '../../../../screens/triple_mode/type_package/triple_parking_completed_page.dart';
import '../../../plate/application/common/driving_recovery_gate.dart';
import '../../../plate/application/triple/triple_plate_state.dart';
import '../../application/triple/triple_page_state.dart';
import '../../input/pages/input_plate_screen.dart';

class TripleRealtimeViewsRefreshService {
  static final TypePageRealtimeViewsRefreshService _service =
  TypePageRealtimeViewsRefreshService(
    collections: const [
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

class TripleTypePage extends StatelessWidget {
  const TripleTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return TypePageShell<TriplePlateState, TriplePageState>(
      config: TypePageConfig<TriplePlateState, TriplePageState>(
        createPageState: () => TriplePageState(),
        enableForTypePages: (plateState) {
          plateState.tripleEnableForTypePages(withDefaults: true);
        },
        disableAll: (plateState) {
          plateState.tripleDisableAll();
        },
        isLoading: (plateState) => plateState.isLoading,
        clearCurrentSelection: (plateState, pageState, userName, onError) async {
          final currentPage = pageState.pages[pageState.selectedIndex];
          final collection = currentPage.collectionKey;
          final selected =
          plateState.tripleGetSelectedPlate(collection, userName);

          if (selected != null && selected.id.isNotEmpty) {
            await plateState.tripleTogglePlateIsSelected(
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
          return TripleParkingCompletedControlButtons(
            showSearchDialog: () {
              TripleParkingCompletedPage.openSearchDialog(
                pageState.parkingCompletedKey,
                context,
              );
            },
          );
        },
        buildDashboardBottomSheet: () => const TripleHomeDashBoardBottomSheet(),
        buildInputScreen: () => const InputPlateScreen(),
        debugMeta: const <String, dynamic>{
          'screen': 'triple_type_page',
          'action': 'open_triple_input_plate_screen',
        },
        recoveryMode: DrivingRecoveryMode.triple,
      ),
    );
  }
}
