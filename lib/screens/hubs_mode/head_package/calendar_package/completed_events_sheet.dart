// lib/screens/head_package/calendar_package/completed_events_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/google_auth_session.dart';
import '../../dev_package/debug_package/debug_api_logger.dart';

// 내부 저장 키
const String _kSheetIdKey = 'gsheet_spreadsheet_id';
const String _kSheetRangeKey = 'gsheet_range'; // 기본 '완료!A2'

// ─────────────────────────────────────────────────────────────
// ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
// ─────────────────────────────────────────────────────────────
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
  } catch (_) {
    // 로깅 실패는 기능에 영향 없도록 무시
  }
}

// 완료/진행률 파싱: 예) "[progress:100]" 이면 100 반환
int _extractProgress(String? description) {
  final m = RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false)
      .firstMatch(description ?? '');
  if (m == null) return 0;
  final v = int.tryParse(m.group(1) ?? '0') ?? 0;
  return v == 100 ? 100 : 0;
}

/// 완료된 이벤트 바텀시트(흰 배경) 오픈
Future<void> openCompletedEventsSheet({
  required BuildContext context,
  required List<gcal.Event> allEvents,
  void Function(BuildContext, gcal.Event)? onEdit,
}) async {
  // 1) 완료 이벤트 필터
  final completed = allEvents.where((e) => _extractProgress(e.description) == 100).toList();

  DateTime _startOf(gcal.Event e) =>
      (e.start?.dateTime?.toLocal()) ?? (e.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0));
  completed.sort((a, b) => _startOf(a).compareTo(_startOf(b)));

  // 2) 포맷터
  final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
  final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');
  final fmtTime = DateFormat('HH:mm');

  // 3) 바텀시트 UI
  try {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ===== 헤더 + 액션 =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '완료된 이벤트 (${completed.length})',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),

                        // 🗑️ 완료 이벤트 삭제(캘린더)
                        IconButton(
                          tooltip: '완료 이벤트 삭제',
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          onPressed: () async {
                            try {
                              await _deleteCompletedEventsFromGoogleCalendar(context, completed);
                            } catch (e) {
                              // 하위에서 로깅하지만, UI 호출 레벨에서도 안전하게 방어
                              await _logApiError(
                                tag: 'openCompletedEventsSheet.deleteTap',
                                message: '완료 이벤트 삭제 버튼 처리 실패',
                                error: e,
                                extra: <String, dynamic>{'count': completed.length},
                                tags: const <String>[_tCal, _tCalUi, _tCalCompleted, _tCalGcal],
                              );
                            }
                          },
                        ),

                        // ⬆️ 시트로 저장
                        IconButton(
                          tooltip: '스프레드시트 저장',
                          icon: const Icon(Icons.upload, color: Colors.black87),
                          onPressed: () async {
                            try {
                              await _saveCompletedEventsToGoogleSheet(context, completed);
                            } catch (e) {
                              await _logApiError(
                                tag: 'openCompletedEventsSheet.saveTap',
                                message: '스프레드시트 저장 버튼 처리 실패',
                                error: e,
                                extra: <String, dynamic>{'count': completed.length},
                                tags: const <String>[_tCal, _tCalUi, _tCalCompleted, _tCalSheet],
                              );
                            }
                          },
                        ),

                        // ⚙️ 시트 설정
                        IconButton(
                          tooltip: '스프레드시트 설정',
                          icon: const Icon(Icons.settings, color: Colors.black87),
                          onPressed: () async {
                            try {
                              await _openSpreadsheetConfigSheet(context);
                            } catch (e) {
                              await _logApiError(
                                tag: 'openCompletedEventsSheet.configTap',
                                message: '스프레드시트 설정 시트 오픈 실패',
                                error: e,
                                tags: const <String>[_tCal, _tCalUi, _tCalPrefs],
                              );
                            }
                          },
                        ),

                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black87),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0x14000000)),

                  // ===== 목록 =====
                  Expanded(
                    child: completed.isEmpty
                        ? const Center(
                      child: Text('완료된 이벤트가 없습니다.', style: TextStyle(color: Colors.black87)),
                    )
                        : ListView.separated(
                      controller: controller,
                      itemCount: completed.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = completed[i];
                        final isAllDay = (e.start?.date != null) && (e.start?.dateTime == null);

                        final startUtc = e.start?.dateTime;
                        final startLocal = (startUtc != null) ? startUtc.toLocal() : e.start?.date;

                        final endUtc = e.end?.dateTime;
                        final endLocal = (endUtc != null) ? endUtc.toLocal() : e.end?.date;

                        String when;
                        if (startLocal == null) {
                          when = '(시작 시간 미정)';
                        } else if (isAllDay) {
                          when = fmtDate.format(startLocal);
                        } else if (endLocal != null) {
                          when = '${fmtDateTime.format(startLocal)} ~ ${fmtTime.format(endLocal)}';
                        } else {
                          when = fmtDateTime.format(startLocal);
                        }

                        return ListTile(
                          leading: const Icon(Icons.done, color: Colors.red),
                          title: Text(
                            e.summary ?? '(제목 없음)',
                            style: const TextStyle(
                              color: Colors.black87,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          subtitle: Text(when, style: const TextStyle(color: Colors.black54)),
                          onTap: onEdit != null ? () => onEdit(context, e) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
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

/// 시트 설정(Spreadsheet ID / Range)
Future<void> _openSpreadsheetConfigSheet(BuildContext context) async {
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

  final idCtrl = TextEditingController(text: prefs.getString(_kSheetIdKey) ?? '');
  final rangeCtrl = TextEditingController(text: prefs.getString(_kSheetRangeKey) ?? '완료!A2');
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스프레드시트 설정을 저장했습니다.')),
      );
    }
  }

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(ctx).unfocus(),
          child: AnimatedPadding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '스프레드시트 설정',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),

                    // Spreadsheet ID
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: idCtrl,
                      builder: (context, value, _) {
                        return TextField(
                          controller: idCtrl,
                          focusNode: idFocus,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => rangeFocus.requestFocus(),
                          decoration: InputDecoration(
                            labelText: 'Spreadsheet ID',
                            hintText: '예: 1fjN8k...(URL 중간의 ID)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: value.text.isNotEmpty
                                ? IconButton(
                              tooltip: '지우기',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                idCtrl.clear();
                                idFocus.requestFocus();
                              },
                            )
                                : null,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 10),

                    // Range
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: rangeCtrl,
                      builder: (context, value, _) {
                        return TextField(
                          controller: rangeCtrl,
                          focusNode: rangeFocus,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => save(),
                          decoration: InputDecoration(
                            labelText: 'Range',
                            hintText: '예: 완료!A2',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: value.text.isNotEmpty
                                ? IconButton(
                              tooltip: '지우기',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                rangeCtrl.clear();
                                rangeFocus.requestFocus();
                              },
                            )
                                : null,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(onPressed: save, child: const Text('저장')),
                        ),
                      ],
                    ),
                  ],
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

/// 완료된 이벤트들을 Google Sheet에 Append
Future<void> _saveCompletedEventsToGoogleSheet(
    BuildContext context,
    List<gcal.Event> completed,
    ) async {
  if (completed.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('저장할 완료 이벤트가 없습니다.')),
    );
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
    return;
  }

  String spreadsheetId = prefs.getString(_kSheetIdKey) ?? '';
  String range = prefs.getString(_kSheetRangeKey) ?? '완료!A2';

  // 설정 없으면 먼저 설정 시트
  if (spreadsheetId.trim().isEmpty) {
    await _openSpreadsheetConfigSheet(context);
    spreadsheetId = prefs.getString(_kSheetIdKey) ?? '';
    range = prefs.getString(_kSheetRangeKey) ?? '완료!A2';
    if (spreadsheetId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스프레드시트 설정이 필요합니다.')),
      );
      return;
    }
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('저장 확인',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                '완료된 ${completed.length}개 이벤트를\n스프레드시트로 저장할까요?\n\nID: $spreadsheetId\nRange: $range',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('저장'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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
      final dateStr = (d != null) ? fmt.format(d) : (dt != null ? fmt.format(dt) : '');
      // ✅ 민감정보 최소화 옵션이 필요하면 description 제외 가능
      return [dateStr, event.summary ?? '', event.description ?? ''];
    }).toList();

    final body = sheets.ValueRange.fromJson({"values": values});
    await sheetsApi.spreadsheets.values.append(
      body,
      spreadsheetId,
      range,
      valueInputOption: 'USER_ENTERED',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Sheet에 저장 완료')),
      );
    }
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

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }
}

/// 완료된 이벤트들을 Google Calendar에서 일괄 삭제
Future<void> _deleteCompletedEventsFromGoogleCalendar(
    BuildContext context,
    List<gcal.Event> completed, {
      String? calendarId,
    }) async {
  if (completed.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('삭제할 완료 이벤트가 없습니다.')),
    );
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
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('삭제 확인',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                '완료된 ${completed.length}개 이벤트를 캘린더에서 삭제할까요?\n'
                    '이 작업은 되돌릴 수 없습니다.\n\nCalendar: $calId',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('삭제'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  ) ??
      false;

  if (!ok) return;

  try {
    final client = await GoogleAuthSession.instance.safeClient();
    final api = gcal.CalendarApi(client);

    int success = 0;
    int failed = 0;

    for (final e in completed) {
      final id = e.id;
      if (id == null || id.isEmpty) {
        failed++;
        continue;
      }
      try {
        await api.events.delete(calId, id);
        success++;
      } catch (inner) {
        failed++;
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

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 완료: $success건 / 실패: $failed건')),
      );
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

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }
}
