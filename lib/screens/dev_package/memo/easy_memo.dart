import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// EasyMemo: 전역 navigatorKey를 사용해 안전하게 바텀시트/오버레이를 띄우는 경량 구현.
/// - 메모/토글은 SharedPreferences에 저장
/// - 플로팅 버블(드래그/엣지 스냅)
class EasyMemo {
  EasyMemo._();

  /// ✅ 전역 네비게이터 키: MaterialApp.navigatorKey로 연결됨
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 켜짐/꺼짐 토글
  static final enabled = ValueNotifier<bool>(false);

  /// "YYYY-MM-DD HH:mm | 내용" 문자열 리스트
  static final notes = ValueNotifier<List<String>>(<String>[]);

  static const _kEnabledKey = 'easy_memo_enabled_v1';
  static const _kNotesKey = 'easy_memo_notes_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;

  /// 앱 시작 시 1회
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;
    notes.value = _prefs!.getStringList(_kNotesKey) ?? <String>[];

    enabled.addListener(() {
      _prefs?.setBool(_kEnabledKey, enabled.value);
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
  }

  /// 첫 프레임 이후 오버레이가 필요하면 붙임 (MaterialApp 생성 이후 보장)
  static void mountIfNeeded() {
    if (enabled.value) _showOverlay();
  }

  /// 항상 Navigator의 overlay.context를 우선 사용 → MediaQuery 보장
  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    if (overlayCtx != null) return overlayCtx;
    return navigatorKey.currentContext; // 차선책
  }

  /// 메모 패널 열기 (온/오프 스위치는 패널 내부 스위치로)
  static Future<void> openPanel() async {
    final ctx = _bestContext();
    if (ctx == null) {
      // 아직 네비게이터가 준비 안 됐다면 다음 프레임에 재시도
      WidgetsBinding.instance.addPostFrameCallback((_) => openPanel());
      return;
    }
    await showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 필요시 rootNavigator: true, // <- 루트 네비게이터로 띄우고 싶다면 주석 해제
      builder: (_) => const _EasyMemoSheet(),
    );
  }

  /// 내부: 오버레이(버블)
  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      // 아직 빌드 전이면 다음 프레임에서 재시도
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

  // ---------- 데이터 조작 ----------
  static Future<void> add(String text) async {
    final now = DateTime.now();
    final stamp =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final list = List<String>.from(notes.value)..insert(0, "$stamp | $text");
    notes.value = list;
    await _prefs?.setStringList(_kNotesKey, list);
  }

  static Future<void> removeAt(int index) async {
    final list = List<String>.from(notes.value)..removeAt(index);
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
  Offset pos = const Offset(12, 200);
  final double size = 56;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            pos = Offset(
              (pos.dx + d.delta.dx).clamp(0.0, screen.width - size),
              (pos.dy + d.delta.dy).clamp(
                0.0,
                screen.height - size - MediaQuery.of(context).padding.bottom,
              ),
            );
          });
        },
        onPanEnd: (_) {
          // 좌/우 엣지 스냅
          final snapX =
          (pos.dx + size / 2) < screen.width / 2 ? 8.0 : screen.width - size - 8.0;
          setState(() => pos = Offset(snapX, pos.dy));
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: EasyMemo.openPanel,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade400,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.sticky_note_2_rounded, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// 메모 바텀시트(스위치 포함)
class _EasyMemoSheet extends StatefulWidget {
  const _EasyMemoSheet();

  @override
  State<_EasyMemoSheet> createState() => _EasyMemoSheetState();
}

class _EasyMemoSheetState extends State<_EasyMemoSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.sticky_note_2_rounded),
                    const SizedBox(width: 8),
                    Text('메모', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    // ✅ 온/오프 스위치(패널 내부에서만 제어)
                    ValueListenableBuilder<bool>(
                      valueListenable: EasyMemo.enabled,
                      builder: (_, on, __) => Switch(
                        value: on,
                        onChanged: (v) => EasyMemo.enabled.value = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: '메모를 입력하세요',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (v) {
                          final t = v.trim();
                          if (t.isEmpty) return;
                          EasyMemo.add(t);
                          _ctrl.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final t = _ctrl.text.trim();
                        if (t.isEmpty) return;
                        EasyMemo.add(t);
                        _ctrl.clear();
                      },
                      child: const Text('추가'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: EasyMemo.notes,
                    builder: (_, list, __) {
                      if (list.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('아직 메모가 없습니다.'),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final line = list[i];
                          final split = line.indexOf('|');
                          final time = split >= 0 ? line.substring(0, split).trim() : '';
                          final text = split >= 0 ? line.substring(split + 1).trim() : line;
                          return ListTile(
                            dense: true,
                            title: Text(text),
                            subtitle: time.isNotEmpty ? Text(time) : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => EasyMemo.removeAt(i),
                              tooltip: '삭제',
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
    );
  }
}
