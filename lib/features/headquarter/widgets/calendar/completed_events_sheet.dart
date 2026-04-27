import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/auth/google_auth_session.dart';
import '../../../dev/debug/debug_api_logger.dart';

const String _kSheetIdKey = 'gsheet_spreadsheet_id';
const String _kSheetRangeKey = 'gsheet_range';

const String _tCal = 'calendar';
const String _tCalUi = 'calendar/ui';
const String _tCalCompleted = 'calendar/completed';
const String _tCalSheet = 'calendar/sheets';
const String _tCalGcal = 'calendar/gcal';
const String _tCalPrefs = 'calendar/prefs';

Future<void> _logApiError({
  required String tag,
  required String message,
  required Object error,
  Map<String, dynamic>? extra,
  List<String>? tags,
}) async {
  try {
    await DebugApiLogger().log(
      <String, dynamic>{
        'tag': tag,
        'message': message,
        'error': error.toString(),
        if (extra != null) 'extra': extra,
      },
      level: 'error',
      tags: tags,
    );
  } catch (_) {}
}

@immutable
class _CompletedTokens {
  const _CompletedTokens({
    required this.accent,
    required this.onAccent,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.divider,
    required this.error,
    required this.scrim,
    required this.handle,
    required this.fieldFill,
    required this.fieldBorder,
    required this.cardTint,
  });

  final Color accent;
  final Color onAccent;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color divider;
  final Color error;
  final Color scrim;
  final Color handle;
  final Color fieldFill;
  final Color fieldBorder;
  final Color cardTint;

  factory _CompletedTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final surface = cs.surface;

    return _CompletedTokens(
      accent: accent,
      onAccent: cs.onPrimary,
      surface: surface,
      onSurface: cs.onSurface,
      onSurfaceVariant: cs.onSurfaceVariant,
      divider: cs.outlineVariant,
      error: cs.error,
      scrim: cs.scrim,
      handle: cs.onSurfaceVariant.withOpacity(0.42),
      fieldFill: Color.alphaBlend(accent.withOpacity(0.10), cs.surface),
      fieldBorder: cs.outlineVariant.withOpacity(0.75),
      cardTint: Color.alphaBlend(accent.withOpacity(0.08), cs.surface),
    );
  }
}

int _extractProgress(String? description) {
  final m = RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false)
      .firstMatch(description ?? '');
  if (m == null) return 0;
  final v = int.tryParse(m.group(1) ?? '0') ?? 0;
  return v == 100 ? 100 : 0;
}

