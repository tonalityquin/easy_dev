import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class EndTimeReminderService {
  EndTimeReminderService._();
  static final EndTimeReminderService instance = EndTimeReminderService._();

  FlutterLocalNotificationsPlugin? _flnp;

  static const int _dailyNotifId = 90351868;
  static const int _weeklyBaseNotifId = 90351880;

  static const String _channelId = 'ParkinWorkin_reminders';
  static const String _channelName = '근무 리마인더';
  static const String _channelDesc = '퇴근 1시간 전 알림 채널';

  void attachPlugin(FlutterLocalNotificationsPlugin flnp) {
    _flnp = flnp;
  }

  Future<void> cancel() async {
    if (_flnp == null) return;
    await _flnp!.cancel(_dailyNotifId);
    for (int w = 1; w <= 7; w++) {
      await _flnp!.cancel(_weeklyNotifId(w));
    }
  }

  Future<void> scheduleDailyOneHourBefore(String endTimeHHmm) async {
    if (_flnp == null) return;

    final trimmed = endTimeHHmm.trim();
    if (trimmed.isEmpty) return;

    final spec = _minusOneHourWithShift(trimmed);
    final reminderHHmm = spec.hhmm;
    final next = _nextInstanceOf(reminderHHmm);

    await cancel();

    await _flnp!.zonedSchedule(
      _dailyNotifId,
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
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'route=checkout',
    );
  }

  Future<void> scheduleWeeklyOneHourBefore({
    required String endTimeHHmm,
    required List<String> fixedHolidays,
  }) async {
    if (_flnp == null) return;

    final trimmed = endTimeHHmm.trim();
    if (!_isValidHHmm(trimmed)) {
      await cancel();
      return;
    }

    int dayToWeekday(String d) {
      switch (d.trim()) {
        case '월':
          return DateTime.monday;
        case '화':
          return DateTime.tuesday;
        case '수':
          return DateTime.wednesday;
        case '목':
          return DateTime.thursday;
        case '금':
          return DateTime.friday;
        case '토':
          return DateTime.saturday;
        case '일':
          return DateTime.sunday;
        default:
          return DateTime.monday;
      }
    }

    const days = <String>['월', '화', '수', '목', '금', '토', '일'];
    final off = fixedHolidays.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    final workingWeekdays = <int>{};
    for (final d in days) {
      if (!off.contains(d)) workingWeekdays.add(dayToWeekday(d));
    }

    final endTimeHHmmByWeekday = <int, String>{};
    for (final d in days) {
      endTimeHHmmByWeekday[dayToWeekday(d)] = trimmed;
    }

    await scheduleWeeklyOneHourBeforeByWeekday(
      endTimeHHmmByWeekday: endTimeHHmmByWeekday,
      workingWeekdays: workingWeekdays,
    );
  }

  Future<void> scheduleWeeklyOneHourBeforeByWeekday({
    required Map<int, String> endTimeHHmmByWeekday,
    required Set<int> workingWeekdays,
  }) async {
    if (_flnp == null) return;

    await _flnp!.cancel(_dailyNotifId);

    for (int endWeekday = 1; endWeekday <= 7; endWeekday++) {
      final id = _weeklyNotifId(endWeekday);
      final isWorkingDay = workingWeekdays.contains(endWeekday);

      final endTime = (endTimeHHmmByWeekday[endWeekday] ?? '').trim();
      if (!isWorkingDay || !_isValidHHmm(endTime)) {
        await _flnp!.cancel(id);
        continue;
      }

      final minusSpec = _minusOneHourWithShift(endTime);
      final reminderWeekday = _shiftWeekday(endWeekday, minusSpec.dayShift);
      final reminderHHmm = minusSpec.hhmm;

      final next = _nextInstanceOfWeekday(reminderWeekday, reminderHHmm);

      await _flnp!.cancel(id);

      await _flnp!.zonedSchedule(
        id,
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
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'route=checkout',
      );
    }
  }

  int _weeklyNotifId(int weekday) => _weeklyBaseNotifId + weekday;

  bool _isValidHHmm(String hhmm) {
    final s = hhmm.trim();
    if (s.isEmpty) return false;
    final parts = s.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;
    if (h < 0 || h > 23 || m < 0 || m > 59) return false;
    return true;
  }

  int _shiftWeekday(int weekday, int dayShift) {
    final zeroBased = weekday - 1;
    final shifted = (zeroBased + dayShift) % 7;
    final norm = shifted < 0 ? shifted + 7 : shifted;
    return norm + 1;
  }

  _MinusOneHourSpec _minusOneHourWithShift(String hhmm) {
    final parts = hhmm.split(':');
    var h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    if (h == 0) {
      h = 23;
      return _MinusOneHourSpec(
        dayShift: -1,
        hhmm: '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
      );
    }

    h = h - 1;
    return _MinusOneHourSpec(
      dayShift: 0,
      hhmm: '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
    );
  }

  tz.TZDateTime _nextInstanceOf(String hhmm) {
    final now = tz.TZDateTime.now(tz.local);
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    var schedule = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!schedule.isAfter(now)) {
      schedule = schedule.add(const Duration(days: 1));
    }
    return schedule;
  }

  tz.TZDateTime _nextInstanceOfWeekday(int weekday, String hhmm) {
    final now = tz.TZDateTime.now(tz.local);
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    var diff = (weekday - now.weekday) % 7;
    if (diff < 0) diff += 7;

    final baseToday = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    var schedule = baseToday.add(Duration(days: diff));

    if (!schedule.isAfter(now)) {
      schedule = schedule.add(const Duration(days: 7));
    }
    return schedule;
  }
}

class _MinusOneHourSpec {
  final int dayShift;
  final String hhmm;

  const _MinusOneHourSpec({required this.dayShift, required this.hhmm});
}