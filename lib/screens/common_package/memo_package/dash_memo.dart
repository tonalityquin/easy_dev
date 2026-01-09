import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../../../utils/app_navigator.dart';
import '../../../../../../utils/google_auth_session.dart';
import '../../../../../../utils/api/email_config.dart';

// ✅ API 디버그(통합 에러 로그) 로거 + (옵션) 디버그 UI
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_bottom_sheet.dart';

// ── Brand palette (minimal use)
const Color _base = Color(0xFF0D47A1);
const Color _dark = Color(0xFF09367D);
const Color _light = Color(0xFF5472D3);

class DashMemo {
  DashMemo._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// 켜짐/꺼짐 토글 상태 (DevMemo와 독립)
  static final enabled = ValueNotifier<bool>(false);

  /// "YYYY-MM-DD HH:mm | 내용" 리스트 (DevMemo와 독립)
  static final notes = _ValueListenableNotifier<List<String>>(<String>[]);

  // ---- SharedPreferences Keys (DevMemo와 분리) ----
  static const _kEnabledKey = 'dash_memo_enabled_v1';
  static const _kNotesKey = 'dash_memo_notes_v1';
  static const _kBubbleXKey = 'dash_memo_bubble_x_v1';
  static const _kBubbleYKey = 'dash_memo_bubble_y_v1';

  /// 노트 상한 (초과 시 오래된 항목 제거)
  static const int kMaxNotes = 1000;

  // ✅ FIX: MIME base64 line length (RFC 2045 recommends 76 chars)
  // (이 값이 없어서 _DashMemoSheetState에서 참조 시 컴파일 오류 발생)
  static const int _mimeB64LineLength = 76;

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _inited = false;

  // ===== 패널 토글 상태 & 중복 호출 가드 =====
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tMemo = 'dash_memo';
  static const String _tMemoUi = 'dash_memo/ui';
  static const String _tMemoPrefs = 'dash_memo/prefs';
  static const String _tMemoEmail = 'dash_memo/email';
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

  /// 최초 1회 초기화 (지연 호출 가능)
  static Future<void> init() async {
    if (_inited) return;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;
      notes.value = _prefs!.getStringList(_kNotesKey) ?? const <String>[];

      // 토글 변경 시 저장 + 오버레이 토글
      enabled.addListener(() {
        try {
          _prefs?.setBool(_kEnabledKey, enabled.value);
        } catch (e) {
          _logApiError(
            tag: 'LiteDashMemo.enabled.listener',
            message: 'enabled 토글 상태 저장 실패(SharedPreferences)',
            error: e,
            extra: <String, dynamic>{'enabled': enabled.value},
            tags: const <String>[_tMemoPrefs, _tMemo],
          );
        }

        if (enabled.value) {
          _showOverlay();
        } else {
          _hideOverlay();
        }
      });

      _inited = true;
    } catch (e) {
      await _logApiError(
        tag: 'LiteDashMemo.init',
        message: 'LiteDashMemo init 실패(SharedPreferences)',
        error: e,
        tags: const <String>[_tMemoPrefs, _tMemo],
      );
      rethrow;
    }
  }

  /// 첫 프레임 이후 오버레이 필요 시 부착
  static void mountIfNeeded() {
    if (!enabled.value) return;
    _showOverlay();
  }

  /// Navigator overlay.context 우선
  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  /// 메모 시트 토글
  static Future<void> togglePanel() async {
    if (!_inited) await init();
    final ctx = _bestContext();
    if (ctx == null) {
      // ✅ _tMemoUi 사용(경고 해결 겸, UI 컨텍스트 부재 상황 로깅)
      await _logApiError(
        tag: 'LiteDashMemo.togglePanel',
        message: 'Navigator context를 가져오지 못해 panel 토글을 지연',
        error: Exception('no_context'),
        tags: const <String>[_tMemoUi, _tMemo],
      );

      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }

    if (_isPanelOpen) {
      Navigator.of(ctx).maybePop();
      return;
    }
    if (_panelFuture != null) return;

    _isPanelOpen = true;
    _panelFuture = showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DashMemoSheet(),
    ).whenComplete(() {
      _isPanelOpen = false;
      _panelFuture = null;
    });

    await _panelFuture;
  }

  // ----------------- 내부: 오버레이(버블) -----------------

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      // ✅ _tMemoUi 사용(경고 해결 겸)
      _logApiError(
        tag: 'LiteDashMemo._showOverlay',
        message: 'Navigator overlay를 찾지 못해 overlay 부착을 지연',
        error: Exception('overlay_null'),
        tags: const <String>[_tMemoUi, _tMemo],
      );

      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(builder: (context) => const _DashMemoBubble());
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

  // ----------------- 데이터 조작 -----------------

  static Future<void> add(String text) async {
    if (!_inited) await init();
    final now = DateTime.now();
    final stamp = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final line = "$stamp | $text";

    final list = List<String>.from(notes.value)..insert(0, line);
    if (list.length > kMaxNotes) {
      list.length = kMaxNotes;
    }
    notes.value = list;

    try {
      await _prefs?.setStringList(_kNotesKey, list);
    } catch (e) {
      await _logApiError(
        tag: 'LiteDashMemo.add',
        message: '메모 저장 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{'len': text.trim().length, 'count': list.length},
        tags: const <String>[_tMemoPrefs, _tMemo],
      );
    }
  }

  static Future<void> removeLine(String line) async {
    if (!_inited) await init();
    final list = List<String>.from(notes.value)..remove(line);
    notes.value = list;
    try {
      await _prefs?.setStringList(_kNotesKey, list);
    } catch (e) {
      await _logApiError(
        tag: 'LiteDashMemo.removeLine',
        message: '메모 삭제 반영 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{'count': list.length},
        tags: const <String>[_tMemoPrefs, _tMemo],
      );
    }
  }

  /// 버블 좌표 저장/복원 (영속화)
  static Future<void> saveBubblePos(Offset pos) async {
    if (!_inited) await init();
    try {
      await _prefs!.setDouble(_kBubbleXKey, pos.dx);
      await _prefs!.setDouble(_kBubbleYKey, pos.dy);
    } catch (e) {
      await _logApiError(
        tag: 'LiteDashMemo.saveBubblePos',
        message: '버블 위치 저장 실패(SharedPreferences)',
        error: e,
        extra: <String, dynamic>{'x': pos.dx, 'y': pos.dy},
        tags: const <String>[_tMemoPrefs, _tMemo],
      );
    }
  }

  static Offset restoreBubblePos() {
    final dx = _prefs?.getDouble(_kBubbleXKey) ?? 12.0;
    final dy = _prefs?.getDouble(_kBubbleYKey) ?? 200.0;
    return Offset(dx, dy);
  }
}

