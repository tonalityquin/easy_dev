import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/models/account_area_access.dart';
import '../../../../app/models/account_role_diagnostics.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/headquarter/application/area/area_master_cache.dart';
import '../../../plate/application/triple/triple_plate_state.dart';
import 'common_area_picker_sheet.dart';

const String _modeKey = 'triple';

void tripleAreaPickerBottomSheet({
  required BuildContext context,
  required AreaState areaState,
  required TriplePlateState plateState,
  bool useCommonUi = false,
}) {
  final userState = context.read<UserState>();
  final session = userState.session;
  if (session == null || session.divisions.isEmpty) return;
  final division = session.divisions.first.trim();
  if (division.isEmpty) return;

  final future = AreaMasterCache.readSelectableAreas(
    division: division,
    userAreas: session.areas,
    modeKey: _modeKey,
    role: session.role,
  );
  final rootContext = context;
  showCommonAreaPickerSheet(
    context: context,
    future: future,
    currentArea: areaState.currentArea,
    onConfirm: (selected, data) async {
      if (!data.selectableAreas.contains(selected) ||
          !AccountAreaAccess.isAssigned(userState.session?.areas ?? const <String>[], selected) ||
          (data.isHeadquarterByName[selected] == true &&
              !AccountAreaAccess.isHeadOfficeRole(session.role))) {
        AccountRoleDiagnostics.record('triple_area_rejected assigned=false');
        return;
      }
      AccountRoleDiagnostics.record('triple_area_allowed');
      Navigator.of(context).pop();
      final beforeArea = areaState.currentArea;
      await userState.areaPickerCurrentArea(selected);
      if (!rootContext.mounted) return;
      if (data.isHeadquarterByName[selected] == true) {
        plateState.tripleDisableAll();
        Navigator.pushReplacementNamed(
          rootContext,
          AppRoutes.tripleHeadquarterPage,
        );
      } else {
        plateState.tripleEnableForTypePages();
        if (beforeArea != areaState.currentArea) {
          plateState.tripleSyncWithAreaState();
        }
        Navigator.pushReplacementNamed(
          rootContext,
          AppRoutes.tripleTypePage,
        );
      }
    },
  );
}
