// lib/services/endtime_reminder_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// 매일 endTime("HH:mm")의 1시간 전에 로컬 알림을 예약하는 서비스.
/// - flutter_local_notifications + timezone 기반
/// - Android Doze 중에도 표시되도록 exactAllowWhileIdle 사용
/// - matchDateTimeComponents: time 로 매일 반복
class EndTimeReminderService {
  EndTimeReminderService._();
  static final EndTimeReminderService instance = EndTimeReminderService._();

  FlutterLocalNotificationsPlugin? _flnp;

  // 하나의 고정 알림 ID를 사용하여 예약/취소 관리
  static const int _notifId = 90351868;
  static const String _channelId = 'easydev_reminders';
  static const String _channelName = '근무 리마인더';
  static const String _channelDesc = '퇴근 1시간 전 알림 채널';

  /// main.dart 초기화 이후 플러그인 주입
  void attachPlugin(FlutterLocalNotificationsPlugin flnp) {
    _flnp = flnp;
  }

  /// endTime: "HH:mm" (예: "18:00")
  /// - 매일 endTime - 1시간에 알림이 뜨도록 예약
  Future<void> scheduleDailyOneHourBefore(String endTimeHHmm) async {
    if (_flnp == null) return;
    final trimmed = endTimeHHmm.trim();
    if (trimmed.isEmpty) return;

    final reminderHHmm = _minusOneHour(trimmed); // "HH:mm"
    final next = _nextInstanceOf(reminderHHmm);

    // 기존 예약 취소 후 다시 등록
    await _flnp!.cancel(_notifId);

    await _flnp!.zonedSchedule(
      _notifId,
      '퇴근 1시간 전 알림',
      '퇴근 한 시간 전입니다. 반드시 퇴근 버튼을 누른 후 앱을 종료하세요.',
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // v19에서도 기본 스타일 사용 가능
          // styleInformation: DefaultStyleInformation(true, true),
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // ✔ 정확/절전모드에서도 울리게
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // ✔ 매일 같은 시각 반복
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'route=checkout',
    );
  }

  /// 예약 취소
  Future<void> cancel() async {
    if (_flnp == null) return;
    await _flnp!.cancel(_notifId);
  }

  // ---------------- 유틸 ----------------

  /// "18:00" -> "17:00" (분은 유지)
  String _minusOneHour(String hhmm) {
    final parts = hhmm.split(':');
    var h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    h = (h - 1) % 24;
    if (h < 0) h += 24;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// 오늘/내일 중 가장 가까운 미래의 해당 시각을 tz 로 반환
  tz.TZDateTime _nextInstanceOf(String hhmm) {
    final now = tz.TZDateTime.now(tz.local);
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    var schedule = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      h,
      m,
    );
    if (!schedule.isAfter(now)) {
      schedule = schedule.add(const Duration(days: 1));
    }
    return schedule;
  }
}
