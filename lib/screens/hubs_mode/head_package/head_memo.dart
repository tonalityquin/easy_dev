import 'dart:convert'; // ⬅️ 이메일 RAW·첨부 생성용
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_navigator.dart';
// ✅ 수신자 이메일 저장/검증 유틸
import '../../../utils/api/email_config.dart';
// ✅ Gmail 전송용
import '../../../utils/google_auth_session.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

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

  // ===== 패널 토글 상태 & 중복 호출 가드 =====
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  /// 앱 시작 시 1회 호출
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;
    notes.value = _prefs!.getStringList(_kNotesKey) ?? const <String>[];

    // 토글 변경 시 저장 (버블 제거 → 오버레이 토글 없음)
    enabled.addListener(() {
      _prefs?.setBool(_kEnabledKey, enabled.value);
    });
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
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }

    if (_isPanelOpen) {
      // 이미 열려 있으면 닫기
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
      backgroundColor: Colors.transparent, // 바깥(시트 바깥) 배경은 투명 유지
      builder: (_) => const _HeadMemoSheet(),
    ).whenComplete(() {
      _isPanelOpen = false;
      _panelFuture = null;
    });

    await _panelFuture;
  }

  // ----------------- 데이터 조작 -----------------

  static Future<void> add(String text) async {
    final now = DateTime.now();
    final stamp =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final line = "$stamp | $text";
    final list = List<String>.from(notes.value)..insert(0, line);
    notes.value = list;
    await _prefs?.setStringList(_kNotesKey, list);
  }

  static Future<void> removeAt(int index) async {
    final list = List<String>.from(notes.value)..removeAt(index);
    notes.value = list;
    await _prefs?.setStringList(_kNotesKey, list);
  }

  static Future<void> removeLine(String line) async {
    final list = List<String>.from(notes.value)..remove(line);
    notes.value = list;
    await _prefs?.setStringList(_kNotesKey, list);
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

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });

    // ✅ EmailConfig 로드 → 다이얼로그 초기값 준비
    () async {
      final cfg = await EmailConfig.load();
      final to = cfg.to;
      setState(() {
        _mailToCtrl.text = to;
        _mailToValid = to.isEmpty || EmailConfig.isValidToList(to);
        _mailToLoading = false;
      });
      _mailToCtrl.addListener(() {
        final t = _mailToCtrl.text.trim();
        final valid = t.isEmpty || EmailConfig.isValidToList(t);
        if (valid != _mailToValid) {
          setState(() => _mailToValid = valid);
        }
      });
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

    // 90% 높이 바텀시트 (배경: 순백색)
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: Colors.white, // ✅ 배경을 완전한 흰색으로 고정
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

                        // On/Off 토글
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
                              ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.email_outlined),
                        ),

                        // ✅ 수신자(To) 편집 다이얼로그
                        IconButton(
                          tooltip: '수신자(To) 편집',
                          onPressed: _mailToLoading ? null : _openRecipientDialog,
                          icon: const Icon(Icons.alternate_email_rounded),
                        ),

                        // 닫기
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
                        if (filtered.isEmpty) {
                          return _EmptyState(query: _query);
                        }
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
                                subtitle: time.isNotEmpty
                                    ? Text(time, style: textTheme.bodySmall?.copyWith(color: cs.outline))
                                    : null,
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

  // ---------- 이메일 전송(.txt 첨부) ----------

  Future<void> _sendNotesByEmail() async {
    final notes = HeadMemo.notes.value;
    if (notes.isEmpty) {
      _showSnack('보낼 메모가 없습니다.');
      return;
    }

    // 수신자 확인
    final cfg = await EmailConfig.load();
    final toCsv = cfg.to.trim();
    if (!EmailConfig.isValidToList(toCsv)) {
      _showSnack('수신자(To) 설정이 필요합니다: 우측 @ 아이콘으로 이메일을 입력하세요.');
      return;
    }

    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final subject = 'HeadMemo export (${_fmtYMD(now)})';
      final filename = 'head_memo_${_fmtCompact(now)}.txt';
      final fileText = notes.join('\n'); // 최신순 문자열 리스트 → LF로 합치기

      // MIME multipart 작성
      final boundary = 'headmemo_${now.millisecondsSinceEpoch}';
      final bodyText = '첨부된 텍스트 파일에 메모가 포함되어 있습니다.';

      // 첨부는 표준 base64
      final attachmentB64 = base64.encode(utf8.encode(fileText));

      final mime = StringBuffer()
        ..writeln('MIME-Version: 1.0')
        ..writeln('To: $toCsv')
        ..writeln('Subject: $subject')
        ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/plain; charset="utf-8"')
        ..writeln('Content-Transfer-Encoding: 7bit')
        ..writeln()
        ..writeln(bodyText)
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/plain; charset="utf-8"; name="$filename"')
        ..writeln('Content-Disposition: attachment; filename="$filename"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln()
        ..writeln(attachmentB64)
        ..writeln('--$boundary--');

      // 전체 RAW를 base64url 인코딩
      final raw = base64Url.encode(utf8.encode(mime.toString()));

      final client = await GoogleAuthSession.instance.safeClient(); // googleapis_auth.AuthClient
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

      _showSnack('이메일을 보냈습니다.');
    } catch (e) {
      _showSnack('전송 실패: $e');
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
                // 다이얼로그 내에서도 에러 텍스트 갱신
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
    final color = focused
        ? (cs ?? Theme.of(context).colorScheme).primary
        : Theme.of(context).dividerColor.withOpacity(.2);
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: focused ? 1.4 : 1),
    );
  }

  // ✅ 수신자 입력 전용 테두리(유효/무효 색상 반영)
  OutlineInputBorder _emailBorder({bool focused = false, bool valid = true, ColorScheme? cs}) {
    final scheme = cs ?? Theme.of(context).colorScheme;
    final Color color = valid
        ? (focused ? scheme.primary : scheme.outlineVariant)
        : scheme.error;
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

  // ✅ 수신자 저장/초기화
  Future<bool> _saveMailTo({bool fromDialog = false}) async {
    final to = _mailToCtrl.text.trim();
    if (to.isNotEmpty && !EmailConfig.isValidToList(to)) {
      setState(() => _mailToValid = false);
      if (fromDialog) {
        // 다이얼로그 내 에러 텍스트 표시 위해 스낵은 생략 가능
      } else {
        _showSnack('수신자 이메일 형식을 확인해 주세요.');
      }
      return false;
    }
    await EmailConfig.save(EmailConfig(to: to));
    setState(() => _mailToValid = true);
    _showSnack('수신자 설정을 저장했습니다.');
    return true;
  }

  Future<void> _clearMailTo() async {
    await EmailConfig.clear();
    setState(() {
      _mailToCtrl.text = '';
      _mailToValid = true;
    });
    _showSnack('수신자를 기본값(빈 값)으로 복원했습니다.');
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
    if (!identical(newValue, super.value)) {
      super.value = newValue;
    } else {
      super.value = newValue;
    }
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
