import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
    HapticFeedback,
    FilteringTextInputFormatter,
    LengthLimitingTextInputFormatter;
import '../../../app/init/app_navigator.dart';
import 'chat_bot_engine.dart';
import 'chat_bot_tools.dart';

enum ChatBotSheetTab { chat, focus, todo, calendar, memo }

class ChatBot {
  ChatBot._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(true);

  static bool _inited = false;
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  static Future<void> init() async {
    if (_inited) return;
    await ChillStore.instance.init();
    _inited = true;
  }

  static void mountIfNeeded() {
    if (_inited) return;
    init();
  }

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static Future<void> togglePanel() async {
    if (!_inited) await init();
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }

    if (_isPanelOpen) {
      Navigator.of(ctx).maybePop();
      return;
    }

    await openPanel();
  }

  static Future<void> openPanel({
    ChatBotSheetTab tab = ChatBotSheetTab.chat,
  }) async {
    if (!_inited) await init();
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openPanel(tab: tab));
      return;
    }
    if (_isPanelOpen || _panelFuture != null) return;

    _isPanelOpen = true;
    _panelFuture = showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChillSheet(initialTabIndex: tab.index),
    ).whenComplete(() {
      _isPanelOpen = false;
      _panelFuture = null;
    });

    await _panelFuture;
  }
}

class _ChillSheet extends StatefulWidget {
  final int initialTabIndex;

  const _ChillSheet({required this.initialTabIndex});

  @override
  State<_ChillSheet> createState() => _ChillSheetState();
}

