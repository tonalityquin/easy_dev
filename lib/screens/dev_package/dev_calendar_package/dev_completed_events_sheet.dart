import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

// ✅ 중앙 인증 세션(google_sign_in v7 대응)만 사용합니다.
//   개별 화면/기능에서는 절대 authenticate/authorizeScopes를 호출하지 않습니다.
import 'package:easydev/utils/google_auth_session.dart';

// 스낵바 헬퍼(프로젝트에 맞게 경로 유지)
import 'package:easydev/utils/snackbar_helper.dart';

/// 설명란에서 진행률(예: "진행률:100%")을 읽어 100%면 100, 아니면 0을 리턴
int _extractProgress(String? description) {
  if (description == null || description.isEmpty) return 0;
  final m = RegExp(r'진행률\s*:\s*(\d{1,3})', caseSensitive: false)
      .firstMatch(description);
  if (m == null) return 0;
  final v = int.tryParse(m.group(1) ?? '0') ?? 0;
  return v == 100 ? 100 : 0;
}

/// Calendar API 인스턴스(공통 AuthClient 재사용)
Future<gcal.CalendarApi> _calendarApi() async {
  final auth.AuthClient client = await GoogleAuthSession.instance.client();
  return gcal.CalendarApi(client);
}

/// 완료된(진행률 100%) 캘린더 이벤트들을 하단시트로 보여주고,
/// 모두 삭제/개별 편집 액션을 제공.
/// [allEvents]: 미리 로드해둔 이벤트 전체(필터는 내부에서 수행)
/// [onEdit]: 개별 항목 탭 시 외부 편집 콜백(선택)
Future<void> openCompletedEventsSheet({
  required BuildContext context,
  required List<gcal.Event> allEvents,
  void Function(BuildContext, gcal.Event)? onEdit,
}) async {
  // 1) 완료 이벤트 필터링
  final completed =
  allEvents.where((e) => _extractProgress(e.description) == 100).toList();

  DateTime _startLocal(gcal.Event e) =>
      (e.start?.dateTime?.toLocal()) ??
          (e.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0));

  completed.sort((a, b) => _startLocal(a).compareTo(_startLocal(b)));

  // 2) 포맷터
  final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
  final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');
  final fmtTime = DateFormat('HH:mm');

  // 3) 바텀시트 UI
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
        builder: (context, scrollController) {
          return Column(
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.done_all, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '완료된 이벤트 (${completed.length}건)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: completed.isEmpty
                          ? null
                          : () async {
                        // 모두 삭제
                        await _deleteCompletedEventsFromGoogleCalendar(
                          context: context,
                          events: completed,
                          calendarId: 'primary',
                        );
                        if (!context.mounted) return;
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('모두 삭제'),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 리스트
              Expanded(
                child: completed.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('완료된 이벤트가 없습니다.'),
                  ),
                )
                    : ListView.separated(
                  controller: scrollController,
                  itemCount: completed.length,
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 0.5),
                  itemBuilder: (_, i) {
                    final e = completed[i];

                    // 시간 표시
                    final startLocal = _startLocal(e);
                    final endLocal = e.end?.dateTime?.toLocal();
                    final isAllDay =
                        e.start?.date != null && e.end?.date != null;

                    String when;
                    if (isAllDay) {
                      when = fmtDate.format(startLocal);
                    } else if (endLocal != null) {
                      when =
                      '${fmtDateTime.format(startLocal)} ~ ${fmtTime.format(endLocal)}';
                    } else {
                      when = fmtDateTime.format(startLocal);
                    }

                    return ListTile(
                      leading: const Icon(Icons.done, color: Colors.red),
                      title: Text(
                        e.summary ?? '(제목 없음)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(when),
                          if ((e.location ?? '').isNotEmpty)
                            Text('장소: ${e.location}'),
                          if ((e.description ?? '').isNotEmpty)
                            Text(
                              e.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      onTap: onEdit == null
                          ? null
                          : () => onEdit(context, e),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// 완료된 이벤트들을 Google Calendar에서 일괄 삭제
Future<void> _deleteCompletedEventsFromGoogleCalendar({
  required BuildContext context,
  required List<gcal.Event> events,
  required String calendarId,
}) async {
  if (events.isEmpty) {
    if (context.mounted) {
      showFailedSnackbar(context, '삭제할 완료 이벤트가 없습니다.');
    }
    return;
  }

  try {
    final api = await _calendarApi();

    int success = 0;
    int failed = 0;

    for (final e in events) {
      final id = e.id;
      if (id == null || id.isEmpty) {
        failed++;
        continue;
      }
      try {
        await api.events.delete(calendarId, id);
        success++;
      } catch (_) {
        failed++;
      }
    }

    if (context.mounted) {
      showSuccessSnackbar(context, '삭제 완료: $success건 / 실패: $failed건');
    }
  } catch (e) {
    if (context.mounted) {
      showFailedSnackbar(context, '삭제 실패: $e');
    }
  }
}
