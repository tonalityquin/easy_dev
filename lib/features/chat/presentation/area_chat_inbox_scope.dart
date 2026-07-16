import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../application/chat_account_scope.dart';
import '../controllers/area_chat_inbox_controller.dart';

class AreaChatInboxScope extends StatelessWidget {
  const AreaChatInboxScope({
    super.key,
    required this.areaNames,
    required this.builder,
    this.notificationsEnabled = false,
    this.suppressedAreaNames = const <String>[],
  });

  final List<String> areaNames;
  final Widget Function(
    BuildContext context,
    AreaChatInboxSnapshot snapshot,
    String currentUserId,
  ) builder;
  final bool notificationsEnabled;
  final List<String> suppressedAreaNames;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<UserState>().session;
    final userId = ChatAccountScope.fromSession(session).userId;
    return builder(
      context,
      const AreaChatInboxSnapshot(),
      userId,
    );
  }
}
