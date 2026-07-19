import '../../headquarter/widgets/calendar/google_calendar_service.dart';
import '../domain/sprint_models.dart';

class SprintCalendarSyncResult {
  const SprintCalendarSyncResult({
    required this.success,
    this.eventId,
    this.calendarId,
    this.calendarProfileId,
    this.error,
  });

  final bool success;
  final String? eventId;
  final String? calendarId;
  final String? calendarProfileId;
  final String? error;
}

class SprintCalendarSyncCoordinator {
  SprintCalendarSyncCoordinator({
    required GoogleCalendarService calendarService,
  }) : _calendarService = calendarService;

  final GoogleCalendarService _calendarService;

  Future<SprintCalendarSyncResult> upsertTask({
    required SprintTask task,
    required SprintScheduleBlock block,
    required SprintProject project,
    required SprintCalendarProfile profile,
    required SprintGoogleAccount account,
  }) async {
    final calendarId = profile.calendarId;
    try {
      final privateProperties = <String, String>{
        'source': 'parkinworkin_sprint',
        'sprintTaskId': task.id,
        'sprintProjectId': project.id,
        'sprintState': task.state.name,
        'sprintCalendarProfileId': profile.id,
        'sprintGoogleAccountId': account.id,
      };
      final description = task.description.trim();
      final stableEventId = task.hasGoogleEvent
          ? task.googleEventId!.trim()
          : _eventIdForTask(task.id);
      final sameRemote = task.hasGoogleEvent &&
          task.googleCalendarProfileId == profile.id &&
          task.googleCalendarId == calendarId;
      if (sameRemote) {
        try {
          final updated = await _calendarService.updateEvent(
            accountEmail: account.email,
            calendarId: calendarId,
            eventId: task.googleEventId!,
            summary: task.title,
            description: description,
            start: block.start,
            end: block.end,
            allDay: true,
            colorId: project.googleColorId,
            privateProperties: privateProperties,
          );
          return SprintCalendarSyncResult(
            success: true,
            eventId: updated.id ?? task.googleEventId,
            calendarId: calendarId,
            calendarProfileId: profile.id,
          );
        } catch (error) {
          if (!_isNotFound(error)) {
            return SprintCalendarSyncResult(
              success: false,
              eventId: task.googleEventId,
              calendarId: calendarId,
              calendarProfileId: profile.id,
              error: error.toString(),
            );
          }
        }
      }
      try {
        final created = await _calendarService.createEvent(
          accountEmail: account.email,
          calendarId: calendarId,
          summary: task.title,
          description: description,
          start: block.start,
          end: block.end,
          allDay: true,
          colorId: project.googleColorId,
          eventId: stableEventId,
          privateProperties: privateProperties,
        );
        return SprintCalendarSyncResult(
          success: true,
          eventId: created.id?.trim().isNotEmpty == true
              ? created.id!.trim()
              : stableEventId,
          calendarId: calendarId,
          calendarProfileId: profile.id,
        );
      } catch (error) {
        if (!_isConflict(error)) rethrow;
        final updated = await _calendarService.updateEvent(
          accountEmail: account.email,
          calendarId: calendarId,
          eventId: stableEventId,
          summary: task.title,
          description: description,
          start: block.start,
          end: block.end,
          allDay: true,
          colorId: project.googleColorId,
          privateProperties: privateProperties,
        );
        return SprintCalendarSyncResult(
          success: true,
          eventId: updated.id ?? stableEventId,
          calendarId: calendarId,
          calendarProfileId: profile.id,
        );
      }
    } catch (error) {
      final fallbackEventId = task.hasGoogleEvent
          ? task.googleEventId!.trim()
          : _eventIdForTask(task.id);
      return SprintCalendarSyncResult(
        success: false,
        eventId: fallbackEventId,
        calendarId: calendarId,
        calendarProfileId: profile.id,
        error: error.toString(),
      );
    }
  }

  Future<SprintCalendarSyncResult> deleteTaskEvent({
    required SprintTask task,
    required SprintCalendarProfile profile,
    required SprintGoogleAccount account,
  }) async {
    final eventId = task.googleEventId?.trim();
    if (eventId == null || eventId.isEmpty) {
      return SprintCalendarSyncResult(
        success: true,
        calendarId: profile.calendarId,
        calendarProfileId: profile.id,
      );
    }
    final calendarId = task.googleCalendarId?.trim().isNotEmpty == true
        ? task.googleCalendarId!.trim()
        : profile.calendarId;
    try {
      await _calendarService.deleteEvent(
        accountEmail: account.email,
        calendarId: calendarId,
        eventId: eventId,
      );
      return SprintCalendarSyncResult(
        success: true,
        calendarId: calendarId,
        calendarProfileId: profile.id,
      );
    } catch (error) {
      if (_isNotFound(error)) {
        return SprintCalendarSyncResult(
          success: true,
          eventId: eventId,
          calendarId: calendarId,
          calendarProfileId: profile.id,
        );
      }
      return SprintCalendarSyncResult(
        success: false,
        eventId: eventId,
        calendarId: calendarId,
        calendarProfileId: profile.id,
        error: error.toString(),
      );
    }
  }

  String _eventIdForTask(String taskId) {
    final normalized = taskId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-v0-9]'), '');
    if (normalized.length >= 5) return normalized;
    var hash = 2166136261;
    for (final value in taskId.codeUnits) {
      hash ^= value;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'sprint${hash.toRadixString(16).padLeft(8, '0')}';
  }

  bool _isNotFound(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('404') ||
        value.contains('not found') ||
        value.contains('notfound');
  }

  bool _isConflict(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('409') ||
        value.contains('already exists') ||
        value.contains('duplicate');
  }
}
