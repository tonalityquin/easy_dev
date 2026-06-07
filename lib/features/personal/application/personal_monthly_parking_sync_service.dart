import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../app/init/local_notifications.dart';
import '../../../shared/plate/domain/services/plate_status_record.dart';
import '../domain/models/personal_calendar_event.dart';
import '../domain/models/personal_saved_vehicle.dart';
import '../domain/models/personal_todo_item.dart';
import 'personal_calendar_store.dart';
import 'personal_todo_store.dart';

class PersonalMonthlyParkingSyncService {
  static const String _channelId = 'ParkinWorkin_reminders';
  static const String _channelName = '근무 리마인더';
  static const String _channelDesc = '개인형 월주차 만료 알림 채널';
  static const String _prefixHead = 'monthly';

  Future<void> syncVehicleMonthlyParking({
    required PersonalSavedVehicle vehicle,
    required PlateStatusRecord? record,
    required PersonalCalendarStore calendarStore,
    required PersonalTodoStore todoStore,
  }) async {
    final prefix = _vehiclePrefix(vehicle);
    if (record == null) {
      await _removeCalendarEvents(calendarStore, prefix);
      await _removeTodos(todoStore, prefix);
      await _cancelReminder(prefix);
      return;
    }

    final now = DateTime.now();
    await _syncCalendarEvents(
      vehicle: vehicle,
      record: record,
      calendarStore: calendarStore,
      prefix: prefix,
      now: now,
    );
    await _syncExpireReminderTodo(
      vehicle: vehicle,
      record: record,
      todoStore: todoStore,
      prefix: prefix,
      now: now,
    );
  }

  Future<void> _syncCalendarEvents({
    required PersonalSavedVehicle vehicle,
    required PlateStatusRecord record,
    required PersonalCalendarStore calendarStore,
    required String prefix,
    required DateTime now,
  }) async {
    final current = List<PersonalCalendarEvent>.of(await calendarStore.load());
    final existing = <String, PersonalCalendarEvent>{
      for (final event in current.where((e) => e.id.startsWith(prefix))) event.id: event,
    };
    final retained = current.where((event) => !event.id.startsWith(prefix)).toList(growable: true);
    final generated = <PersonalCalendarEvent>[];
    final plate = vehicle.displayPlate;
    final start = _parseDate(record.startDate);
    final end = _parseDate(record.endDate);

    if (start != null) {
      generated.add(_event(
        id: '${prefix}start',
        existing: existing['${prefix}start'],
        title: '$plate 월주차 시작',
        plateNumber: vehicle.displayPlate,
        note: _rangeNote(record),
        date: start,
        now: now,
      ));
    }

    if (end != null) {
      generated.add(_event(
        id: '${prefix}end',
        existing: existing['${prefix}end'],
        title: '$plate 월주차 만료',
        plateNumber: vehicle.displayPlate,
        note: _rangeNote(record),
        date: end,
        now: now,
      ));
    }

    for (var i = 0; i < record.paymentHistory.length; i++) {
      final payment = record.paymentHistory[i];
      final paidAt = _paymentDate(payment);
      if (paidAt == null) continue;
      final id = '${prefix}payment:${_paymentKey(payment, i)}';
      generated.add(_event(
        id: id,
        existing: existing[id],
        title: '$plate 월주차 결제',
        plateNumber: vehicle.displayPlate,
        note: _paymentNote(payment),
        date: paidAt,
        now: now,
      ));
    }

    retained.addAll(generated);
    await calendarStore.saveAll(retained);
  }

  Future<void> _syncExpireReminderTodo({
    required PersonalSavedVehicle vehicle,
    required PlateStatusRecord record,
    required PersonalTodoStore todoStore,
    required String prefix,
    required DateTime now,
  }) async {
    final current = List<PersonalTodoItem>.of(await todoStore.load());
    final id = '${prefix}expire-reminder';
    final existing = current.where((todo) => todo.id == id).firstOrNull;
    final retained = current.where((todo) => !todo.id.startsWith(prefix)).toList(growable: true);
    final end = _parseDate(record.endDate);

    if (end == null) {
      await todoStore.saveAll(retained);
      await _cancelReminder(prefix);
      return;
    }

    final dueDate = DateTime(end.year, end.month, end.day).subtract(const Duration(days: 7));
    final title = '${vehicle.displayPlate} 월주차 만료 7일 전 확인';
    final existingDueDate = existing?.dueDate;
    final dueChanged = existingDueDate == null || !_sameDay(existingDueDate, dueDate);
    final previousDone = existing?.done ?? false;
    final previousCreatedAt = existing?.createdAt ?? now;
    retained.insert(
      0,
      PersonalTodoItem(
        id: id,
        title: title,
        plateNumber: vehicle.displayPlate,
        dueDate: dueDate,
        done: dueChanged ? false : previousDone,
        createdAt: previousCreatedAt,
        updatedAt: now,
      ),
    );
    await todoStore.saveAll(retained);
    await _scheduleReminder(
      prefix: prefix,
      plateNumber: vehicle.displayPlate,
      endDate: end,
      reminderDate: dueDate,
    );
  }

