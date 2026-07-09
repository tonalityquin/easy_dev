import 'package:flutter/material.dart';

import 'area_chat_inbox_scope.dart';

class AreaChatAlertWatcher extends StatelessWidget {
  const AreaChatAlertWatcher({
    super.key,
    required this.areaNames,
    this.child,
    this.enabled = true,
    this.suppressedAreaNames = const <String>[],
  });

  final List<String> areaNames;
  final Widget? child;
  final bool enabled;
  final List<String> suppressedAreaNames;

  @override
  Widget build(BuildContext context) {
    return AreaChatInboxScope(
      areaNames: enabled ? areaNames : const <String>[],
      notificationsEnabled: enabled,
      suppressedAreaNames: suppressedAreaNames,
      builder: (context, snapshot, currentUserId) {
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
