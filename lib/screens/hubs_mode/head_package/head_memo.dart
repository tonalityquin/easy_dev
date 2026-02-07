import 'dart:convert'; // ⬅️ 이메일 RAW·첨부 생성용

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_navigator.dart';
// ✅ 수신자 이메일 저장/검증 유틸
import '../../../utils/api/email_config.dart';
// ✅ Gmail 전송용(중앙 세션)
import '../../../utils/google_auth_session.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../dev_package/debug_package/debug_api_logger.dart';

/// EasyMemo
/// - 전역 navigatorKey로 안전한 컨텍스트 확보 (showModalBottomSheet)
/// - 토글/메모 SharedPreferences 영속화
/// - 90% 높이 바텀시트 패널 (버블 제거됨)
class HeadMemo {
  HeadMemo._();

  /// ✅ MaterialApp.navigatorKey 로 연결
  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// 켜짐/꺼짐 토글 상태
  static final enabled = ValueNotifier<bool>(false);

  /// "YYYY-MM-DD HH:mm | 내용" 형태의 문자열 리스트
  static final notes = ValueListenableNotifier<List<String>>(<String>[]);

  static const _kEnabledKey = 'head_memo_enabled_v1';
  static const _kNotesKey = 'head_memo_notes_v1';

  static SharedPreferences? _prefs;
  static bool _inited = false;

  // ===== 패널 토글 상태 & 중복 호출 가드 =====
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tMemo = 'head_memo';
  static const String _tMemoUi = 'head_memo/ui';
  static const String _tMemoPrefs = 'head_memo/prefs';
  static const String _tMemoEmail = 'head_memo/email';
  static const String _tEmailConfig = 'email_config';
  static const String _tGmailSend = 'gmail/send';

  static Future<void> _logApiError({
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

  static Future<void> _ensureInited() async {
    if (_inited) return;
    await init();
  }

  /// 앱 시작 시 1회 호출
  static Future<void> init() async {
    if (_inited) return;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;
      notes.value = _prefs!.getStringList(_kNotesKey) ?? const <String>[];

      // 토글 변경 시 저장 (버블 제거 → 오버레이 토글 없음)
      enabled.addListener(() {
        try {
          _prefs?.setBool(_kEnabledKey, enabled.value);
        } catch (e) {
          _logApiError(
            tag: 'HeadMemo.enabled.listener',
            message: 'enabled 토글 저장 실패(SharedPreferences)',
            error: e,
            extra: <String, dynamic>{'enabled': enabled.value},
            tags: const <String>[_tMemo, _tMemoPrefs],
          );
        }
      });

      _inited = true;
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.init',
        message: 'HeadMemo init 실패(SharedPreferences)',
        error: e,
        tags: const <String>[_tMemo, _tMemoPrefs],
      );
      rethrow;
    }
  }

  /// Navigator 의 overlay.context 를 최우선으로 사용 → MediaQuery/Theme 보장
  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  /// (호환용) 기존 API는 토글로 라우팅
  static Future<void> openPanel() => togglePanel();

  /// ✅ 패널 토글 API: 열려 있으면 닫고, 닫혀 있으면 연다
  static Future<void> togglePanel() async {
    await _ensureInited();

    final ctx = _bestContext();
    if (ctx == null) {
      await _logApiError(
        tag: 'HeadMemo.togglePanel',
        message: 'Navigator context를 가져오지 못해 panel 토글을 지연',
        error: Exception('no_context'),
        tags: const <String>[_tMemo, _tMemoUi],
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }

    if (_isPanelOpen) {
      Navigator.of(ctx).maybePop();
      return;
    }

    // 빠른 연속 탭 가드
    if (_panelFuture != null) return;

    _isPanelOpen = true;
    _panelFuture = showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HeadMemoSheet(),
    ).whenComplete(() {
      _isPanelOpen = false;
      _panelFuture = null;
    });

    await _panelFuture;
  }

  // ----------------- 데이터 조작 -----------------

  static Future<void> add(String text) async {
    await _ensureInited();

    final now = DateTime.now();
    final stamp =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final line = "$stamp | $text";

    final list = List<String>.from(notes.value)..insert(0, line);
    notes.value = list;

    try {
      await _prefs?.setStringList(_kNotesKey, list);
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.add',
        message: '메모 저장 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{'len': text.trim().length, 'count': list.length},
        tags: const <String>[_tMemo, _tMemoPrefs],
      );
    }
  }

  static Future<void> removeAt(int index) async {
    await _ensureInited();

    final list = List<String>.from(notes.value);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);

    notes.value = list;

    try {
      await _prefs?.setStringList(_kNotesKey, list);
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.removeAt',
        message: '메모 삭제 반영 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{'index': index, 'count': list.length},
        tags: const <String>[_tMemo, _tMemoPrefs],
      );
    }
  }

  static Future<void> removeLine(String line) async {
    await _ensureInited();

    final list = List<String>.from(notes.value)..remove(line);
    notes.value = list;

    try {
      await _prefs?.setStringList(_kNotesKey, list);
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.removeLine',
        message: '메모 삭제 반영 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{'count': list.length},
        tags: const <String>[_tMemo, _tMemoPrefs],
      );
    }
  }
}

