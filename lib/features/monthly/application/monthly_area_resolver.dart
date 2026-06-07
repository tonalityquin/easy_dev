import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';

class MonthlyAreaResolver {
  MonthlyAreaResolver._();

  static String resolve({
    required String userArea,
    required String areaStateArea,
  }) {
    final preferred = userArea.trim();
    if (preferred.isNotEmpty) return preferred;
    return areaStateArea.trim();
  }

  static String readCurrentArea(BuildContext context) {
    final userArea = context.read<UserState>().currentArea.trim();
    if (userArea.isNotEmpty) return userArea;
    return context.read<AreaState>().currentArea.trim();
  }
}
