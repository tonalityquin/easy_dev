import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

// OAuth (google_sign_in v7.x + extension v3.x)
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

// 스낵바 헬퍼
import '../../../utils/snackbar_helper.dart';

/// ✅ 웹 “클라이언트 ID”(Web Application) — 콘솔에서 만든 값
const String kWebClientId =
    '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

/// 쓰기여부에 따른 스코프
List<String> _scopesFor(bool write) {
  return write
      ? <String>[gcal.CalendarApi.calendarEventsScope] // R/W
      : <String>[gcal.CalendarApi.calendarReadonlyScope]; // Readonly
}

// google_sign_in v7.x: initialize()는 반드시 1회만.
bool _gsInitialized = false;
Future<void> _ensureGsInitialized() async {
  if (_gsInitialized) return;
  // ✅ Android에선 serverClientId로 “웹 클라ID”를 넣어야 함(28444 방지)
  _gsInitialized = true;
}

/// 인증 이벤트에서 SignIn 이벤트를 기다려 GoogleSignInAccount 획득
Future<GoogleSignInAccount> _waitForSignInEvent() async {
  final signIn = GoogleSignIn.instance;
  final completer = Completer<GoogleSignInAccount>();
  late final StreamSubscription sub;

  sub = signIn.authenticationEvents.listen((event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        if (!completer.isCompleted) completer.complete(event.user);
      case GoogleSignInAuthenticationEventSignOut():
        break;
    }
  }, onError: (e) {
    if (!completer.isCompleted) completer.completeError(e);
  });

  try {
    try {
      await signIn.attemptLightweightAuthentication(); // 무UI 시도
    } catch (_) {}

    if (signIn.supportsAuthenticate()) {
      // UI 인증은 확실히 기다립니다(경쟁상황 방지)
      await signIn.authenticate();
    }

    final user = await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw Exception('Google 로그인 응답 시간 초과'),
    );
    return user;
  } finally {
    await sub.cancel();
  }
}

/// OAuth 기반 AuthClient 만들기 (v7 권장 흐름)
Future<auth.AuthClient> getAuthClient({bool write = false}) async {
  final scopes = _scopesFor(write);
  await _ensureGsInitialized();

  // 1) 사용자 확보(이벤트 기반) → 2) 스코프 인가 → 3) AuthClient
  final user = await _waitForSignInEvent();

  var authorization =
  await user.authorizationClient.authorizationForScopes(scopes);
  authorization ??= await user.authorizationClient.authorizeScopes(scopes);

  return authorization.authClient(scopes: scopes);
}

// ---------------------------
// 완료 이벤트 바텀시트 UI & 로직
// ---------------------------

int _extractProgress(String? description) {
  final m = RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false)
      .firstMatch(description ?? '');
  if (m == null) return 0;
  final v = int.tryParse(m.group(1) ?? '0') ?? 0;
  return v == 100 ? 100 : 0;
}

/// 완료된 이벤트 바텀시트 오픈
Future<void> openCompletedEventsSheet({
  required BuildContext context,
  required List<gcal.Event> allEvents,
  void Function(BuildContext, gcal.Event)? onEdit,
}) async {
  final completed =
  allEvents.where((e) => _extractProgress(e.description) == 100).toList();

  DateTime _startOf(gcal.Event e) =>
      (e.start?.dateTime?.toLocal()) ??
          (e.start?.date ?? DateTime.fromMillisecondsSinceEpoch(0));

  completed.sort((a, b) => _startOf(a).compareTo(_startOf(b)));

  final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
  final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');
  final fmtTime = DateFormat('HH:mm');

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
                      IconButton(
                        tooltip: '완료 이벤트 삭제',
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent),
                        onPressed: () => _deleteCompletedEventsFromGoogleCalendar(
                          context,
                          completed,
                          // calendarId: 'primary',
                        ),
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
                    separatorBuilder: (_, __) =>
                    const Divider(height: 1),
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
                        const Icon(Icons.done, color: Colors.red),
                        title: Text(
                          e.summary ?? '(제목 없음)',
                          style: const TextStyle(color: Colors.black87),
                        ),
                        subtitle: Text(
                          when,
                          style:
                          const TextStyle(color: Colors.black54),
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
      );
    },
  );
}

/// (참고용) calendarId 추정. OAuth에서는 'primary' 사용 권장.
String? _guessCalendarId(List<gcal.Event> events) {
  for (final e in events) {
    final cand = e.organizer?.email ??
        e.creator?.email ??
        (e.attendees
            ?.firstWhere(
              (a) => a.self == true && (a.email?.isNotEmpty ?? false),
          orElse: () => gcal.EventAttendee(),
        ))
            ?.email;
    if (cand != null && cand.isNotEmpty) return cand;
  }
  return null;
}

/// 완료(progress:100) 이벤트 일괄 삭제 (OAuth)
Future<void> _deleteCompletedEventsFromGoogleCalendar(
    BuildContext context,
    List<gcal.Event> completed, {
      String? calendarId,
    }) async {
  if (completed.isEmpty) {
    showSelectedSnackbar(context, '삭제할 완료 이벤트가 없습니다.');
    return;
  }

  // 전달값 > 추정값 > primary
  final calId = (() {
    final explicit = calendarId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _guessCalendarId(completed) ?? 'primary';
  })();

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
                  style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent),
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
    final client = await getAuthClient(write: true);
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