/// 메모 바텀시트(90% 높이 · 스위치 · 이메일 전송 버튼 · 수신자 다이얼로그 · 검색 · 입력 · 스와이프 삭제)
class _HeadMemoSheet extends StatefulWidget {
  const _HeadMemoSheet();

  @override
  State<_HeadMemoSheet> createState() => _HeadMemoSheetState();
}

class _HeadMemoSheetState extends State<_HeadMemoSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  // ✅ 수신자(To) 다이얼로그용 컨트롤러/상태
  final TextEditingController _mailToCtrl = TextEditingController();
  bool _mailToValid = true;
  bool _mailToLoading = true;

  // ✅ 이메일 전송 상태
  bool _sending = false;

  String _query = '';

  // MIME helpers
  static const int _mimeB64LineLength = 76;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim());
    });

    // ✅ EmailConfig 로드 → 다이얼로그 초기값 준비
    () async {
      try {
        final cfg = await EmailConfig.load();
        final to = cfg.to;
        if (!mounted) return;

        setState(() {
          _mailToCtrl.text = to;
          _mailToValid = to.isEmpty || EmailConfig.isValidToList(to);
          _mailToLoading = false;
        });

        _mailToCtrl.addListener(() {
          final t = _mailToCtrl.text.trim();
          final valid = t.isEmpty || EmailConfig.isValidToList(t);
          if (!mounted) return;
          if (valid != _mailToValid) setState(() => _mailToValid = valid);
        });
      } catch (e) {
        await HeadMemo._logApiError(
          tag: '_HeadMemoSheet.initState',
          message: 'EmailConfig.load 실패',
          error: e,
          tags: const <String>[HeadMemo._tMemo, HeadMemo._tEmailConfig],
        );
        if (!mounted) return;
        setState(() {
          _mailToCtrl.text = '';
          _mailToValid = true;
          _mailToLoading = false;
        });
      }
    }();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _searchCtrl.dispose();
    _mailToCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _DragHandle(),
                  const SizedBox(height: 12),

                  // 헤더: 타이틀 · 온/오프 · 이메일 전송 · 수신자 편집 · 닫기
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.sticky_note_2_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('메모', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),

                        ValueListenableBuilder<bool>(
                          valueListenable: HeadMemo.enabled,
                          builder: (_, on, __) => Row(
                            children: [
                              Text(on ? 'On' : 'Off', style: textTheme.labelMedium?.copyWith(color: cs.outline)),
                              const SizedBox(width: 6),
                              Switch(value: on, onChanged: (v) => HeadMemo.enabled.value = v),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // ✅ 이메일 전송(.txt 첨부)
                        IconButton(
                          tooltip: _sending ? '전송 중...' : '이메일로 보내기',
                          onPressed: _sending ? null : _sendNotesByEmail,
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.email_outlined),
                        ),

                        // ✅ 수신자(To) 편집 다이얼로그
                        IconButton(
                          tooltip: '수신자(To) 편집',
                          onPressed: _mailToLoading ? null : _openRecipientDialog,
                          icon: const Icon(Icons.alternate_email_rounded),
                        ),

                        IconButton(
                          tooltip: '닫기',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),

                  // 검색 바
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: '메모 검색',
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(.5),
                        border: _inputBorder(),
                        enabledBorder: _inputBorder(),
                        focusedBorder: _inputBorder(focused: true, cs: cs),
                        isDense: true,
                      ),
                    ),
                  ),

                  // 입력 영역
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            textInputAction: TextInputAction.done,
                            minLines: 1,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: '메모를 입력하세요',
                              prefixIcon: const Icon(Icons.edit_note_rounded),
                              filled: true,
                              fillColor: cs.surfaceVariant.withOpacity(.5),
                              border: _inputBorder(),
                              enabledBorder: _inputBorder(),
                              focusedBorder: _inputBorder(focused: true, cs: cs),
                              isDense: true,
                            ),
                            onSubmitted: _submitNote,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _submitNote(_inputCtrl.text),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('추가'),
                        ),
                      ],
                    ),
                  ),

                  // 리스트
                  Expanded(
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: HeadMemo.notes,
                      builder: (_, list, __) {
                        final filtered = _filtered(list, _query);
                        if (filtered.isEmpty) return _EmptyState(query: _query);

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final line = filtered[i];
                            final (time, text) = _parse(line);

                            return Dismissible(
                              key: ValueKey(line),
                              direction: DismissDirection.endToStart,
                              background: _SwipeDeleteBackground(
                                color: cs.errorContainer,
                                iconColor: cs.onErrorContainer,
                              ),
                              onDismissed: (_) {
                                HeadMemo.removeLine(line);
                                HapticFeedback.selectionClick();
                              },
                              child: ListTile(
                                dense: false,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.notes_rounded, color: cs.onPrimaryContainer, size: 18),
                                ),
                                title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: time.isNotEmpty ? Text(time, style: textTheme.bodySmall?.copyWith(color: cs.outline)) : null,
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: '복사',
                                      icon: const Icon(Icons.copy_rounded),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: text));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('메모를 복사했어요'),
                                            behavior: SnackBarBehavior.floating,
                                            duration: Duration(milliseconds: 900),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      tooltip: '삭제',
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      onPressed: () => HeadMemo.removeLine(line),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ 이메일 전송(.txt 첨부): DebugApiLogger 로깅 + MIME 안정화
  // ─────────────────────────────────────────────────────────────
  Future<void> _sendNotesByEmail() async {
    final notes = HeadMemo.notes.value;
    if (notes.isEmpty) {
      _showSnack('보낼 메모가 없습니다.');
      return;
    }

    // 세션 차단이면 전송 금지(안전)
    if (GoogleAuthSession.instance.isSessionBlocked) {
      _showSnack('구글 세션 차단(ON) 상태입니다. 전송을 위해 OFF로 변경해 주세요.');
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._sendNotesByEmail',
        message: '구글 세션 차단(ON) 상태로 이메일 전송 차단됨',
        error: StateError('google_session_blocked'),
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tMemoEmail],
      );
      return;
    }

    // 수신자 확인
    EmailConfig cfg;
    try {
      cfg = await EmailConfig.load();
    } catch (e) {
      _showSnack('수신자 설정 로드 실패: $e');
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._sendNotesByEmail',
        message: 'EmailConfig.load 실패',
        error: e,
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tEmailConfig],
      );
      return;
    }

    final toCsv = cfg.to.trim();
    if (!EmailConfig.isValidToList(toCsv)) {
      _showSnack('수신자(To) 설정이 필요합니다: 우측 @ 아이콘으로 이메일을 입력하세요.');
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._sendNotesByEmail',
        message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
        error: StateError('invalid_to'),
        extra: <String, dynamic>{'toLen': toCsv.length},
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tMemoEmail, HeadMemo._tEmailConfig],
      );
      return;
    }

    setState(() => _sending = true);

    try {
      final now = DateTime.now();
      final subject = 'HeadMemo export (${_fmtYMD(now)})';
      final filename = 'head_memo_${_fmtCompact(now)}.txt';
      final fileText = notes.join('\n'); // LF

      final boundary = 'headmemo_${now.millisecondsSinceEpoch}';
      const bodyText = '첨부된 텍스트 파일에 메모가 포함되어 있습니다.';

      // base64 첨부 + 76자 CRLF 래핑
      final attachmentB64 = base64.encode(utf8.encode(fileText));
      final attachmentWrapped = _wrapBase64Lines(attachmentB64);

      // MIME CRLF
      const crlf = '\r\n';
      final mime = StringBuffer()
        ..write('MIME-Version: 1.0$crlf')
        ..write('To: $toCsv$crlf')
        ..write('Subject: ${_encodeSubjectRfc2047(subject)}$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"$crlf')
        ..write('Content-Transfer-Encoding: 7bit$crlf')
        ..write(crlf)
        ..write(bodyText)
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"; name="$filename"$crlf')
        ..write('Content-Disposition: attachment; filename="$filename"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(attachmentWrapped)
        ..write('--$boundary--$crlf');

      final raw = base64UrlEncode(utf8.encode(mime.toString())).replaceAll('=', '');
      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

      _showSnack('이메일을 보냈습니다.');
    } catch (e) {
      _showSnack('전송 실패: $e');
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._sendNotesByEmail',
        message: 'Gmail 메모 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'notesCount': notes.length,
          'notesBytes': utf8.encode(notes.join('\n')).length,
        },
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tMemoEmail, HeadMemo._tGmailSend],
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- 수신자 다이얼로그 ----------

  Future<void> _openRecipientDialog() async {
    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('수신자(To) 설정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _mailToCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveMailTo(fromDialog: true),
                decoration: InputDecoration(
                  labelText: '수신자(To)',
                  hintText: 'a@x.com, b@y.com',
                  helperText: '쉼표(,)로 여러 명 입력',
                  isDense: true,
                  border: _emailBorder(),
                  enabledBorder: _emailBorder(valid: _mailToValid, cs: cs),
                  focusedBorder: _emailBorder(valid: _mailToValid, cs: cs, focused: true),
                  errorText: _mailToValid ? null : '이메일 형식을 확인해 주세요',
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('초기화'),
              onPressed: () async {
                await _clearMailTo();
                (ctx as Element).markNeedsBuild();
              },
            ),
            TextButton(
              child: const Text('취소'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('저장'),
              onPressed: () async {
                final ok = await _saveMailTo(fromDialog: true);
                if (ok && context.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // ---------- helpers ----------

  OutlineInputBorder _inputBorder({bool focused = false, ColorScheme? cs}) {
    final scheme = cs ?? Theme.of(context).colorScheme;
    final color = focused ? scheme.primary : Theme.of(context).dividerColor.withOpacity(.2);
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: focused ? 1.4 : 1),
    );
  }

  OutlineInputBorder _emailBorder({bool focused = false, bool valid = true, ColorScheme? cs}) {
    final scheme = cs ?? Theme.of(context).colorScheme;
    final Color color = valid ? (focused ? scheme.primary : scheme.outlineVariant) : scheme.error;
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: focused ? 1.4 : 1),
    );
  }

  (String, String) _parse(String line) {
    final split = line.indexOf('|');
    if (split < 0) return ('', line.trim());
    final time = line.substring(0, split).trim();
    final text = line.substring(split + 1).trim();
    return (time, text);
  }

  List<String> _filtered(List<String> src, String q) {
    if (q.isEmpty) return src;
    final query = q.toLowerCase();
    return src.where((e) => e.toLowerCase().contains(query)).toList();
  }

  void _submitNote(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    HeadMemo.add(t);
    _inputCtrl.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
  }

  Future<bool> _saveMailTo({bool fromDialog = false}) async {
    final to = _mailToCtrl.text.trim();
    if (to.isNotEmpty && !EmailConfig.isValidToList(to)) {
      if (mounted) setState(() => _mailToValid = false);
      if (!fromDialog) _showSnack('수신자 이메일 형식을 확인해 주세요.');
      return false;
    }

    try {
      await EmailConfig.save(EmailConfig(to: to));
    } catch (e) {
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._saveMailTo',
        message: 'EmailConfig.save 실패',
        error: e,
        extra: <String, dynamic>{'toLen': to.length},
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tEmailConfig],
      );
      _showSnack('저장 실패: $e');
      return false;
    }

    if (mounted) setState(() => _mailToValid = true);
    _showSnack('수신자 설정을 저장했습니다.');
    return true;
  }

  Future<void> _clearMailTo() async {
    try {
      await EmailConfig.clear();
      if (!mounted) return;
      setState(() {
        _mailToCtrl.text = '';
        _mailToValid = true;
      });
      _showSnack('수신자를 기본값(빈 값)으로 복원했습니다.');
    } catch (e) {
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._clearMailTo',
        message: 'EmailConfig.clear 실패',
        error: e,
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tEmailConfig],
      );
      _showSnack('초기화 실패: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  // 날짜 포맷터(외부 intl 없이 동작)
  String _fmt2(int n) => n.toString().padLeft(2, '0');
  String _fmtYMD(DateTime d) => '${d.year}-${_fmt2(d.month)}-${_fmt2(d.day)}';
  String _fmtCompact(DateTime d) =>
      '${d.year}${_fmt2(d.month)}${_fmt2(d.day)}_${_fmt2(d.hour)}${_fmt2(d.minute)}${_fmt2(d.second)}';

  // MIME helpers
  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _encodeSubjectRfc2047(String subject) {
    final hasNonAscii = subject.codeUnits.any((c) => c > 127);
    if (!hasNonAscii) return subject;
    final subjectB64 = base64.encode(utf8.encode(subject));
    return '=?utf-8?B?$subjectB64?=';
  }
}

// ---------- widgets ----------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  final Color color;
  final Color iconColor;
  const _SwipeDeleteBackground({required this.color, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: color,
      child: Icon(Icons.delete_outline_rounded, color: iconColor),
    );
  }
}

/// 작은 제네릭 ValueNotifier(리스트 비교 시 setState 유발 보장용)
class ValueListenableNotifier<T> extends ValueNotifier<T> {
  ValueListenableNotifier(super.value);

  @override
  set value(T newValue) {
    // 동일 참조여도 notify를 일으키고 싶다면 super.value 재할당이 가장 단순합니다.
    super.value = newValue;
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasQuery = query.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.event_note,
              color: cs.outline,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery ? '검색 결과가 없어요' : '아직 메모가 없습니다.',
              style: textTheme.bodyMedium?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
            if (hasQuery) ...[
              const SizedBox(height: 4),
              Text(
                '"$query"',
                style: textTheme.bodySmall?.copyWith(color: cs.outline),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
