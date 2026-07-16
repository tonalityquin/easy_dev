import 'package:flutter/foundation.dart';

class AreaChatInboxSnapshot {
  const AreaChatInboxSnapshot();

  int unreadCountForArea(String areaName, String currentUserId) {
    return 0;
  }

  int get totalUnreadCount => 0;
}

class AreaChatInboxController extends ChangeNotifier {
  static const AreaChatInboxSnapshot _emptySnapshot = AreaChatInboxSnapshot();

  AreaChatInboxSnapshot get snapshot => _emptySnapshot;

  void startReadReceiptStream() {}

  void configure({
    required String division,
    required String selectedArea,
    required List<String> areaNames,
    required String currentUserId,
    bool notificationsEnabled = false,
    List<String> suppressedAreaNames = const <String>[],
  }) {}

  void reset() {}
}
