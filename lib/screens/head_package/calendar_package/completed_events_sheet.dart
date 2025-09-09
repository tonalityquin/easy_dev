// lib/screens/head_package/calendar_package/completed_events_sheet.dart
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ 서비스계정 인증 유틸 (service_calendar_logic 대체)
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;

// ---- 서비스계정 JSON 경로(프로젝트에 맞게 유지/수정) ----
const String _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

/// 내부 저장 키
const String _kSheetIdKey = 'gsheet_spreadsheet_id';
const String _kSheetRangeKey = 'gsheet_range'; // 기본 '완료!A2'

// ---------------------------
// 인증/클라이언트 유틸 (service_calendar_logic 대체)
// ---------------------------

/// 작업별 필요 스코프 반환 (append에는 Sheets RW 필요)
List<String> _scopesFor(bool write) {
  if (write) {
    return <String>[
      gcal.CalendarApi.calendarScope, // 캘린더 RW (향후 확장 대비)
      'https://www.googleapis.com/auth/spreadsheets', // 시트 RW
    ];
  } else {
    return <String>[
      gcal.CalendarApi.calendarReadonlyScope, // 캘린더 RO
      'https://www.googleapis.com/auth/spreadsheets.readonly',
    ];
  }
}

/// 서비스 계정으로 인증된 HTTP 클라이언트
Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
  final jsonString = await rootBundle.loadString(_serviceAccountPath);
  final credentials = ServiceAccountCredentials.fromJson(jsonString);
  final scopes = _scopesFor(write);
  return clientViaServiceAccount(credentials, scopes);
}

// ---------------------------
// 완료 이벤트 바텀시트 UI & 로직
// ---------------------------

int _extractProgress(String? description) {
  final m = RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false).firstMatch(description ?? '');
  if (m == null) return 0;
  final v = int.tryParse(m.group(1) ?? '0') ?? 0;
  return v == 100 ? 100 : 0;
}

/// 완료된 이벤트 바텀시트(흰 배경) 오픈
///
/// [onEdit]를 넘기면 리스트 아이템 탭 시 수정 시트를 열 수 있어요.
Future<void> openCompletedEventsSheet({
  required BuildContext context,
  required List<gcal.Event> allEvents,
  void Function(BuildContext, gcal.Event)? onEdit,
}) async {
  final completed = allEvents.where((e) => _extractProgress(e.description) == 100).toList();

  DateTime _startOf(gcal.Event e) =>
      (e.start?.dateTime?.toLocal()) ?? (e.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0));

  completed.sort((a, b) => _startOf(a).compareTo(_startOf(b)));

  final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
  final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');
  final fmtTime = DateFormat('HH:mm');

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.white, // ✅ 흰색 고정
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
                      // 🗑️ 휴지통 버튼 (제목에 가장 가까운 위치)
                      IconButton(
                        tooltip: '완료 이벤트 삭제',
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        onPressed: () => _deleteCompletedEventsFromGoogleCalendar(
                          context,
                          completed,
                          // 필요 시 특정 캘린더를 지정하세요:
                          // calendarId: 'primary',
                        ),
                      ),
                      IconButton(
                        tooltip: '스프레드시트 저장',
                        icon: const Icon(Icons.upload, color: Colors.black87),
                        onPressed: () => _saveCompletedEventsToGoogleSheet(context, completed),
                      ),
                      IconButton(
                        tooltip: '스프레드시트 설정',
                        icon: const Icon(Icons.settings, color: Colors.black87),
                        onPressed: () => _openSpreadsheetConfigSheet(context),
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
                    child: Text(
                      '완료된 이벤트가 없습니다.',
                      style: TextStyle(color: Colors.black87),
                    ),
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
                        subtitle: Text(
                          when,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        onTap: onEdit != null ? () => onEdit(context, e) : null,
                        // ❌ 항목별 삭제 버튼은 없음 (헤더 휴지통으로 일괄 삭제)
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
}

/// 스프레드시트 설정(Spreadsheet ID / Range) 시트
Future<void> _openSpreadsheetConfigSheet(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();

  final idCtrl = TextEditingController(text: prefs.getString(_kSheetIdKey) ?? '');
  final rangeCtrl = TextEditingController(text: prefs.getString(_kSheetRangeKey) ?? '완료!A2');

  final idFocus = FocusNode();
  final rangeFocus = FocusNode();

  Future<void> save() async {
    await prefs.setString(_kSheetIdKey, idCtrl.text.trim());
    await prefs.setString(
      _kSheetRangeKey,
      (rangeCtrl.text.trim().isEmpty) ? '완료!A2' : rangeCtrl.text.trim(),
    );
    if (context.mounted) Navigator.pop(context);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스프레드시트 설정을 저장했습니다.')),
      );
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // ✅ 키보드 대응
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(ctx).unfocus(), // 바깥 터치로 키보드 닫기
        child: AnimatedPadding(
          // ✅ 키보드 높이만큼 시트 내용이 자연스럽게 올라감
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('스프레드시트 설정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                        child: ElevatedButton(
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
      );
    },
  );

  // 메모리 누수 방지
  idCtrl.dispose();
  rangeCtrl.dispose();
  idFocus.dispose();
  rangeFocus.dispose();
}

