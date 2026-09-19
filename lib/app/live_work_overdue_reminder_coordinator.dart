import 'live_work_diagnostics.dart';
import 'live_work_overdue_notification_service.dart';
import 'live_work_overdue_reminder_policy.dart';
import 'live_work_overdue_reminder_store.dart';
import 'live_work_snapshot.dart';

class LiveWorkOverdueReminderCoordinator {
  LiveWorkOverdueReminderCoordinator._();

  static Future<void> evaluate(LiveWorkSnapshot snapshot) async {
    if (!snapshot.isWorking || snapshot.scheduledEnd == null) {
      await clear();
      return;
    }
    if (!snapshot.isOverdue) return;
    final slot = LiveWorkOverdueReminderPolicy.currentSlot(snapshot);
    if (slot == null) return;
    final shouldNotify = await LiveWorkOverdueReminderStore.shouldNotify(
      scheduledEnd: snapshot.scheduledEnd!,
      slot: slot,
    );
    LiveWorkDiagnostics.record('overdue_reminder_evaluated', <String, Object?>{
      'overdueMinutes': snapshot.overdueMinutes,
      'slot': slot,
      'shouldNotify': shouldNotify,
      'event': LiveWorkOverdueReminderStore.eventKey(snapshot.scheduledEnd!),
    });
    if (!shouldNotify) return;
    final shown = await LiveWorkOverdueNotificationService.instance.show(snapshot);
    if (!shown) return;
    await LiveWorkOverdueReminderStore.markNotified(
      scheduledEnd: snapshot.scheduledEnd!,
      slot: slot,
    );
    LiveWorkDiagnostics.record('overdue_reminder_sent', <String, Object?>{
      'overdueMinutes': snapshot.overdueMinutes,
      'slot': slot,
    });
  }

  static Future<void> clear() async {
    await LiveWorkOverdueNotificationService.instance.cancel();
    await LiveWorkOverdueReminderStore.clear();
    LiveWorkDiagnostics.record('overdue_reminder_cleared');
  }
}
