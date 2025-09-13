// lib/screens/dev_package/dev_memo.dart
//
// ※ intl 패키지가 필요합니다. pubspec.yaml에 추가하세요:
// dependencies:
//   intl: ^0.19.0

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_navigator.dart';

class DevMemo {
  DevMemo._();

  /// ✅ MaterialApp.navigatorKey 로 연결
  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// 켜짐/꺼짐 토글 상태
  static final enabled = ValueNotifier<bool>(false);

  /// "YYYY-MM-DD HH:mm | 내용" 형태의 문자열 리스트
  static final notes = ValueListenableNotifier<List<String>>(<String>[]);

  // ---- SharedPreferences Keys ----
  static const _kEnabledKey = 'dev_memo_enabled_v1';
  static const _kNotesKey = 'dev_memo_notes_v1';
  static const _kBubbleXKey = 'dev_memo_bubble_x_v1';
  static const _kBubbleYKey = 'dev_memo_bubble_y_v1';

  /// 노트 보관 상한 (옵션): 초과 시 오래된 항목을 잘라냅니다.
  static const int kMaxNotes = 1000;

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;

  // ===== 패널 토글 상태 & 중복 호출 가드 =====
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

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

  /// (호환용) 기존 API는 토글로 라우팅
  static Future<void> openPanel() => togglePanel();

  /// ✅ 바텀시트 토글 API (메뉴의 "메모 열기"에서 사용)
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

  /// 버블 좌표 저장/복원 (영속화)
  static Future<void> saveBubblePos(Offset pos) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kBubbleXKey, pos.dx);
    await _prefs!.setDouble(_kBubbleYKey, pos.dy);
  }

  static Offset restoreBubblePos() {
    final dx = _prefs?.getDouble(_kBubbleXKey) ?? 12.0;
    final dy = _prefs?.getDouble(_kBubbleYKey) ?? 200.0;
    return Offset(dx, dy);
  }
}

/// 드래그 가능한 플로팅 버블
/// - 탭 시: 기어 회전 + 두 개의 미니 버튼("메모 열기", "플로팅 종료") 가로 펼침/접힘
/// - 배경 탭 시: 접힘
class _DevMemoBubble extends StatefulWidget {
  const _DevMemoBubble();

  @override
  State<_DevMemoBubble> createState() => _DevMemoBubbleState();
}

class _DevMemoBubbleState extends State<_DevMemoBubble> with SingleTickerProviderStateMixin {
  static const double _bubbleSize = 56;
  static const double _miniSize = 44;
  static const double _gap = 60; // 버튼 간 기본 간격(가로)
  late Offset _pos;
  bool _clampedOnce = false;

  // 펼침/접힘 + 기어 회전
  late final AnimationController _ctrl;
  late final Animation<double> _gearTurn; // 0 → 1

  // ✅ 단순/안정 판정: 값만 보고 확장 여부 판단 (리스너가 매 프레임 리빌드 보장)
  bool get _expanded => _ctrl.value > 0.001;

  @override
  void initState() {
    super.initState();
    _pos = DevMemo.restoreBubblePos();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _gearTurn = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // ✅ 애니메이션 값/상태 변화 시마다 리빌드 → 배경 탭 레이어/미니버튼 표시 갱신
    _ctrl.addListener(() => setState(() {}));
    _ctrl.addStatusListener((_) => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_expanded) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    // 첫 빌드 시 화면 경계로 1회 클램프
    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset);
    }

    // ✅ 가로 방향 배치: 왼쪽에 있으면 → 오른쪽(+), 오른쪽이면 → 왼쪽(-)
    final isLeft = (_pos.dx + _bubbleSize / 2) < (screen.width / 2);
    final baseDirX = isLeft ? 1.0 : -1.0;

    // 각 미니버튼의 가로 오프셋(애니메이션 비율 반영)
    final oOpen = Offset(baseDirX * _gap * _gearTurn.value, 0);
    final oExit = Offset(baseDirX * (_gap * 2) * _gearTurn.value, 0);

    return Stack(
      children: [
        // 배경 탭 → 접힘
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleMenu,
              behavior: HitTestBehavior.opaque,
            ),
          ),

        // 미니 버튼 1: 메모 열기 (바텀시트)
        Positioned(
          left: _pos.dx + (_bubbleSize - _miniSize) / 2 + oOpen.dx,
          top: _pos.dy + (_bubbleSize - _miniSize) / 2 + oOpen.dy,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Opacity(
              opacity: _gearTurn.value,
              child: _MiniActionButton(
                size: _miniSize,
                color: cs.secondaryContainer,
                icon: Icons.sticky_note_2_rounded,
                tooltip: '메모 열기',
                label: '메모 열기',
                iconColor: cs.onSecondaryContainer,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await _ctrl.reverse(); // 메뉴 접고
                  await DevMemo.togglePanel(); // 바텀시트 열기
                },
              ),
            ),
          ),
        ),

        // 미니 버튼 2: 플로팅 종료 (enabled=false → overlay 제거)
        Positioned(
          left: _pos.dx + (_bubbleSize - _miniSize) / 2 + oExit.dx,
          top: _pos.dy + (_bubbleSize - _miniSize) / 2 + oExit.dy,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Opacity(
              opacity: _gearTurn.value,
              child: _MiniActionButton(
                size: _miniSize,
                color: cs.errorContainer,
                icon: Icons.power_settings_new_rounded,
                tooltip: '플로팅 종료',
                label: '플로팅 종료',
                iconColor: cs.onErrorContainer,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  // 먼저 메뉴 닫고 → 기능 비활성화
                  await _ctrl.reverse();
                  DevMemo.enabled.value = false; // 리스너에서 overlay 제거 & 상태 저장
                },
              ),
            ),
          ),
        ),

        // 메인 버블 (드래그 + 탭으로 메뉴 토글)
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
              // 좌/우 엣지 스냅
              final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
                  ? 8.0
                  : screen.width - _bubbleSize - 8.0;
              setState(() => _pos = Offset(snapX, _pos.dy));
              await DevMemo.saveBubblePos(_pos);
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleMenu,
                customBorder: const CircleBorder(),
                child: AnimatedBuilder(
                  animation: _gearTurn,
                  builder: (_, __) {
                    return Container(
                      width: _bubbleSize,
                      height: _bubbleSize,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.onSurface.withOpacity(.08)),
                        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                      ),
                      alignment: Alignment.center,
                      child: Transform.rotate(
                        angle: _gearTurn.value * math.pi, // 0 → π (반바퀴)
                        child: Icon(
                          Icons.settings_rounded,
                          color: Colors.white.withOpacity(0.95),
                        ),
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
    final maxX = (screen.width - _bubbleSize).clamp(0.0, double.infinity);
    final maxY = (screen.height - _bubbleSize - bottomInset).clamp(0.0, double.infinity);
    final dx = raw.dx.clamp(0.0, maxX);
    final dy = raw.dy.clamp(0.0, maxY);
    return Offset(dx, dy);
  }
}

class _MiniActionButton extends StatelessWidget {
  final double size;
  final Color color;
  final IconData icon;
  final String tooltip;
  final String label;
  final Color? iconColor;
  final VoidCallback onTap;

  const _MiniActionButton({
    required this.size,
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = iconColor ?? Theme.of(context).colorScheme.onPrimaryContainer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: tooltip,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black.withOpacity(.06)),
                  boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: onColor),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// 메모 바텀시트(풀높이 · 스위치 · 검색 · 입력 · 스와이프 삭제)
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