/// 드래그 가능한 플로팅 버블(즉시 열림 버전)
class _DashMemoBubble extends StatefulWidget {
  const _DashMemoBubble();

  @override
  State<_DashMemoBubble> createState() => _DashMemoBubbleState();
}

class _DashMemoBubbleState extends State<_DashMemoBubble> with SingleTickerProviderStateMixin {
  static const double _bubbleSize = 56;
  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _spinCtrl;
  late final Animation<double> _spin;

  @override
  void initState() {
    super.initState();
    _pos = DashMemo.restoreBubblePos();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _spin = CurvedAnimation(
      parent: _spinCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    HapticFeedback.selectionClick();
    _spinCtrl.forward(from: 0).then((_) => _spinCtrl.reverse());
    await DashMemo.togglePanel();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset);
    }

    return Stack(
      children: [
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                final next = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
                _pos = _clampToScreen(next, screen, bottomInset);
              });
            },
            onPanEnd: (_) async {
              final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2 ? 8.0 : screen.width - _bubbleSize - 8.0;
              setState(() => _pos = Offset(snapX, _pos.dy));
              await DashMemo.saveBubblePos(_pos);
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _onTap,
                customBorder: const CircleBorder(),
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (_, __) {
                    return Container(
                      width: _bubbleSize,
                      height: _bubbleSize,
                      decoration: BoxDecoration(
                        color: _base.withOpacity(0.92),
                        shape: BoxShape.circle,
                        border: Border.all(color: _light.withOpacity(.55)),
                        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                      ),
                      alignment: Alignment.center,
                      child: Transform.rotate(
                        angle: _spin.value * math.pi,
                        child: Icon(Icons.settings_rounded, color: Colors.white.withOpacity(0.95)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _clampToScreen(Offset raw, Size screen, double bottomInset) {
    const double s = _bubbleSize;
    final maxX = (screen.width - s).clamp(0.0, double.infinity);
    final maxY = (screen.height - s - bottomInset).clamp(0.0, double.infinity);
    final dx = raw.dx.clamp(0.0, maxX);
    final dy = raw.dy.clamp(0.0, maxY);
    return Offset(dx, dy);
  }
}

/// 메모 바텀시트(풀높이 · 스위치 · 검색 · 입력 · 스와이프 삭제)
class _DashMemoSheet extends StatefulWidget {
  const _DashMemoSheet();

  @override
  State<_DashMemoSheet> createState() => _DashMemoSheetState();
}

class _DashMemoSheetState extends State<_DashMemoSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
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
      heightFactor: 1.0,
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

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.sticky_note_2_rounded, color: _base),
                        const SizedBox(width: 8),
                        Text('메모', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),

                        IconButton(
                          tooltip: 'API 디버그',
                          onPressed: () async {
                            HapticFeedback.selectionClick();
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const DebugBottomSheet(),
                            );
                          },
                          icon: const Icon(Icons.bug_report_outlined),
                        ),

                        ValueListenableBuilder<bool>(
                          valueListenable: DashMemo.enabled,
                          builder: (_, on, __) => Row(
                            children: [
                              Text(on ? 'On' : 'Off', style: textTheme.labelMedium?.copyWith(color: cs.outline)),
                              const SizedBox(width: 6),
                              Switch(
                                value: on,
                                onChanged: (v) => DashMemo.enabled.value = v,
                                activeColor: _base,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        IconButton(
                          tooltip: _sending ? '전송 중...' : '이메일로 보내기',
                          onPressed: _sending ? null : _sendNotesByEmail,
                          icon: _sending
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(_base),
                            ),
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
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: _light, width: 1.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _submitNote(_inputCtrl.text),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('추가'),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: DashMemo.notes,
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
                                await DashMemo.removeLine(line);
                                HapticFeedback.selectionClick();
                              },
                              child: ListTile(
                                dense: false,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: _light.withOpacity(.18),
                                  child: const Icon(Icons.notes_rounded, color: _dark, size: 18),
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
                                        HapticFeedback.selectionClick();
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
                                        await DashMemo.removeLine(line);
                                        HapticFeedback.selectionClick();
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

  Future<void> _sendNotesByEmail() async {
    final notes = DashMemo.notes.value;
    if (notes.isEmpty) {
      _showSnack('보낼 메모가 없습니다.');
      return;
    }

    final blocked = GoogleAuthSession.instance.isSessionBlocked;
    if (blocked) {
      _showSnack('구글 세션 차단(ON) 상태입니다. 전송을 위해 OFF로 변경해 주세요.');
      return;
    }

    final cfg = await EmailConfig.load();
    if (!EmailConfig.isValidToList(cfg.to)) {
      _showSnack('수신자(To) 설정이 필요합니다: 설정 화면에서 이메일을 입력하세요.');

      await DashMemo._logApiError(
        tag: 'DashMemo._sendNotesByEmail',
        message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
        error: Exception('invalid_to'),
        extra: <String, dynamic>{'toRaw': cfg.to},
        tags: const <String>[DashMemo._tMemoEmail, DashMemo._tMemo],
      );

      return;
    }

    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final subject = 'DashMemo export (${DateFormat('yyyy-MM-dd').format(now)})';
      final filename = 'dash_memo_${DateFormat('yyyyMMdd_HHmmss').format(now)}.txt';

      final fileText = notes.join('\n');

      final boundary = 'dashmemo_${now.millisecondsSinceEpoch}';
      const bodyText = '첨부된 텍스트 파일에 메모가 포함되어 있습니다.';
      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

      final attachmentB64 = base64.encode(utf8.encode(fileText));
      final attachmentWrapped = _wrapBase64Lines(attachmentB64);

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

      final raw = base64Url.encode(utf8.encode(mime.toString())).replaceAll('=', '');

      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

      _showSnack('이메일을 보냈습니다.');
    } catch (e) {
      _showSnack('전송 실패: $e');

      await DashMemo._logApiError(
        tag: 'DashMemo._sendNotesByEmail',
        message: 'Gmail API 메모 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'notesCount': notes.length,
          'notesBytes': utf8.encode(notes.join('\n')).length,
        },
        tags: const <String>[DashMemo._tMemoEmail, DashMemo._tGmailSend, DashMemo._tMemo],
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  OutlineInputBorder _inputBorder({bool focused = false, ColorScheme? cs}) {
    final color = focused ? _base : Theme.of(context).dividerColor.withOpacity(.2);
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
    DashMemo.add(t);
    _inputCtrl.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
  }

  String _wrapBase64Lines(String b64, {int lineLength = DashMemo._mimeB64LineLength}) {
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

/// 내부 전용: ValueNotifier set시 동일 참조라도 리빌드 보장
class _ValueListenableNotifier<T> extends ValueNotifier<T> {
  _ValueListenableNotifier(super.value);

  @override
  set value(T newValue) {
    super.value = newValue;
  }
}

/// 빈 상태 위젯 (검색/목록 비었을 때)
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
