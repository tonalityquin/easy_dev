import 'package:shared_preferences/shared_preferences.dart';

class LiveWorkOverdueReminderState {
  const LiveWorkOverdueReminderState({
    required this.eventKey,
    required this.lastSlot,
  });

  final String? eventKey;
  final int? lastSlot;
}

class LiveWorkOverdueReminderStore {
  LiveWorkOverdueReminderStore._();

  static const String _eventKey = 'live_work_overdue_reminder_event';
  static const String _slotKey = 'live_work_overdue_reminder_slot';

  static String eventKey(DateTime scheduledEnd) =>
      '${scheduledEnd.year.toString().padLeft(4, '0')}-'
      '${scheduledEnd.month.toString().padLeft(2, '0')}-'
      '${scheduledEnd.day.toString().padLeft(2, '0')}|'
      '${scheduledEnd.hour.toString().padLeft(2, '0')}:'
      '${scheduledEnd.minute.toString().padLeft(2, '0')}';

  static Future<bool> shouldNotify({
    required DateTime scheduledEnd,
    required int slot,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final currentEvent = eventKey(scheduledEnd);
    final storedEvent = prefs.getString(_eventKey);
    final storedSlot = prefs.getInt(_slotKey);
    if (storedEvent != currentEvent) return true;
    return storedSlot == null || slot > storedSlot;
  }

  static Future<void> markNotified({
    required DateTime scheduledEnd,
    required int slot,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eventKey, eventKey(scheduledEnd));
    await prefs.setInt(_slotKey, slot);
  }

  static Future<LiveWorkOverdueReminderState> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return LiveWorkOverdueReminderState(
      eventKey: prefs.getString(_eventKey),
      lastSlot: prefs.getInt(_slotKey),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventKey);
    await prefs.remove(_slotKey);
  }
}
