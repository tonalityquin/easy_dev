import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/app_navigator.dart';

/// DevMemo (Firestore 버전)
/// - 전역 navigatorKey로 안전한 컨텍스트 확보 (showModalBottomSheet/Overlay)
/// - ✅ SharedPreferences 제거 → Firestore document 실시간 동기화
/// - 드래그 가능한 플로팅 버블 + 90% 높이 바텀시트 패널
class DevMemo {
  DevMemo._();

  /// ✅ MaterialApp.navigatorKey 로 연결
  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// 켜짐/꺼짐 토글 상태
  static final enabled = ValueNotifier<bool>(false);

  /// "YYYY-MM-DD HH:mm | 내용" 형태의 문자열 리스트
  static final notes = ValueListenableNotifier<List<String>>(<String>[]);

  // ---- Firestore ----
  static FirebaseFirestore? _db;
  static DocumentReference<Map<String, dynamic>>? _doc;
  static Stream<DocumentSnapshot<Map<String, dynamic>>>? _snapStream;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static String _docId = 'dev_global'; // 기본값 (필요 시 init(docId: ...)로 교체)

  // 오버레이
  static OverlayEntry? _entry;

  // ===== 패널 토글 상태 & 중복 호출 가드 =====
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  /// 앱 시작 시 1회 호출
  /// - docId 에 구글 Docs/Sheets ID를 그대로 넘겨 사용하세요.
  static Future<void> init({String docId = 'dev_global'}) async {
    _docId = docId;
    _db ??= FirebaseFirestore.instance;
    _doc = _db!.collection('memo_docs').doc(_docId);

    // 문서가 없으면 초기값 생성
    final snap = await _doc!.get();
    if (!snap.exists) {
      await _doc!.set({
        'enabled': false,
        'notes': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 실시간 구독 → enabled/notes 동기화
    await _sub?.cancel();
    _snapStream = _doc!.snapshots();
    _sub = _snapStream!.listen((s) {
      final data = s.data();
      if (data == null) return;
      final bool on = (data['enabled'] ?? false) as bool;
      final List<String> list = List<String>.from(data['notes'] ?? const <String>[]);
      // 외부 변경도 반영
      if (enabled.value != on) enabled.value = on;
      if (!_listEquals(notes.value, list)) notes.value = list;
    });

    // 로컬에서 스위치 바꾸면 Firestore 로 반영
    enabled.addListener(() {
      _doc?.update({'enabled': enabled.value, 'updatedAt': FieldValue.serverTimestamp()});
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
  }

  /// 런타임에 다른 문서로 전환(예: 다른 Google Docs/Sheets ID)
  static Future<void> switchDoc(String newDocId) async {
    if (newDocId.trim().isEmpty || newDocId == _docId) return;
    await _sub?.cancel();
    _docId = newDocId;
    _doc = _db!.collection('memo_docs').doc(_docId);

    final snap = await _doc!.get();
    if (!snap.exists) {
      await _doc!.set({
        'enabled': false,
        'notes': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    _sub = _doc!.snapshots().listen((s) {
      final data = s.data();
      if (data == null) return;
      final bool on = (data['enabled'] ?? false) as bool;
      final List<String> list = List<String>.from(data['notes'] ?? const <String>[]);
      if (enabled.value != on) enabled.value = on;
      if (!_listEquals(notes.value, list)) notes.value = list;
    });
  }

  /// 첫 프레임 이후 오버레이 필요 시 부착 (MaterialApp 생성 후 보장)
  static void mountIfNeeded() {
    if (enabled.value) _showOverlay();
  }

  /// Navigator 의 overlay.context 를 최우선으로 사용 → MediaQuery/Theme 보장
  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  /// (호환용) 기존 API는 토글로 라우팅
  static Future<void> openPanel() => togglePanel();

  /// ✅ 버블/카드가 부를 토글 API: 열려 있으면 닫고, 닫혀 있으면 연다
  static Future<void> togglePanel() async {
    final ctx = _bestContext();
    if (ctx == null) {
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
      builder: (_) => const _DevMemoSheet(),
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(builder: (context) => const _DevMemoBubble());
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

  // ----------------- 데이터 조작 (Firestore Transaction) -----------------

  static Future<void> add(String text) async {
    final now = DateTime.now();
    final stamp =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final line = "$stamp | $text";

    await _db!.runTransaction((tx) async {
      final s = await tx.get(_doc!);
      final cur = List<String>.from(s.data()?['notes'] ?? const <String>[]);
      cur.insert(0, line);
      tx.update(_doc!, {'notes': cur, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  static Future<void> removeAt(int index) async {
    await _db!.runTransaction((tx) async {
      final s = await tx.get(_doc!);
      final cur = List<String>.from(s.data()?['notes'] ?? const <String>[]);
      if (index >= 0 && index < cur.length) {
        cur.removeAt(index);
        tx.update(_doc!, {'notes': cur, 'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  }

  static Future<void> removeLine(String line) async {
    await _db!.runTransaction((tx) async {
      final s = await tx.get(_doc!);
      final cur = List<String>.from(s.data()?['notes'] ?? const <String>[]);
      cur.remove(line);
      tx.update(_doc!, {'notes': cur, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// 종료 정리(선택)
  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _snapStream = null;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 드래그 가능한 플로팅 버블(엣지 스냅)
class _DevMemoBubble extends StatefulWidget {
  const _DevMemoBubble();

  @override
  State<_DevMemoBubble> createState() => _DevMemoBubbleState();
}

class _DevMemoBubbleState extends State<_DevMemoBubble> {
  static const double _bubbleSize = 56;
  Offset _pos = const Offset(12, 200);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _pos = Offset(
              (_pos.dx + d.delta.dx).clamp(0.0, screen.width - _bubbleSize),
              (_pos.dy + d.delta.dy).clamp(0.0, screen.height - _bubbleSize - bottomInset),
            );
          });
        },
        onPanEnd: (_) {
          final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
              ? 8.0
              : screen.width - _bubbleSize - 8.0;
          setState(() => _pos = Offset(snapX, _pos.dy));
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: DevMemo.togglePanel,
            customBorder: const CircleBorder(),
            child: Container(
              width: _bubbleSize,
              height: _bubbleSize,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.5), // 50% 반투명
                shape: BoxShape.circle,
                border: Border.all(color: cs.onSurface.withOpacity(.08)),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.sticky_note_2_rounded,
                color: Colors.white.withOpacity(0.95),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 메모 바텀시트(90% 높이 · 스위치 · 검색 · 입력 · 스와이프 삭제)
class _DevMemoSheet extends StatefulWidget {
  const _DevMemoSheet();

  @override
  State<_DevMemoSheet> createState() => _DevMemoSheetState();
}

class _DevMemoSheetState extends State<_DevMemoSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

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

                  // 헤더: 타이틀 · 온/오프 · 닫기
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.sticky_note_2_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('메모', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        ValueListenableBuilder<bool>(
                          valueListenable: DevMemo.enabled,
                          builder: (_, on, __) => Row(
                            children: [
                              Text(on ? 'On' : 'Off', style: textTheme.labelMedium?.copyWith(color: cs.outline)),
                              const SizedBox(width: 6),
                              Switch(value: on, onChanged: (v) => DevMemo.enabled.value = v),
                            ],
                          ),
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
                              key: ValueKey(line),
                              direction: DismissDirection.endToStart,
                              background: _SwipeDeleteBackground(
                                color: cs.errorContainer,
                                iconColor: cs.onErrorContainer,
                              ),
                              onDismissed: (_) {
                                DevMemo.removeLine(line);
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
                                      onPressed: () => DevMemo.removeLine(line),
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
