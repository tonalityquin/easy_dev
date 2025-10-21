// lib/screens/dev_package/dev_memo.dart
//
// ※ intl 패키지가 필요합니다. pubspec.yaml에 추가하세요:
// dependencies:
//   intl: ^0.19.0

import 'dart:convert'; // ⬅️ 이메일 첨부(base64) 생성
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ⬇️ 전역 네비게이터/인증/메일 수신자 설정
import '../../utils/app_navigator.dart';
import '../../utils/google_auth_session.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import '../../utils/email_config.dart';

/// DevMemo
/// - ✅ 플로팅 버블(Overlay) 로직 제거
/// - ✅ 바텀시트 메모 패널만 남김 (필요 시 DevMemo.togglePanel()로 열기)
/// - ✅ "이메일 보내기" 버튼 추가: 메모를 .txt 첨부로 전송
class DevMemo {
  DevMemo._();

  /// ✅ MaterialApp.navigatorKey 로 연결
  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// "YYYY-MM-DD HH:mm | 내용" 형태의 문자열 리스트
  static final notes = ValueListenableNotifier<List<String>>(<String>[]);

  // ---- SharedPreferences Keys ----
  static const _kNotesKey = 'dev_memo_notes_v1';

  /// 노트 보관 상한 (옵션): 초과 시 오래된 항목을 잘라냅니다.
  static const int kMaxNotes = 1000;

  static SharedPreferences? _prefs;

  /// 앱 시작 시 1회 호출
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    notes.value = _prefs!.getStringList(_kNotesKey) ?? const <String>[];
  }

  /// Navigator 의 overlay.context 를 우선 사용 → MediaQuery/Theme 보장
  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  /// (호출용) 메모 패널 열기
  static Future<void> togglePanel() async {
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }

    await showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DevMemoSheet(),
    );
  }

  /// (호환용 별칭) 기존 코드에서 openPanel()을 호출해도 동작하도록 유지
  static Future<void> openPanel() => togglePanel();

  // ----------------- 데이터 조작 -----------------

  static Future<void> add(String text) async {
    final now = DateTime.now();
    final stamp = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final line = "$stamp | $text";

    final list = List<String>.from(notes.value)..insert(0, line);
    // 상한 적용
    if (list.length > kMaxNotes) {
      list.length = kMaxNotes; // 앞쪽(최신)만 남기고 뒤쪽(오래된) 커트
    }
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

/// 메모 바텀시트(풀높이 · 검색 · 입력 · 스와이프 삭제 · 이메일 전송)
class _DevMemoSheet extends StatefulWidget {
  const _DevMemoSheet();

  @override
  State<_DevMemoSheet> createState() => _DevMemoSheetState();
}

class _DevMemoSheetState extends State<_DevMemoSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _sending = false; // ⬅️ 이메일 전송 중 상태

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FractionallySizedBox(
      heightFactor: 1.0, // ⬅️ 최상단까지
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: Colors.white,
          child: SafeArea(
            top: false, // 외부 showModalBottomSheet(useSafeArea:true)와 중복 방지
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _DragHandle(),
                  const SizedBox(height: 12),

                  // 헤더: 타이틀 · 이메일 · 닫기
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.sticky_note_2_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('메모', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        // ⬇️ 이메일 전송 버튼 (.txt 첨부)
                        IconButton(
                          tooltip: _sending ? '전송 중...' : '이메일로 보내기',
                          onPressed: _sending ? null : _sendNotesByEmail,
                          icon: _sending
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.email_outlined),
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
                      valueListenable: DevMemo.notes,
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
                              key: ValueKey('${line}_$i'),
                              direction: DismissDirection.endToStart,
                              background: _SwipeDeleteBackground(
                                color: cs.errorContainer,
                                iconColor: cs.onErrorContainer,
                              ),
                              onDismissed: (_) async {
                                await DevMemo.removeLine(line);
                                HapticFeedback.selectionClick(); // 삭제 햅틱
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
                                        HapticFeedback.selectionClick(); // 복사 햅틱
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
                                      onPressed: () async {
                                        await DevMemo.removeLine(line);
                                        HapticFeedback.selectionClick(); // 삭제 햅틱
                                      },
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
    final notes = DevMemo.notes.value;
    if (notes.isEmpty) {
      _showSnack('보낼 메모가 없습니다.');
      return;
    }

    final cfg = await EmailConfig.load();
    if (!EmailConfig.isValidToList(cfg.to)) {
      _showSnack('수신자(To) 설정이 필요합니다: 설정 화면에서 이메일을 입력하세요.');
      return;
    }

    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final subject = 'DevMemo export (${DateFormat('yyyy-MM-dd').format(now)})';
      final filename = 'dev_memo_${DateFormat('yyyyMMdd_HHmmss').format(now)}.txt';
      final fileText = notes.join('\n'); // 최신순 문자열 리스트 → LF로 합치기

      // MIME multipart 작성
      final boundary = 'devmemo_${now.millisecondsSinceEpoch}';
      final bodyText = '첨부된 텍스트 파일에 메모가 포함되어 있습니다.';
      final toCsv = cfg.to;

      final attachmentB64 = base64.encode(utf8.encode(fileText)); // 표준 base64
      final mime = StringBuffer()
        ..writeln('MIME-Version: 1.0')
        ..writeln('To: $toCsv')
        ..writeln('Subject: $subject')
        ..writeln('Content-Type: multipart/mixed; boundary=\"$boundary\"')
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/plain; charset=\"utf-8\"')
        ..writeln('Content-Transfer-Encoding: 7bit')
        ..writeln()
        ..writeln(bodyText)
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/plain; charset=\"utf-8\"; name=\"$filename\"')
        ..writeln('Content-Disposition: attachment; filename=\"$filename\"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln()
        ..writeln(attachmentB64)
        ..writeln('--$boundary--');

      // 전체 RAW를 base64url 인코딩
      final raw = base64Url.encode(utf8.encode(mime.toString()));

      final client = await GoogleAuthSession.instance.client(); // googleapis_auth.AuthClient
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
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
    DevMemo.add(t);
    _inputCtrl.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
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
