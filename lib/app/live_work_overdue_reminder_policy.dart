import 'live_work_snapshot.dart';

class LiveWorkOverdueReminderPolicy {
  LiveWorkOverdueReminderPolicy._();

  static int? currentSlot(LiveWorkSnapshot snapshot) {
    if (!snapshot.isOverdue) return null;
    final minutes = snapshot.overdueMinutes;
    if (minutes < 5) return 0;
    if (minutes < 10) return 5;
    if (minutes < 15) return 10;
    if (minutes < 20) return 15;
    if (minutes < 30) return 20;
    if (minutes < 45) return 30;
    return 45 + ((minutes - 45) ~/ 15) * 15;
  }

  static int? nextSlot(LiveWorkSnapshot snapshot) {
    if (!snapshot.isOverdue) return null;
    final current = currentSlot(snapshot);
    if (current == null) return null;
    if (current == 0) return 5;
    if (current == 5) return 10;
    if (current == 10) return 15;
    if (current == 15) return 20;
    if (current == 20) return 30;
    if (current == 30) return 45;
    return current + 15;
  }
}
