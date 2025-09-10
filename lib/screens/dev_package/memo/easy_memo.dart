import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

/// EasyMemo
/// - 전역 navigatorKey로 안전한 컨텍스트 확보 (showModalBottomSheet/Overlay)
/// - 토글/메모 SharedPreferences 영속화
/// - 드래그 가능한 플로팅 버블 + 90% 높이 바텀시트 패널
class EasyMemo {
  EasyMemo._();

  /// ✅ MaterialApp.navigatorKey 로 연결
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 켜짐/꺼짐 토글 상태
  static final enabled = ValueNotifier<bool>(false);

  /// "YYYY-MM-DD HH:mm | 내용" 형태의 문자열 리스트
  static final notes = ValueListenableNotifier<List<String>>(<String>[]);

  static const _kEnabledKey = 'easy_memo_enabled_v1';
  static const _kNotesKey = 'easy_memo_notes_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;

  /// 앱 시작 시 1회 호출
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;
    notes.value = _prefs!.getStringList(_kNotesKey) ?? const <String>[];

    // 토글 변경 시 저장 + 오버레이 토글
    enabled.addListener(() {
      _prefs?.setBool(_kEnabledKey, enabled.value);
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
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

  /// 메모 패널 열기 (온/오프 스위치는 패널 내부 스위치로 제어)
  static Future<void> openPanel() async {
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openPanel());
      return;
    }
    await showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // 바깥 배경 투명
      builder: (_) => const _EasyMemoSheet(),
    );
  }

  // ----------------- 내부: 오버레이(버블) -----------------

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(builder: (context) => const _EasyMemoBubble());
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
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

/// 드래그 가능한 플로팅 버블(엣지 스냅)
class _EasyMemoBubble extends StatefulWidget {
  const _EasyMemoBubble();

  @override
  State<_EasyMemoBubble> createState() => _EasyMemoBubbleState();
}

class _EasyMemoBubbleState extends State<_EasyMemoBubble> {
  static const double _bubbleSize = 56;
  Offset _pos = const Offset(12, 200);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;

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
          // 좌/우 엣지 스냅
          final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
              ? 8.0
              : screen.width - _bubbleSize - 8.0;
          setState(() => _pos = Offset(snapX, _pos.dy));
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: EasyMemo.openPanel,
            customBorder: const CircleBorder(),
            child: Container(
              width: _bubbleSize,
              height: _bubbleSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.12)),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.sticky_note_2_rounded,
                  color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 메모 바텀시트(90% 높이 · 스위치 · 검색 · 입력 · 스와이프 삭제)
class _EasyMemoSheet extends StatefulWidget {
  const _EasyMemoSheet();

  @override
  State<_EasyMemoSheet> createState() => _EasyMemoSheetState();
}

class _EasyMemoSheetState extends State<_EasyMemoSheet> {
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

    // 90% 높이 바텀시트
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Stack(
          children: [
            // 살짝 블러+틴트 배경 (요즘 감성)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: cs.surface.withOpacity(0.9)),
            ),
            Material(
              color: Colors.transparent,
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
                              valueListenable: EasyMemo.enabled,
                              builder: (_, on, __) => Row(
                                children: [
                                  Text(on ? 'On' : 'Off', style: textTheme.labelMedium?.copyWith(color: cs.outline)),
                                  const SizedBox(width: 6),
                                  Switch(value: on, onChanged: (v) => EasyMemo.enabled.value = v),
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
                          valueListenable: EasyMemo.notes,
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
                                  background: _SwipeDeleteBackground(color: cs.errorContainer, iconColor: cs.onErrorContainer),
                                  onDismissed: (_) {
                                    EasyMemo.removeLine(line);
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
                                              SnackBar(content: const Text('메모를 복사했어요'), behavior: SnackBarBehavior.floating, duration: const Duration(milliseconds: 900)),
                                            );
                                          },
                                        ),
                                        IconButton(
                                          tooltip: '삭제',
                                          icon: const Icon(Icons.delete_outline_rounded),
                                          onPressed: () => EasyMemo.removeLine(line),
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
          ],
        ),
      ),
    );
  }

  // ---------- helpers ----------

  OutlineInputBorder _inputBorder({bool focused = false, ColorScheme? cs}) {
    final color = focused ? (cs ?? Theme.of(context).colorScheme).primary : Theme.of(context).dividerColor.withOpacity(.2);
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
    EasyMemo.add(t);
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
      // 같은 인스턴스여도 강제로 통지하고 싶다면:
      // notifyListeners();
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
