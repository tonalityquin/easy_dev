import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../shared/page/application/common/type_view_mode_state.dart';
import '../../../shared/page/widget/navigation/double_top_navigation.dart';
import '../../../shared/plate/application/double/double_plate_state.dart';
import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../common_package/real_time_table/view_doc_rows_firestore_sync.dart';
import '../../common_package/type_page/parking_completed_page/parking_completed_page_shell.dart';
import 'parking_completed_package/double_parking_completed_real_time_table.dart';
import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/double_parking_completed_search_bottom_sheet.dart';

class DoubleParkingCompletedPage extends StatefulWidget {
  const DoubleParkingCompletedPage({super.key});

  static void openSearchDialog(GlobalKey key, BuildContext context) {
    (key.currentState as _DoubleParkingCompletedPageState?)
        ?._showSearchDialog(context);
  }

  @override
  State<DoubleParkingCompletedPage> createState() =>
      _DoubleParkingCompletedPageState();
}

class _DoubleParkingCompletedPageState
    extends State<DoubleParkingCompletedPage> {
  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('[ParkingCompleted] $msg');
    }
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;
    _log('open search dialog');

    showDialog(
      context: context,
      builder: (context) {
        return DoubleParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  Future<bool> _handleWillPop() async {
    final plateState = context.read<DoublePlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.doubleGetSelectedPlate(
      PlateType.parkingCompleted,
      userName,
    );

    if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
      await plateState.doubleTogglePlateIsSelected(
        collection: PlateType.parkingCompleted,
        plateNumber: selectedPlate.plateNumber,
        userName: userName,
        onError: (msg) => debugPrint(msg),
      );
      _log('clear selection');
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<TypeViewModeState>().mode;
    final area = resolveParkingCompletedArea(context);

    return ParkingCompletedPageShell(
      topNavigation: const DoubleTopNavigation(),
      semanticsLabel: 'screen_tag: DoubleParkingCompletedPage',
      syncSourceTag: 'DoubleParkingCompletedPage(sync)',
      syncSpecs: const [
        ViewDocSyncSpec(
          collection: 'parking_completed_view',
          primaryAtField: 'parkingCompletedAt',
        ),
      ],
      onWillPop: _handleWillPop,
      content: DoubleParkingCompletedRealTimeTable(
        statusPreview: mode == TypeViewMode.status,
        area: area,
      ),
    );
  }
}
