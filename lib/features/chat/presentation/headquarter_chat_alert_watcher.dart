import 'package:flutter/material.dart';

import '../application/chat_area_key.dart';
import 'area_chat_inbox_scope.dart';

class HeadquarterChatAlertWatcher extends StatelessWidget {
  const HeadquarterChatAlertWatcher({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AreaChatInboxScope(
      areaNames: enabled ? const <String>[headquarterChatAreaName] : const <String>[],
      notificationsEnabled: enabled,
      builder: (context, snapshot, currentUserId) {
        return child;
      },
    );
  }
}
