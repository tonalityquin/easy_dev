import 'package:flutter/material.dart';
import '../../../../features/dashboard/sheets/double/double_home_dash_board_bottom_sheet.dart';
import '../../../../features/mode_double/double_parking_completed_page.dart';
import '../../../../features/mode_double/parking_completed_package/double_parking_completed_control_buttons.dart';
import '../../../plate/application/double/double_plate_state.dart';
import '../../application/double/double_page_state.dart';
import '../../input/pages/input_plate_screen.dart';
import '../common/type_page.dart';

class DoubleRealtimeViewsRefreshService {
  static final TypePageRealtimeViewsRefreshService _service =
  TypePageRealtimeViewsRefreshService(
    collections: const ['parking_completed_view'],
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

class DoubleTypePage extends StatelessWidget {
  const DoubleTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return TypePageShell<DoublePlateState, DoublePageState>(
      config: TypePageConfig<DoublePlateState, DoublePageState>(
        createPageState: () => DoublePageState(),
        enableForTypePages: (plateState) {
          plateState.doubleEnableForTypePages(withDefaults: true);
        },
        disableAll: (plateState) {
          plateState.doubleDisableAll();
        },
        isLoading: (plateState) => plateState.isLoading,
        clearCurrentSelection: (plateState, pageState, userName, onError) async {
          final currentPage = pageState.pages[pageState.selectedIndex];
          final collection = currentPage.collectionKey;
          final selected =
          plateState.doubleGetSelectedPlate(collection, userName);

          if (selected != null && selected.id.isNotEmpty) {
            await plateState.doubleTogglePlateIsSelected(
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
          return DoubleParkingCompletedControlButtons(
            showSearchDialog: () {
              DoubleParkingCompletedPage.openSearchDialog(
                pageState.parkingCompletedKey,
                context,
              );
            },
          );
        },
        buildDashboardBottomSheet: () => const DoubleHomeDashBoardBottomSheet(),
        buildInputScreen: () => const InputPlateScreen(),
        debugMeta: const <String, dynamic>{
          'screen': 'lite_type_page',
          'action': 'open_double_input_plate_screen',
        },
      ),
    );
  }
}
