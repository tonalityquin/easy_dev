import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/personal_todo_store.dart';
import '../../domain/models/personal_todo_item.dart';
import '../widgets/personal_prompt_components.dart';

Future<bool?> showPersonalTodoDialog(BuildContext context) {
  return showPromptOverlayDialog<bool>(
    context: context,
    builder: (_) => const PersonalTodoDialog(),
  );
}

class PersonalTodoDialog extends StatefulWidget {
  const PersonalTodoDialog({super.key});

  @override
  State<PersonalTodoDialog> createState() => _PersonalTodoDialogState();
}

class _PersonalTodoDialogState extends State<PersonalTodoDialog> {
  final PersonalTodoStore _store = PersonalTodoStore();
  List<PersonalTodoItem> _todos = const <PersonalTodoItem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final todos = await _store.load();
    if (!mounted) return;
    setState(() {
      _todos = todos;
      _loading = false;
    });
  }

  Future<void> _toggle(PersonalTodoItem todo) async {
    HapticFeedback.selectionClick();
    await _store.upsert(
      todo.copyWith(done: !todo.done, updatedAt: DateTime.now()),
    );
    await _load();
  }

  Future<void> _remove(PersonalTodoItem todo) async {
    HapticFeedback.mediumImpact();
    await _store.remove(todo.id);
    await _load();
  }

  Future<void> _add() async {
    final item = await showPromptOverlayDialog<PersonalTodoItem>(
      context: context,
      builder: (_) => const _TodoEditorDialog(),
    );
    if (item == null) return;
    await _store.upsert(item);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: size.height * .82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(
                        PromptUiShapes.control,
                      ),
                    ),
                    child: Icon(
                      Icons.checklist_rounded,
                      color: tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '내 차량 할 일',
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PersonalPromptStatusPill(
                    label: '${_todos.where((todo) => !todo.done).length}개 진행',
                    foreground: tokens.statusSettlementPending,
                    background: tokens.statusSettlementPendingContainer,
                    icon: Icons.pending_actions_rounded,
                  ),
                  const SizedBox(width: 6),
                  PromptIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(false),
                    haptic: PromptHaptic.selection,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 14),
              Flexible(
                child: PersonalPromptAnimatedSwap(
                  stateKey: _loading
                      ? 'loading'
                      : _todos.isEmpty
                          ? 'empty'
                          : 'list-${_todos.length}',
                  alignment: Alignment.topCenter,
                  child: _loading
                      ? const Center(
                          child: PersonalPromptLoadingState(
                            label: '할 일을 불러오는 중입니다.',
                          ),
                        )
                      : _todos.isEmpty
                          ? PersonalPromptEmptyState(
                              icon: Icons.task_alt_rounded,
                              title: '아직 등록된 할 일이 없습니다.',
                              message: '차량 관련 메모를 남겨두면 홈에서 바로 확인할 수 있습니다.',
                              actionLabel: '할 일 추가',
                              onAction: _add,
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _todos.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final todo = _todos[index];
                                return PromptAnimatedReveal(
                                  key: ValueKey<String>(todo.id),
                                  delay: Duration(milliseconds: index * 24),
                                  child: AnimatedContainer(
                                    duration: personalPromptDuration(
                                      context,
                                      PromptUiMotion.selection,
                                    ),
                                    decoration: BoxDecoration(
                                      color: todo.done
                                          ? tokens.surfaceOverlay
                                          : tokens.surfaceRaised,
                                      borderRadius: BorderRadius.circular(
                                        PromptUiShapes.card,
                                      ),
                                      border: Border.all(
                                        color: todo.done
                                            ? tokens.statusSynchronized
                                                .withOpacity(.34)
                                            : tokens.borderSubtle,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: todo.done,
                                      onChanged: (_) => _toggle(todo),
                                      title: Text(
                                        todo.title,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: tokens.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          decoration: todo.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: Text(
                                        _todoSubtitle(todo),
                                        style: textTheme.bodySmall?.copyWith(
                                          color: tokens.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      secondary: PromptIconButton(
                                        icon: Icons.delete_outline_rounded,
                                        tooltip: '삭제',
                                        onPressed: () => _remove(todo),
                                        haptic: PromptHaptic.medium,
                                      ),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ),
              const SizedBox(height: 16),
              PromptButton(
                label: '할 일 추가',
                icon: Icons.add_rounded,
                expand: true,
                haptic: PromptHaptic.light,
                onPressed: _add,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoEditorDialog extends StatefulWidget {
  const _TodoEditorDialog();

  @override
  State<_TodoEditorDialog> createState() => _TodoEditorDialogState();
}

class _TodoEditorDialogState extends State<_TodoEditorDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  DateTime? _dueDate;

  @override
  void dispose() {
    _titleController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showPromptDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() => _dueDate = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      HapticFeedback.mediumImpact();
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).pop(
      PersonalTodoItem(
        id: 'todo_${now.microsecondsSinceEpoch}',
        title: title,
        plateNumber: _plateController.text.trim(),
        dueDate: _dueDate,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.add_task_rounded, color: tokens.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '할 일 추가',
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '할 일',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _plateController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '차량 번호 또는 메모',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              PromptButton(
                label: _dueDate == null ? '날짜 선택' : _formatDate(_dueDate!),
                icon: Icons.event_rounded,
                variant: PromptButtonVariant.secondary,
                expand: true,
                haptic: PromptHaptic.selection,
                onPressed: _pickDate,
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: PromptButton(
                      label: '취소',
                      variant: PromptButtonVariant.tertiary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PromptButton(
                      label: '저장',
                      icon: Icons.check_rounded,
                      haptic: PromptHaptic.light,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _todoSubtitle(PersonalTodoItem todo) {
  final parts = <String>[];
  if (todo.plateNumber.trim().isNotEmpty) parts.add(todo.plateNumber.trim());
  if (todo.dueDate != null) parts.add(_formatDate(todo.dueDate!));
  return parts.isEmpty ? '날짜 없음' : parts.join(' · ');
}

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${d.year}.${two(d.month)}.${two(d.day)}';
}
