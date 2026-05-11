import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../productivity_sheet.dart';
import '../../utils/productivity_tools.dart';

Future<void> showTodoDialog({
  required BuildContext context,
  int? initialFocusTodoId,
}) async {
  await ChillStore.instance.refreshAll();
  if (!context.mounted) return;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'todo',
    barrierColor: Colors.black.withOpacity(0.38),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => TodoDialog(initialFocusTodoId: initialFocusTodoId),
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (ctx, _) {
          final t = curved.value;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}

class ChillTodoRouter {
  ChillTodoRouter._();

  static bool _bound = false;
  static Future<void>? _dialogFuture;

  static void bind(GlobalKey<NavigatorState> navigatorKey) {
    if (_bound) return;
    _bound = true;

    ChillStore.instance.openTodoId.addListener(() {
      final id = ChillStore.instance.consumeOpenTodoId();
      if (id == null) return;
      if (_dialogFuture != null) return;

      final state = navigatorKey.currentState;
      final ctx = state?.overlay?.context ?? state?.context;
      if (ctx == null) return;

      _dialogFuture = showTodoDialog(context: ctx, initialFocusTodoId: id).whenComplete(() {
        _dialogFuture = null;
      });
    });
  }
}

class TodoDialog extends StatelessWidget {
  final int? initialFocusTodoId;

  const TodoDialog({super.key, this.initialFocusTodoId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 860),
            child: Material(
              color: cs.surfaceContainerHighest,
              elevation: 10,
              shadowColor: cs.shadow.withOpacity(0.28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
              ),
              clipBehavior: Clip.antiAlias,
              child: TodoPanel(
                mode: TodoPanelMode.dialog,
                initialFocusTodoId: initialFocusTodoId,
                onClose: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum TodoPanelMode { tab, dialog }

enum _TodoScope { active, done, all }

class TodoPanel extends StatefulWidget {
  final TodoPanelMode mode;
  final VoidCallback? onClose;
  final int? initialFocusTodoId;

  const TodoPanel({
    super.key,
    required this.mode,
    this.onClose,
    this.initialFocusTodoId,
  });

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  final ScrollController _sc = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  _TodoScope _scope = _TodoScope.active;
  String _query = '';
  int? _focusTodoId;

  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();

    _focusTodoId = widget.initialFocusTodoId;
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fromNoti = ChillStore.instance.consumeOpenTodoId();
      if (fromNoti != null) {
        setState(() => _focusTodoId = fromNoti);
      }
      _scrollToFocusIfPossible();
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ChillTodo> _filtered(List<ChillTodo> list) {
    final q = _query.trim().toLowerCase();
    Iterable<ChillTodo> it = list;

    switch (_scope) {
      case _TodoScope.active:
        it = it.where((e) => !e.isDone);
        break;
      case _TodoScope.done:
        it = it.where((e) => e.isDone);
        break;
      case _TodoScope.all:
        break;
    }

    if (q.isNotEmpty) it = it.where((e) => e.displayTitle().toLowerCase().contains(q) || (e.content ?? '').toLowerCase().contains(q));
    return it.toList(growable: false);
  }

  Future<void> _deleteTodo(ChillTodo t) async {
    final ok = await _confirmDelete(
      context,
      title: '할 일 삭제',
      message: '"${t.displayTitle()}"을(를) 삭제할까요?',
    );
    if (!ok) return;

    if (_focusTodoId == t.id) setState(() => _focusTodoId = null);
    await ChillStore.instance.deleteTodo(t);
  }

  Future<void> _clearDone() async {
    final done = ChillStore.instance.todos.value.where((e) => e.isDone).toList(growable: false);
    if (done.isEmpty) return;

    final ok = await _confirmDelete(
      context,
      title: '완료 비우기',
      message: '완료된 할 일을 모두 삭제할까요?',
    );
    if (!ok) return;

    await ChillStore.instance.clearDoneTodos();
  }

  void _scrollToFocusIfPossible() {
    final id = _focusTodoId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[id];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    });
  }

  void _openTodoComposer() {
    widget.onClose?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ProductivitySheet.openPanel(tab: ProductivitySheetTab.todo));
    });
  }

  Widget _topBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ValueListenableBuilder<List<ChillTodo>>(
      valueListenable: ChillStore.instance.todos,
      builder: (_, list, __) {
        final active = list.where((e) => !e.isDone).length;
        final done = list.where((e) => e.isDone).length;

        final title = widget.mode == TodoPanelMode.dialog ? '할 일 정리' : '할 일';
        final subtitle = '진행 $active · 완료 $done';

        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.checklist_rounded, size: 18, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: (tt.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: done == 0 ? null : _clearDone,
              icon: const Icon(Icons.cleaning_services_rounded, size: 18),
              label: const Text('완료 비우기'),
            ),
            if (widget.mode == TodoPanelMode.dialog) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '닫기',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _filters(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final trailing = <Widget>[];
    if (_query.trim().isNotEmpty) {
      trailing.add(
        IconButton(
          tooltip: '지우기',
          onPressed: () => _searchCtrl.clear(),
          icon: const Icon(Icons.clear_rounded),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SearchBar(
            controller: _searchCtrl,
            hintText: '검색',
            leading: const Icon(Icons.search_rounded),
            trailing: trailing,
            elevation: const MaterialStatePropertyAll<double>(0),
            backgroundColor: MaterialStatePropertyAll<Color>(cs.surfaceContainerHigh),
            shadowColor: const MaterialStatePropertyAll<Color>(Colors.transparent),
            padding: const MaterialStatePropertyAll<EdgeInsets>(
              EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SegmentedButton<_TodoScope>(
          segments: const <ButtonSegment<_TodoScope>>[
            ButtonSegment<_TodoScope>(value: _TodoScope.active, label: Text('진행')),
            ButtonSegment<_TodoScope>(value: _TodoScope.done, label: Text('완료')),
            ButtonSegment<_TodoScope>(value: _TodoScope.all, label: Text('전체')),
          ],
          selected: <_TodoScope>{_scope},
          onSelectionChanged: (s) => setState(() => _scope = s.first),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: const MaterialStatePropertyAll<EdgeInsets>(
              EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            backgroundColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return cs.primaryContainer.withOpacity(0.75);
              return cs.surfaceContainerHigh;
            }),
            foregroundColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return cs.onPrimaryContainer;
              return cs.onSurfaceVariant;
            }),
            side: MaterialStatePropertyAll(BorderSide(color: cs.outlineVariant.withOpacity(0.55))),
            shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
        ),
      ],
    );
  }

  Widget _tag(BuildContext context, String text, {bool primary = false}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final bg = primary ? cs.primaryContainer.withOpacity(0.8) : cs.surfaceContainerHigh;
    final fg = primary ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(fontWeight: FontWeight.w800, color: fg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _item(BuildContext context, ChillTodo t) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final meta = <String>[];
    if (t.alarmTimeMinutes != null) meta.add('알림 ${chillFormatTimeMinutes(t.alarmTimeMinutes!)}');
    if (t.mode == ChillTodoMode.b) {
      final c = (t.content ?? '').trim();
      if (c.isNotEmpty) meta.add(c);
    }

    final highlight = _focusTodoId == t.id;

    final border = BorderSide(
      color: highlight ? cs.primary.withOpacity(0.85) : cs.outlineVariant.withOpacity(0.5),
      width: highlight ? 1.2 : 1.0,
    );

    return AnimatedContainer(
      key: _itemKeys[t.id],
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.fromBorderSide(border),
      ),
      child: Dismissible(
        key: ValueKey('todo_${t.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          await _deleteTodo(t);
          return false;
        },
        background: _deleteBg(context),
        child: Material(
          color: t.isDone ? cs.surfaceContainerLow.withOpacity(0.55) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: () async {
              await ChillStore.instance.toggleTodoDone(t);
              if (!mounted) return;
              if (_focusTodoId == t.id) _scrollToFocusIfPossible();
            },
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: t.isDone,
                    onChanged: (_) async {
                      await ChillStore.instance.toggleTodoDone(t);
                      if (!mounted) return;
                      if (_focusTodoId == t.id) _scrollToFocusIfPossible();
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.displayTitle(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.isDone
                              ? (tt.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          )
                              : (tt.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (t.alarmTimeMinutes != null) _tag(context, '알림 ${chillFormatTimeMinutes(t.alarmTimeMinutes!)}', primary: true),
                              if (t.mode == ChillTodoMode.b && (t.content ?? '').trim().isNotEmpty) _tag(context, (t.content ?? '').trim()),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '삭제',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteTodo(t),
                    icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<ChillTodo> filtered) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (filtered.isEmpty) {
      final msg = _query.trim().isNotEmpty
          ? '검색 결과가 없어요.'
          : (_scope == _TodoScope.done ? '완료된 할 일이 없어요.' : '할 일이 없어요.');
      return Center(
        child: Text(
          msg,
          style: (tt.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      controller: _sc,
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final t = filtered[i];
        _itemKeys.putIfAbsent(t.id, () => GlobalKey());
        return _item(ctx, t);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final padding = widget.mode == TodoPanelMode.dialog
        ? const EdgeInsets.fromLTRB(16, 16, 16, 14)
        : const EdgeInsets.fromLTRB(16, 12, 16, 16);

    return Padding(
      padding: padding,
      child: Column(
        children: [
          _topBar(context),
          const SizedBox(height: 12),
          _filters(context),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<List<ChillTodo>>(
              valueListenable: ChillStore.instance.todos,
              builder: (_, list, __) {
                final filtered = _filtered(list);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _scrollToFocusIfPossible();
                });
                return _list(context, filtered);
              },
            ),
          ),
          if (widget.mode == TodoPanelMode.dialog) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _openTodoComposer,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('생성'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.tonal(
                      onPressed: widget.onClose,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHigh,
                        foregroundColor: cs.onSurface,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('닫기'),
                    ),
                  ),
                ),
              ],
            ),
          ]
        ],
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
      color: cs.errorContainer.withOpacity(0.9),
      borderRadius: BorderRadius.circular(18),
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
  final tt = Theme.of(context).textTheme;
  final res = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: Text(title),
      content: Text(message),
      titleTextStyle: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(fontWeight: FontWeight.w900),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  return res == true;
}
