class AreaChatNotificationGate {
  AreaChatNotificationGate._();

  static final Set<String> _notifiedKeys = <String>{};

  static bool allow({
    required String channelId,
    required String messageId,
  }) {
    final key = '$channelId::$messageId';
    if (_notifiedKeys.contains(key)) return false;
    _notifiedKeys.add(key);
    if (_notifiedKeys.length > 500) {
      final keep = _notifiedKeys.skip(_notifiedKeys.length - 250).toSet();
      _notifiedKeys
        ..clear()
        ..addAll(keep);
    }
    return true;
  }
}