Future<void> openCompletedEventsSheet({
  required BuildContext context,
  required List<gcal.Event> allEvents,
  void Function(BuildContext, gcal.Event)? onEdit,
}) async {
  final tokens = _CompletedTokens.of(context);
  final completed =
      allEvents.where((e) => _extractProgress(e.description) == 100).toList();

  DateTime _startOf(gcal.Event e) =>
      (e.start?.dateTime?.toLocal()) ??
      (e.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0));

  completed.sort((a, b) => _startOf(a).compareTo(_startOf(b)));

  final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
  final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');
  final fmtTime = DateFormat('HH:mm');

  try {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: tokens.scrim.withOpacity(0.60),
      builder: (sheetCtx) {
        return _FullSheetFrame(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (ctx, controller) {
              final t = _CompletedTokens.of(ctx);

              return Material(
                color: t.surface,
                surfaceTintColor: Colors.transparent,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.handle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '완료된 이벤트 (${completed.length})',
                              style:
                                  Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: t.onSurface,
                                      ),
                            ),
                          ),
                          IconButton(
                            tooltip: '완료 이벤트 삭제',
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: t.error,
                            ),
                            onPressed: () async {
                              try {
                                await _deleteCompletedEventsFromGoogleCalendar(
                                  ctx,
                                  completed,
                                );
                              } catch (e) {
                                await _logApiError(
                                  tag: 'openCompletedEventsSheet.deleteTap',
                                  message: '완료 이벤트 삭제 버튼 처리 실패',
                                  error: e,
                                  extra: <String, dynamic>{
                                    'count': completed.length,
                                  },
                                  tags: const <String>[
                                    _tCal,
                                    _tCalUi,
                                    _tCalCompleted,
                                    _tCalGcal,
                                  ],
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: '스프레드시트 저장',
                            icon:
                                Icon(Icons.upload_rounded, color: t.onSurface),
                            onPressed: () async {
                              try {
                                await _saveCompletedEventsToGoogleSheet(
                                    ctx, completed);
                              } catch (e) {
                                await _logApiError(
                                  tag: 'openCompletedEventsSheet.saveTap',
                                  message: '스프레드시트 저장 버튼 처리 실패',
                                  error: e,
                                  extra: <String, dynamic>{
                                    'count': completed.length,
                                  },
                                  tags: const <String>[
                                    _tCal,
                                    _tCalUi,
                                    _tCalCompleted,
                                    _tCalSheet,
                                  ],
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: '스프레드시트 설정',
                            icon: Icon(Icons.settings_rounded,
                                color: t.onSurface),
                            onPressed: () async {
                              try {
                                await _openSpreadsheetConfigSheet(ctx);
                              } catch (e) {
                                await _logApiError(
                                  tag: 'openCompletedEventsSheet.configTap',
                                  message: '스프레드시트 설정 시트 오픈 실패',
                                  error: e,
                                  tags: const <String>[
                                    _tCal,
                                    _tCalUi,
                                    _tCalPrefs
                                  ],
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: '닫기',
                            icon: Icon(Icons.close_rounded, color: t.onSurface),
                            onPressed: () => Navigator.of(ctx).maybePop(),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: t.divider),
                    Expanded(
                      child: completed.isEmpty
                          ? Center(
                              child: Text(
                                '완료된 이벤트가 없습니다.',
                                style: TextStyle(color: t.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              itemCount: completed.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: t.divider),
                              itemBuilder: (context, i) {
                                final e = completed[i];
                                final isAllDay = (e.start?.date != null) &&
                                    (e.start?.dateTime == null);

                                final startUtc = e.start?.dateTime;
                                final startLocal = (startUtc != null)
                                    ? startUtc.toLocal()
                                    : e.start?.date;

                                final endUtc = e.end?.dateTime;
                                final endLocal = (endUtc != null)
                                    ? endUtc.toLocal()
                                    : e.end?.date;

                                String when;
                                if (startLocal == null) {
                                  when = '(시작 시간 미정)';
                                } else if (isAllDay) {
                                  when = fmtDate.format(startLocal);
                                } else if (endLocal != null) {
                                  when =
                                      '${fmtDateTime.format(startLocal)} ~ ${fmtTime.format(endLocal)}';
                                } else {
                                  when = fmtDateTime.format(startLocal);
                                }

                                return ListTile(
                                  leading:
                                      Icon(Icons.done_rounded, color: t.accent),
                                  title: Text(
                                    e.summary ?? '(제목 없음)',
                                    style: TextStyle(
                                      color: t.onSurface,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  subtitle: Text(
                                    when,
                                    style: TextStyle(color: t.onSurfaceVariant),
                                  ),
                                  onTap: onEdit != null
                                      ? () => onEdit(context, e)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  } catch (e) {
    await _logApiError(
      tag: 'openCompletedEventsSheet',
      message: '완료 이벤트 바텀시트(showModalBottomSheet) 오픈 실패',
      error: e,
      extra: <String, dynamic>{
        'allEvents': allEvents.length,
        'completed': completed.length,
      },
      tags: const <String>[_tCal, _tCalUi, _tCalCompleted],
    );
  }
}

class _FullSheetFrame extends StatelessWidget {
  const _FullSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = _CompletedTokens.of(context);

    return FractionallySizedBox(
      heightFactor: 1.0,
      widthFactor: 1.0,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  spreadRadius: 8,
                  color: t.scrim.withOpacity(0.18),
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openSpreadsheetConfigSheet(BuildContext context) async {
  final tokens = _CompletedTokens.of(context);

  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    await _logApiError(
      tag: '_openSpreadsheetConfigSheet',
      message: 'SharedPreferences.getInstance 실패',
      error: e,
      tags: const <String>[_tCal, _tCalPrefs],
    );
    rethrow;
  }

  final idCtrl =
      TextEditingController(text: prefs.getString(_kSheetIdKey) ?? '');
  final rangeCtrl =
      TextEditingController(text: prefs.getString(_kSheetRangeKey) ?? '완료!A2');
  final idFocus = FocusNode();
  final rangeFocus = FocusNode();

  Future<void> save() async {
    try {
      await prefs.setString(_kSheetIdKey, idCtrl.text.trim());
      await prefs.setString(
        _kSheetRangeKey,
        (rangeCtrl.text.trim().isEmpty) ? '완료!A2' : rangeCtrl.text.trim(),
      );
    } catch (e) {
      await _logApiError(
        tag: '_openSpreadsheetConfigSheet.save',
        message: '스프레드시트 설정 저장 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{
          'idLen': idCtrl.text.trim().length,
          'range': rangeCtrl.text.trim(),
        },
        tags: const <String>[_tCal, _tCalPrefs],
      );
      rethrow;
    }

    if (context.mounted) Navigator.pop(context);
  }

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: tokens.scrim.withOpacity(0.60),
      builder: (ctx) {
        final t = _CompletedTokens.of(ctx);

        InputDecoration deco({
          required String label,
          required String hint,
          required TextEditingController controller,
          required FocusNode focusNode,
          FocusNode? nextFocus,
          required VoidCallback onClear,
        }) {
          return InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true,
            fillColor: t.fieldFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.accent, width: 1.2),
            ),
            isDense: true,
            prefixIcon: Icon(Icons.link_rounded, color: t.accent),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, __) {
                if (v.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  tooltip: '지우기',
                  icon: Icon(Icons.clear_rounded, color: t.onSurfaceVariant),
                  onPressed: () {
                    onClear();
                    focusNode.requestFocus();
                  },
                );
              },
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(ctx).unfocus(),
          child: AnimatedPadding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        spreadRadius: 8,
                        color: t.scrim.withOpacity(0.18),
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      color: t.surface,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: t.handle,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '스프레드시트 설정',
                              style:
                                  Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: t.onSurface,
                                      ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: idCtrl,
                              focusNode: idFocus,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => rangeFocus.requestFocus(),
                              decoration: deco(
                                label: 'Spreadsheet ID',
                                hint: '예: 1fjN8k...(URL 중간의 ID)',
                                controller: idCtrl,
                                focusNode: idFocus,
                                nextFocus: rangeFocus,
                                onClear: () => idCtrl.clear(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: rangeCtrl,
                              focusNode: rangeFocus,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => save(),
                              decoration: deco(
                                label: 'Range',
                                hint: '예: 완료!A2',
                                controller: rangeCtrl,
                                focusNode: rangeFocus,
                                onClear: () => rangeCtrl.clear(),
                              ).copyWith(
                                prefixIcon: Icon(Icons.grid_on_rounded,
                                    color: t.accent),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: t.onSurface,
                                      side: BorderSide(
                                          color: t.divider.withOpacity(0.85)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('취소'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: t.accent,
                                      foregroundColor: t.onAccent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: save,
                                    child: const Text('저장'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  } catch (e) {
    await _logApiError(
      tag: '_openSpreadsheetConfigSheet',
      message: '스프레드시트 설정 시트(showModalBottomSheet) 오픈 실패',
      error: e,
      tags: const <String>[_tCal, _tCalUi, _tCalPrefs],
    );
  } finally {
    idCtrl.dispose();
    rangeCtrl.dispose();
    idFocus.dispose();
    rangeFocus.dispose();
  }
}

Future<void> _saveCompletedEventsToGoogleSheet(
  BuildContext context,
  List<gcal.Event> completed,
) async {
  if (completed.isEmpty) {
    return;
  }

  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    await _logApiError(
      tag: '_saveCompletedEventsToGoogleSheet',
      message: 'SharedPreferences.getInstance 실패',
      error: e,
      tags: const <String>[_tCal, _tCalPrefs],
    );
    return;
  }

  String spreadsheetId = prefs.getString(_kSheetIdKey) ?? '';
  String range = prefs.getString(_kSheetRangeKey) ?? '완료!A2';

  if (spreadsheetId.trim().isEmpty) {
    await _openSpreadsheetConfigSheet(context);
    spreadsheetId = prefs.getString(_kSheetIdKey) ?? '';
    range = prefs.getString(_kSheetRangeKey) ?? '완료!A2';
    if (spreadsheetId.trim().isEmpty) {
      return;
    }
  }

  final ok = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: _CompletedTokens.of(context).scrim.withOpacity(0.60),
        builder: (ctx) {
          final t = _CompletedTokens.of(ctx);
          return _ConfirmSheetFrame(
            title: '저장 확인',
            body: Text(
              '완료된 ${completed.length}개 이벤트를\n스프레드시트로 저장할까요?\n\nID: $spreadsheetId\nRange: $range',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.onSurface),
            ),
            cancelLabel: '취소',
            confirmLabel: '저장',
            confirmColor: t.accent,
            confirmFg: t.onAccent,
          );
        },
      ) ??
      false;

  if (!ok) return;

  try {
    final client = await GoogleAuthSession.instance.safeClient();
    final sheetsApi = sheets.SheetsApi(client);
    final fmt = DateFormat('yyyy-MM-dd');

    final values = completed.map((event) {
      final d = event.start?.date;
      final dt = event.start?.dateTime?.toLocal();
      final dateStr =
          (d != null) ? fmt.format(d) : (dt != null ? fmt.format(dt) : '');
      return [dateStr, event.summary ?? '', event.description ?? ''];
    }).toList();

    final body = sheets.ValueRange.fromJson({"values": values});
    await sheetsApi.spreadsheets.values.append(
      body,
      spreadsheetId,
      range,
      valueInputOption: 'USER_ENTERED',
    );
  } catch (e) {
    await _logApiError(
      tag: '_saveCompletedEventsToGoogleSheet',
      message: 'Google Sheets append 실패',
      error: e,
      extra: <String, dynamic>{
        'spreadsheetIdLen': spreadsheetId.trim().length,
        'range': range,
        'count': completed.length,
      },
      tags: const <String>[_tCal, _tCalSheet, _tCalCompleted],
    );
  }
}

Future<void> _deleteCompletedEventsFromGoogleCalendar(
  BuildContext context,
  List<gcal.Event> completed, {
  String? calendarId,
}) async {
  if (completed.isEmpty) {
    return;
  }

  String? _guessCalendarId(List<gcal.Event> events) {
    for (final e in events) {
      final cand = e.organizer?.email ??
          e.creator?.email ??
          (e.attendees
              ?.firstWhere(
                (a) => a.self == true && (a.email?.isNotEmpty ?? false),
                orElse: () => gcal.EventAttendee(),
              )
              .email);
      if (cand != null && cand.isNotEmpty) return cand;
    }
    return null;
  }

  final calId = (calendarId ?? _guessCalendarId(completed)) ?? 'primary';

  final ok = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: _CompletedTokens.of(context).scrim.withOpacity(0.60),
        builder: (ctx) {
          final t = _CompletedTokens.of(ctx);
          return _ConfirmSheetFrame(
            title: '삭제 확인',
            body: Text(
              '완료된 ${completed.length}개 이벤트를 캘린더에서 삭제할까요?\n이 작업은 되돌릴 수 없습니다.\n\nCalendar: $calId',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.onSurface),
            ),
            cancelLabel: '취소',
            confirmLabel: '삭제',
            confirmColor: t.error,
            confirmFg: Theme.of(ctx).colorScheme.onError,
          );
        },
      ) ??
      false;

  if (!ok) return;

  try {
    final client = await GoogleAuthSession.instance.safeClient();
    final api = gcal.CalendarApi(client);

    for (final e in completed) {
      final id = e.id;
      if (id == null || id.isEmpty) {
        continue;
      }
      try {
        await api.events.delete(calId, id);
      } catch (inner) {
        await _logApiError(
          tag: '_deleteCompletedEventsFromGoogleCalendar.item',
          message: '이벤트 삭제 실패(개별)',
          error: inner,
          extra: <String, dynamic>{
            'calendarId': calId,
            'eventId': id,
          },
          tags: const <String>[_tCal, _tCalGcal, _tCalCompleted],
        );
      }
    }
  } catch (e) {
    await _logApiError(
      tag: '_deleteCompletedEventsFromGoogleCalendar',
      message: 'CalendarApi delete 일괄 처리 실패(상위)',
      error: e,
      extra: <String, dynamic>{
        'calendarId': calId,
        'count': completed.length,
      },
      tags: const <String>[_tCal, _tCalGcal, _tCalCompleted],
    );
  }
}

class _ConfirmSheetFrame extends StatelessWidget {
  const _ConfirmSheetFrame({
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.confirmColor,
    required this.confirmFg,
  });

  final String title;
  final Widget body;
  final String cancelLabel;
  final String confirmLabel;
  final Color confirmColor;
  final Color confirmFg;

  @override
  Widget build(BuildContext context) {
    final t = _CompletedTokens.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 8,
                color: t.scrim.withOpacity(0.18),
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: t.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.handle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: t.onSurface,
                          ),
                    ),
                    const SizedBox(height: 12),
                    body,
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.onSurface,
                              side: BorderSide(
                                  color: t.divider.withOpacity(0.85)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(cancelLabel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: confirmColor,
                              foregroundColor: confirmFg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(confirmLabel),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