class _ChillSheetState extends State<_ChillSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    ChillStore.instance.refreshAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 1.0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: cs.surface,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                const _DragHandle(),
                const SizedBox(height: 10),
                const _Header(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TabBar(
                    controller: _tab,
                    labelColor: cs.primary,
                    unselectedLabelColor: cs.outline,
                    indicatorColor: cs.primary,
                    tabs: const [
                      Tab(icon: Icon(Icons.chat_bubble_rounded), text: '채팅'),
                      Tab(icon: Icon(Icons.timer_rounded), text: '집중'),
                      Tab(icon: Icon(Icons.checklist_rounded), text: '할 일'),
                      Tab(icon: Icon(Icons.calendar_month_rounded), text: '일정'),
                      Tab(icon: Icon(Icons.note_alt_rounded), text: '메모'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: const [
                      _ChatTab(),
                      _FocusTab(),
                      _TodoTab(),
                      _CalendarTab(),
                      _MemoTab(),
                    ],
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

class _Header extends StatelessWidget {
  const _Header();

  Future<void> _rename(BuildContext context) async {
    HapticFeedback.selectionClick();
    final ctrl =
    TextEditingController(text: ChillStore.instance.profile.value.name);
    final cs = Theme.of(context).colorScheme;
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '이름'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (res == null) return;
    await ChillStore.instance.renameCompanion(res);
  }

  Future<void> _reroll(BuildContext context) async {
    HapticFeedback.selectionClick();
    await ChillStore.instance.rerollCompanionSeed();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<ChillCompanionProfile>(
            valueListenable: ChillStore.instance.profile,
            builder: (_, p, __) {
              return _PixelAvatar(seed: p.seed, size: 56);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<ChillCompanionProfile>(
                        valueListenable: ChillStore.instance.profile,
                        builder: (_, p, __) => Text(
                          p.name,
                          style: tt.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '이름',
                      onPressed: () => _rename(context),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    IconButton(
                      tooltip: '외형 변경',
                      onPressed: () => _reroll(context),
                      icon: const Icon(Icons.casino_rounded),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ValueListenableBuilder<String>(
                  valueListenable: ChillStore.instance.headline,
                  builder: (_, s, __) => Text(
                    s,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTab extends StatefulWidget {
  const _ChatTab();

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _sc = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _scrollBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_sc.hasClients) return;
      final pos = _sc.position.maxScrollExtent;
      if (!animated) {
        _sc.jumpTo(pos);
        return;
      }
      _sc.animateTo(
        pos,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    HapticFeedback.selectionClick();
    await ChillStore.instance.sendChatUser(text);
    _scrollBottom();
  }

  Future<void> _clear() async {
    HapticFeedback.selectionClick();
    await ChillStore.instance.clearChat();
    _scrollBottom(animated: false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Text(
                '대화',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: '초기화',
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<List<ChillChatMessage>>(
            valueListenable: ChillStore.instance.chatMessages,
            builder: (_, msgs, __) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollBottom(animated: false));
              if (msgs.isEmpty) {
                return Center(
                  child: Text(
                    '메시지 없음',
                    style: tt.bodyMedium?.copyWith(color: cs.outline),
                  ),
                );
              }
              return ListView.builder(
                controller: _sc,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: msgs.length,
                itemBuilder: (_, i) => _ChatBubble(msg: msgs[i]),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '입력',
                      filled: true,
                      fillColor: cs.surfaceVariant.withOpacity(0.55),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _send,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChillChatMessage msg;

  const _ChatBubble({required this.msg});

  String _hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isUser = msg.role == ChatRole.user;

    final bg = isUser ? cs.primary : cs.surfaceVariant;
    final fg = isUser ? cs.onPrimary : cs.onSurfaceVariant;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );

    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Container(
                decoration: BoxDecoration(color: bg, borderRadius: radius),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  msg.text,
                  style: tt.bodyMedium?.copyWith(color: fg, height: 1.35),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _hhmm(msg.at),
              style: tt.labelSmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusTab extends StatefulWidget {
  const _FocusTab();

  @override
  State<_FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends State<_FocusTab> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start(int minutes) async {
    HapticFeedback.lightImpact();
    await ChillStore.instance.startFocus(minutes: minutes);
  }

  Future<void> _customStart() async {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController(text: '25');
    final res = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('집중 시간'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '분'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(int.tryParse(ctrl.text.trim()) ?? 25),
            child: const Text('시작'),
          ),
        ],
      ),
    );
    if (res == null) return;
    await _start(res);
  }

  Future<void> _stop() async {
    HapticFeedback.mediumImpact();
    await ChillStore.instance.stopFocus();
  }

  Future<void> _doneNow() async {
    HapticFeedback.selectionClick();
    await ChillStore.instance.markFocusDoneFromUi();
  }

  Future<void> _addRoutine() async {
    HapticFeedback.selectionClick();
    final titleCtrl = TextEditingController();
    TimeOfDay? pickedTime;
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('루틴 추가'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: '제목'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pickedTime == null
                            ? '시간 없음'
                            : '${pickedTime!.hour.toString().padLeft(2, '0')}:${pickedTime!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (t == null) return;
                        setState(() => pickedTime = t);
                      },
                      icon: const Icon(Icons.schedule_rounded),
                      label: const Text('선택'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (pickedTime == null) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    await ChillStore.instance
        .addRoutine(title: title, time: pickedTime!, enabled: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<ChillFocusState>(
            valueListenable: ChillStore.instance.focus,
            builder: (_, st, __) {
              final label =
              st.isRunning ? st.remainLabel() : (st.isDone ? '완료' : '대기');
              final sub = st.isRunning
                  ? (st.plannedEndAt == null
                  ? ''
                  : '종료 ${chillFormatDateTime(st.plannedEndAt!)}')
                  : (st.isDone
                  ? (st.plannedEndAt == null
                  ? ''
                  : '종료 ${chillFormatDateTime(st.plannedEndAt!)}')
                  : '');
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '집중',
                            style: tt.labelLarge?.copyWith(color: cs.outline),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: tt.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (sub.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              sub,
                              style: tt.bodySmall?.copyWith(color: cs.outline),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (st.isRunning)
                      Column(
                        children: [
                          FilledButton.icon(
                            onPressed: _stop,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('중단'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _doneNow,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('완료'),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          FilledButton.icon(
                            onPressed: () => _start(25),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('25분'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _customStart,
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('직접'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '루틴',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: '루틴 추가',
                onPressed: _addRoutine,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Expanded(
            child: ValueListenableBuilder<List<ChillRoutine>>(
              valueListenable: ChillStore.instance.routines,
              builder: (_, list, __) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '루틴 없음',
                      style: tt.bodyMedium?.copyWith(color: cs.outline),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = list[i];
                    final hh = (r.timeMinutes ~/ 60).toString().padLeft(2, '0');
                    final mm = (r.timeMinutes % 60).toString().padLeft(2, '0');
                    return Dismissible(
                      key: ValueKey('routine_${r.id}'),
                      background: _deleteBg(context),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => ChillStore.instance.deleteRoutine(r),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('$hh:$mm'),
                          trailing: Switch(
                            value: r.enabled,
                            onChanged: (_) =>
                                ChillStore.instance.toggleRoutineEnabled(r),
                          ),
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
    );
  }
}

class _TodoTab extends StatefulWidget {
  const _TodoTab();

  @override
  State<_TodoTab> createState() => _TodoTabState();
}

class _TodoTabState extends State<_TodoTab> {
  ChillTodoMode _mode = ChillTodoMode.a;

  final TextEditingController _memoCtrl = TextEditingController();
  final TextEditingController _plateCtrl = TextEditingController();

  String _content = '';
  int? _alarmMinutes;

  @override
  void dispose() {
    _memoCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAlarmTime() async {
    HapticFeedback.selectionClick();
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
    );
    if (t == null) return;
    setState(() => _alarmMinutes = t.hour * 60 + t.minute);
  }

  void _clearAlarmTime() {
    HapticFeedback.selectionClick();
    setState(() => _alarmMinutes = null);
  }

  void _clearPlate() {
    _plateCtrl.clear();
    if (mounted) setState(() {});
  }

  void _insertPhrase(String phrase) {
    final p = phrase.trim();
    if (p.isEmpty) return;
    setState(() {
      final cur = _content.trimRight();
      if (cur.isEmpty) {
        _content = p;
      } else {
        _content = '$cur $p';
      }
    });
  }

  void _clearContent() {
    setState(() => _content = '');
  }

  Future<void> _addPhrase() async {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('단어 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '단어'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final word = ctrl.text.trim();
    if (word.isEmpty) return;
    await ChillStore.instance.addTodoPhrase(word);
  }

  Future<void> _create() async {
    HapticFeedback.selectionClick();

    if (_mode == ChillTodoMode.a) {
      final title = _memoCtrl.text.trim();
      if (title.isEmpty) return;
      _memoCtrl.clear();
      await ChillStore.instance
          .addTodoA(title: title, alarmTimeMinutes: _alarmMinutes);
      setState(() => _alarmMinutes = null);
      return;
    }

    final plate = _plateCtrl.text.trim();
    final content = _content.trim();
    if (plate.isEmpty && content.isEmpty) return;

    await ChillStore.instance.addTodoB(
      plate: plate,
      content: content,
      alarmTimeMinutes: _alarmMinutes,
    );

    setState(() {
      _plateCtrl.clear();
      _content = '';
      _alarmMinutes = null;
    });
  }

  Widget _modeSelector(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget chip({required ChillTodoMode mode, required String label}) {
      final selected = _mode == mode;
      return ChoiceChip(
        label: Text(
          label,
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        selected: selected,
        onSelected: (_) => setState(() => _mode = mode),
        selectedColor: cs.primary.withOpacity(0.18),
        side: BorderSide(
          color: selected
              ? cs.primary.withOpacity(0.65)
              : cs.outlineVariant.withOpacity(0.7),
        ),
      );
    }

    return Row(
      children: [
        chip(mode: ChillTodoMode.a, label: '모드 A'),
        const SizedBox(width: 10),
        chip(mode: ChillTodoMode.b, label: '모드 B'),
      ],
    );
  }

  Widget _alarmRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final label = _alarmMinutes == null
        ? '-'
        : chillFormatTimeMinutes(_alarmMinutes!);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '알림',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: '선택',
            onPressed: _pickAlarmTime,
            icon: const Icon(Icons.schedule_rounded),
          ),
          IconButton(
            tooltip: '지우기',
            onPressed: _alarmMinutes == null ? null : _clearAlarmTime,
            icon: const Icon(Icons.clear_rounded),
          ),
        ],
      ),
    );
  }

  Widget _memoForm(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _memoCtrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '할 일 입력',
            filled: true,
            fillColor: cs.surfaceVariant.withOpacity(0.45),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _alarmRow(context),
      ],
    );
  }

  Widget _carForm(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _plateCtrl,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: false,
            signed: false,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '번호판',
            filled: true,
            fillColor: cs.surfaceVariant.withOpacity(0.45),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            suffixIcon: IconButton(
              tooltip: '지우기',
              onPressed: _plateCtrl.text.trim().isEmpty ? null : _clearPlate,
              icon: Icon(Icons.clear_rounded, color: cs.onSurfaceVariant),
            ),
          ),
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
          onChanged: (_) {
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '내용',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              tooltip: '단어 추가',
              onPressed: _addPhrase,
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: cs.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: '내용 지우기',
              onPressed: _content.trim().isEmpty ? null : _clearContent,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            _content.trim().isEmpty ? '내용 없음' : _content,
            style: tt.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<String>>(
          valueListenable: ChillStore.instance.todoPhrases,
          builder: (_, list, __) {
            if (list.isEmpty) return const SizedBox.shrink();
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in list)
                  ActionChip(
                    label: Text(w),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _insertPhrase(w);
                    },
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        _alarmRow(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '할 일 생성',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton.icon(
                onPressed: _create,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('추가'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _modeSelector(context),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: _mode == ChillTodoMode.a ? _memoForm(context) : _carForm(context),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              '완료/정리는 다이얼로그에서 처리',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarTab extends StatelessWidget {
  const _CalendarTab();

  Future<void> _add(BuildContext context) async {
    HapticFeedback.selectionClick();
    final titleCtrl = TextEditingController();
    DateTime? startAt;
    DateTime? endAt;
    DateTime? remindAt;
    bool allDay = false;
    final cs = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickStart() async {
            final dt = await _pickDateTime(context);
            if (dt == null) return;
            setState(() => startAt = dt);
          }

          Future<void> pickEnd() async {
            final dt = await _pickDateTime(context);
            if (dt == null) return;
            setState(() => endAt = dt);
          }

          Future<void> pickRemind() async {
            final dt = await _pickDateTime(context);
            if (dt == null) return;
            setState(() => remindAt = dt);
          }

          return AlertDialog(
            title: const Text('일정 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '제목'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: allDay,
                    onChanged: (v) => setState(() => allDay = v),
                    title: const Text('종일'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  _dtRow(
                    context,
                    label: '시작',
                    value: startAt,
                    onPick: pickStart,
                    onClear: () => setState(() => startAt = null),
                  ),
                  const SizedBox(height: 8),
                  _dtRow(
                    context,
                    label: '종료',
                    value: endAt,
                    onPick: pickEnd,
                    onClear: () => setState(() => endAt = null),
                  ),
                  const SizedBox(height: 8),
                  _dtRow(
                    context,
                    label: '알림',
                    value: remindAt,
                    onPick: pickRemind,
                    onClear: () => setState(() => remindAt = null),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final s = startAt ?? DateTime.now();
    await ChillStore.instance.addEvent(
      title: title,
      startAt: s,
      endAt: endAt,
      allDay: allDay,
      remindAt: remindAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '일정',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Expanded(
            child: ValueListenableBuilder<List<ChillEvent>>(
              valueListenable: ChillStore.instance.events,
              builder: (_, list, __) {
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      '일정 없음',
                      style: tt.bodyMedium?.copyWith(color: cs.outline),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final e = list[i];
                    final when = e.allDay
                        ? '종일 · ${chillFormatDateTime(e.startAt).split(' ').first}'
                        : chillFormatDateTime(e.startAt);
                    final meta = <String>[when];
                    if (e.remindAt != null) {
                      meta.add('알림 ${chillFormatDateTime(e.remindAt!)}');
                    }
                    if (e.isLocked) {
                      meta.add('삭제 불가');
                    }
                    return Dismissible(
                      key: ValueKey('event_${e.id}'),
                      background: _deleteBg(context),
                      direction: e.isLocked
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
                      confirmDismiss: (_) => e.isLocked
                          ? Future<bool>.value(false)
                          : _confirmDelete(
                              ctx,
                              title: '일정 삭제',
                              message: '삭제',
                            ),
                      onDismissed: (_) => ChillStore.instance.deleteEvent(e),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: e.isLocked
                                ? cs.primary.withOpacity(0.45)
                                : cs.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            meta.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: Icon(
                            e.isLocked ? Icons.lock_rounded : Icons.event_rounded,
                          ),
                          trailing: e.isLocked
                              ? Icon(
                                  Icons.lock_outline_rounded,
                                  color: cs.primary,
                                )
                              : IconButton(
                                  tooltip: '삭제',
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: cs.outline,
                                  ),
                                  onPressed: () async {
                                    final ok = await _confirmDelete(
                                      ctx,
                                      title: '일정 삭제',
                                      message: '삭제',
                                    );
                                    if (!ok) return;
                                    await ChillStore.instance.deleteEvent(e);
                                  },
                                ),
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
    );
  }
}

class _MemoTab extends StatelessWidget {
  const _MemoTab();

  Future<void> _openEditor(BuildContext context, {ChillNote? note}) async {
    HapticFeedback.selectionClick();
    final titleCtrl = TextEditingController(text: note?.title ?? '');
    final contentCtrl = TextEditingController(text: note?.content ?? '');
    final cs = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(note == null ? '메모 추가' : '메모 수정'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(hintText: '제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contentCtrl,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(hintText: '내용'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final content = contentCtrl.text.trim();
    final title = titleCtrl.text.trim();
    if (content.isEmpty && title.isEmpty) return;
    await ChillStore.instance
        .upsertNote(id: note?.id, title: title, content: content);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '메모',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Expanded(
            child: ValueListenableBuilder<List<ChillNote>>(
              valueListenable: ChillStore.instance.notes,
              builder: (_, list, __) {
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      '메모 없음',
                      style: tt.bodyMedium?.copyWith(color: cs.outline),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final n = list[i];
                    final title =
                    n.title.trim().isEmpty ? '(제목 없음)' : n.title.trim();
                    final preview = n.content.trim().replaceAll('\n', ' ');
                    final short = preview.length > 80
                        ? '${preview.substring(0, 80)}…'
                        : preview;
                    return Dismissible(
                      key: ValueKey('note_${n.id}'),
                      background: _deleteBg(context),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(
                        ctx,
                        title: '메모 삭제',
                        message: '삭제',
                      ),
                      onDismissed: (_) => ChillStore.instance.deleteNote(n),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        child: ListTile(
                          onTap: () => _openEditor(context, note: n),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            short,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${n.updatedAt.month}/${n.updatedAt.day}',
                                style: tt.labelSmall?.copyWith(color: cs.outline),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: '삭제',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.outline,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                                onPressed: () async {
                                  final ok = await _confirmDelete(
                                    ctx,
                                    title: '메모 삭제',
                                    message: '삭제',
                                  );
                                  if (!ok) return;
                                  await ChillStore.instance.deleteNote(n);
                                },
                              ),
                            ],
                          ),
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
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

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

Widget _deleteBg(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 18),
    decoration: BoxDecoration(
      color: cs.errorContainer.withOpacity(0.85),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
  );
}

Future<bool> _confirmDelete(
    BuildContext context, {
      required String title,
      required String message,
    }) async {
  final cs = Theme.of(context).colorScheme;
  final res = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          ),
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  return res == true;
}

Widget _dtRow(
    BuildContext context, {
      required String label,
      required DateTime? value,
      required VoidCallback onPick,
      required VoidCallback onClear,
    }) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: tt.bodyMedium?.copyWith(color: cs.outline),
        ),
      ),
      Expanded(
        child: Text(
          value == null ? '-' : chillFormatDateTime(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      IconButton(
        tooltip: '선택',
        onPressed: onPick,
        icon: const Icon(Icons.event_available_rounded),
      ),
      IconButton(
        tooltip: '지우기',
        onPressed: onClear,
        icon: const Icon(Icons.clear_rounded),
      ),
    ],
  );
}

Future<DateTime?> _pickDateTime(BuildContext context) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 2),
    initialDate: now,
  );
  if (d == null) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now),
  );
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

class _PixelAvatar extends StatelessWidget {
  final int seed;
  final double size;

  const _PixelAvatar({required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        size: Size.square(size),
        painter: _PixelAvatarPainter(
          seed: seed,
          surface: cs.surfaceVariant,
          accent: cs.primary,
        ),
      ),
    );
  }
}

class _PixelAvatarPainter extends CustomPainter {
  _PixelAvatarPainter({
    required this.seed,
    required this.surface,
    required this.accent,
  });

  final int seed;
  final Color surface;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final cell = size.width / 16.0;
    final bg = Paint()..color = surface.withOpacity(0.9);
    canvas.drawRect(Offset.zero & size, bg);

    final base =
        Color.lerp(accent, Colors.black, 0.25 + (rng.nextDouble() * 0.25)) ??
            accent;
    final alt =
        Color.lerp(accent, Colors.white, 0.20 + (rng.nextDouble() * 0.25)) ??
            accent;
    final pBase = Paint()..color = base.withOpacity(0.95);
    final pAlt = Paint()..color = alt.withOpacity(0.95);

    for (int y = 2; y < 15; y++) {
      for (int x = 0; x < 8; x++) {
        final v = rng.nextInt(100);
        if (v < 22) continue;
        final useAlt = v > 78;
        final px = x;
        final mx = 15 - x;
        final rect1 = Rect.fromLTWH(px * cell, y * cell, cell, cell);
        final rect2 = Rect.fromLTWH(mx * cell, y * cell, cell, cell);
        canvas.drawRect(rect1, useAlt ? pAlt : pBase);
        canvas.drawRect(rect2, useAlt ? pAlt : pBase);
      }
    }

    final eye = Paint()..color = Colors.black.withOpacity(0.85);
    final eyeY = 6.5 * cell;
    canvas.drawRect(Rect.fromLTWH(5.5 * cell, eyeY, cell, cell), eye);
    canvas.drawRect(Rect.fromLTWH(9.5 * cell, eyeY, cell, cell), eye);

    final mouth = Paint()..color = Colors.black.withOpacity(0.60);
    canvas.drawRect(
      Rect.fromLTWH(7.5 * cell, 10.5 * cell, 2 * cell, cell),
      mouth,
    );
  }

  @override
  bool shouldRepaint(covariant _PixelAvatarPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.surface != surface ||
        oldDelegate.accent != accent;
  }
}
