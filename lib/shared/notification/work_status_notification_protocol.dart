class WorkStatusNotificationProtocol {
  const WorkStatusNotificationProtocol._();

  static const String eventKind = 'work_status_notification_event_v1';
  static const String pressedEvent = 'notification_pressed';
  static const String dismissedEvent = 'notification_dismissed';
  static const String serviceTimeoutEvent = 'service_timeout';
  static const String serviceDestroyedEvent = 'service_destroyed';
  static const String serviceStartBlockedNotWorkingEvent =
      'service_start_blocked_not_working';
}