  PersonalCalendarEvent _event({
    required String id,
    required PersonalCalendarEvent? existing,
    required String title,
    required String plateNumber,
    required String note,
    required DateTime date,
    required DateTime now,
  }) {
    return PersonalCalendarEvent(
      id: id,
      title: title,
      plateNumber: plateNumber,
      note: note,
      date: DateTime(date.year, date.month, date.day),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _removeCalendarEvents(PersonalCalendarStore store, String prefix) async {
    final retained = List<PersonalCalendarEvent>.of(await store.load())..removeWhere((event) => event.id.startsWith(prefix));
    await store.saveAll(retained);
  }

  Future<void> _removeTodos(PersonalTodoStore store, String prefix) async {
    final retained = List<PersonalTodoItem>.of(await store.load())..removeWhere((todo) => todo.id.startsWith(prefix));
    await store.saveAll(retained);
  }

  Future<void> _scheduleReminder({
    required String prefix,
    required String plateNumber,
    required DateTime endDate,
    required DateTime reminderDate,
  }) async {
    final scheduleAt = DateTime(reminderDate.year, reminderDate.month, reminderDate.day, 9);
    final id = _notificationId(prefix);
    if (!scheduleAt.isAfter(DateTime.now())) {
      await _cancelNotification(id);
      return;
    }

    try {
      await LocalNotifications.ensureInitialized();
      final permission = await LocalNotifications.requestPermission();
      if (permission == false) return;
      final when = tz.TZDateTime.from(scheduleAt, tz.local);

      Future<void> run(AndroidScheduleMode mode) async {
        await LocalNotifications.plugin.zonedSchedule(
          id,
          '월주차 만료 7일 전',
          '$plateNumber 월주차가 ${_formatDate(endDate)} 만료됩니다.',
          when,
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
          androidScheduleMode: mode,
          payload: 'personal_monthly_expire:$plateNumber',
        );
      }

      await LocalNotifications.plugin.cancel(id);
      try {
        await run(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        await run(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    } catch (_) {}
  }

  Future<void> _cancelReminder(String prefix) async {
    await _cancelNotification(_notificationId(prefix));
  }

  Future<void> _cancelNotification(int id) async {
    try {
      await LocalNotifications.ensureInitialized();
      await LocalNotifications.plugin.cancel(id);
    } catch (_) {}
  }

  String _vehiclePrefix(PersonalSavedVehicle vehicle) {
    return '$_prefixHead:${_safeSegment(vehicle.id)}:';
  }

  String _safeSegment(String value) {
    return value.trim().replaceAll(RegExp(r'[^0-9A-Za-z가-힣_-]'), '_');
  }

  int _notificationId(String prefix) {
    var hash = 0x1868;
    for (final unit in prefix.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return 186800000 + (hash % 100000000);
  }

  DateTime? _parseDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final normalized = text.replaceAll('.', '-').replaceAll('/', '-');
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return DateTime(direct.year, direct.month, direct.day);
    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  DateTime? _paymentDate(PlateStatusPaymentRecord payment) {
    if (payment.paidAt != null) {
      final d = payment.paidAt!.toLocal();
      return DateTime(d.year, d.month, d.day);
    }
    final raw = (payment.paidAtRaw ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return _parseDate(raw);
    final d = parsed.toLocal();
    return DateTime(d.year, d.month, d.day);
  }

  String _paymentKey(PlateStatusPaymentRecord payment, int index) {
    final raw = (payment.paidAtRaw ?? payment.paidAt?.toIso8601String() ?? '').trim();
    final amount = (payment.amountText ?? '').trim();
    final base = '$raw|$amount|$index';
    return _safeSegment(base.isEmpty ? index.toString() : base);
  }

  String _rangeNote(PlateStatusRecord record) {
    final start = (record.startDate ?? '').trim();
    final end = (record.endDate ?? '').trim();
    if (start.isEmpty && end.isEmpty) return '월주차 기간 정보';
    if (start.isEmpty) return '만료일 $end';
    if (end.isEmpty) return '시작일 $start';
    return '$start ~ $end';
  }

  String _paymentNote(PlateStatusPaymentRecord payment) {
    final amount = (payment.amountText ?? '').trim();
    final extended = (payment.extendedText ?? '').trim();
    final parts = <String>[];
    if (amount.isNotEmpty) parts.add('금액 $amount');
    if (extended.isNotEmpty) parts.add('연장 $extended');
    return parts.isEmpty ? '월주차 결제' : parts.join(' · ');
  }

  String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)}';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
