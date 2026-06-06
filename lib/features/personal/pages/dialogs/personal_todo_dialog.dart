import 'package:flutter/material.dart';

import '../../application/personal_todo_store.dart';
import '../../domain/models/personal_todo_item.dart';

Future<bool?> showPersonalTodoDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
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
    await _store.upsert(todo.copyWith(done: !todo.done, updatedAt: DateTime.now()));
    await _load();
  }

  Future<void> _remove(PersonalTodoItem todo) async {
    await _store.remove(todo.id);
    await _load();
  }

  Future<void> _add() async {
    final item = await showDialog<PersonalTodoItem>(
      context: context,
      builder: (_) => const _TodoEditorDialog(),
    );
    if (item == null) return;
    await _store.upsert(item);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.checklist_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('내 차량 할 일', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: _loading
            ? const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))
            : _todos.isEmpty
                ? _EmptyTodo(onAdd: _add)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _todos
                          .map(
                            (todo) => Card(
                              elevation: 0,
                              color: todo.done ? cs.surfaceContainerLow : cs.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
                              ),
                              child: CheckboxListTile(
                                value: todo.done,
                                onChanged: (_) => _toggle(todo),
                                title: Text(
                                  todo.title,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    decoration: todo.done ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                subtitle: Text(
                                  _todoSubtitle(todo),
                                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                                ),
                                secondary: IconButton(
                                  tooltip: '삭제',
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () => _remove(todo),
                                ),
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('닫기')),
        FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('할 일 추가')),
      ],
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
    final picked = await showDatePicker(
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
    if (title.isEmpty) return;
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
    return AlertDialog(
      title: const Text('할 일 추가'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: '할 일', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _plateController, decoration: const InputDecoration(labelText: '차량 번호 또는 메모', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_rounded),
            label: Text(_dueDate == null ? '날짜 선택' : _formatDate(_dueDate!)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}

class _EmptyTodo extends StatelessWidget {
  const _EmptyTodo({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt_rounded, color: cs.primary, size: 42),
          const SizedBox(height: 12),
          Text('아직 등록된 할 일이 없습니다.', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('차량 관련 메모를 남겨두면 홈에서 바로 확인할 수 있어요.', textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('할 일 추가')),
        ],
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