/// 완료된 이벤트들을 스프레드시트에 Append
Future<void> _saveCompletedEventsToGoogleSheet(
    BuildContext context,
    List<gcal.Event> completed,
    ) async {
  if (completed.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장할 완료 이벤트가 없습니다.')));
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  String spreadsheetId = prefs.getString(_kSheetIdKey) ?? '';
  String range = prefs.getString(_kSheetRangeKey) ?? '완료!A2';

  // 설정 없으면 먼저 설정 열기
  if (spreadsheetId.trim().isEmpty) {
    await _openSpreadsheetConfigSheet(context);
    spreadsheetId = prefs.getString(_kSheetIdKey) ?? '';
    range = prefs.getString(_kSheetRangeKey) ?? '완료!A2';
    if (spreadsheetId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스프레드시트 설정이 필요합니다.')));
      return;
    }
  }

  // 확인
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
              const Text('저장 확인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
    final client = await getAuthClient(write: true); // ✅ Sheets append에는 RW 스코프 필요
    final sheetsApi = sheets.SheetsApi(client);

    final dateOnly = DateFormat('yyyy-MM-dd');
    final values = completed.map((event) {
      final d = event.start?.date;
      final dt = event.start?.dateTime?.toLocal();
      final dateStr = (d != null) ? dateOnly.format(d) : (dt != null ? dateOnly.format(dt) : '');
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
  }
}

// ---------------------------
// 삭제 유틸 (휴지통 버튼 동작)
// ---------------------------

/// 가능한 calendarId 추론(없으면 null)
String? _guessCalendarId(List<gcal.Event> events) {
  for (final e in events) {
    final cand = e.organizer?.email ??
        e.creator?.email ??
        (e.attendees?.firstWhere(
              (a) => a.self == true && (a.email?.isNotEmpty ?? false),
          orElse: () => gcal.EventAttendee(),
        ).email);
    if (cand != null && cand.isNotEmpty) return cand;
  }
  return null;
}

/// 완료(progress:100) 이벤트 일괄 삭제
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

  // calendarId 없으면 추정 시도
  final calId = (calendarId ?? _guessCalendarId(completed));
  if (calId == null || calId.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('캘린더 ID를 확인할 수 없습니다. (organizer/creator 기반 추정 실패)')),
    );
    return;
  }

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
              const Text('삭제 확인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                '완료된 ${completed.length}개 이벤트를 캘린더에서 삭제할까요?\n이 작업은 되돌릴 수 없습니다.\n\nCalendar: $calId',
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
    final client = await getAuthClient(write: true); // 캘린더 RW 스코프 포함
    final api = gcal.CalendarApi(client);

    int success = 0;
    int failed = 0;

    // 순차 삭제
    for (final e in completed) {
      final id = e.id;
      if (id == null || id.isEmpty) {
        failed++;
        continue;
      }
      try {
        await api.events.delete(calId, id);
        success++;
      } catch (_) {
        failed++;
      }
    }

    if (context.mounted) {
      // 바텀시트 유지: 결과만 안내 (원하면 닫으려면 아래 주석 해제)
      // Navigator.maybePop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 완료: $success건 / 실패: $failed건')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }
}
