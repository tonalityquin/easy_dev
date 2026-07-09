import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';

class ChatAreaResolver {
  const ChatAreaResolver._();

  static String read(BuildContext context) {
    final areaStateArea = context.read<AreaState>().currentArea.trim();
    if (areaStateArea.isNotEmpty) {
      return areaStateArea;
    }
    return context.read<UserState>().currentArea.trim();
  }

  static String watch(BuildContext context) {
    final areaStateArea = context.watch<AreaState>().currentArea.trim();
    if (areaStateArea.isNotEmpty) {
      return areaStateArea;
    }
    return context.watch<UserState>().currentArea.trim();
  }
}
