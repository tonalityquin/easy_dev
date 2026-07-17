import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

Future<bool> showSprintProjectEditSheet({
  required BuildContext context,
  required SprintModeStore store,
  required SprintProject project,
}) async {
  final colors = Theme.of(context).colorScheme;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _SprintProjectEditSheet(
      store: store,
      project: project,
    ),
  );
  return result == true;
}

class _SprintProjectEditSheet extends StatefulWidget {
  const _SprintProjectEditSheet({
    required this.store,
    required this.project,
  });

  final SprintModeStore store;
  final SprintProject project;

  @override
  State<_SprintProjectEditSheet> createState() =>
      _SprintProjectEditSheetState();
}

class _SprintProjectEditSheetState
    extends State<_SprintProjectEditSheet> {
  late final TextEditingController _nameController;
  late String _iconKey;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _iconKey = widget.project.iconKey;
    _targetDate = widget.project.targetDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _targetDate ?? today.add(const Duration(days: 7));
    final initialDay = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDay,
      firstDate: initialDay.isBefore(today) ? initialDay : today,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _targetDate = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로젝트 이름을 입력하세요.')),
      );
      return;
    }
    setState(() => _saving = true);
    final saved = await widget.store.updateProject(
      projectId: widget.project.id,
      name: name,
      iconKey: _iconKey,
      targetDate: _targetDate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      sprintShowMessage(
        context: context,
        message: '프로젝트를 수정했습니다.',
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '프로젝트 수정',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '프로젝트 이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '아이콘',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sprintProjectIcons.entries.map((entry) {
                final selected = entry.key == _iconKey;
                return Semantics(
                  button: true,
                  selected: selected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _iconKey = entry.key),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.primaryContainer
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? colors.primary
                              : colors.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Icon(entry.value),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 18),
            SprintSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              backgroundColor: colors.surfaceContainerLow,
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        _targetDate == null
                            ? '목표일 없음'
                            : sprintFormatDate(_targetDate!),
                        key: ValueKey<String>(
                          _targetDate?.toIso8601String() ?? 'none',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickTargetDate,
                    child: const Text('선택'),
                  ),
                  if (_targetDate != null)
                    IconButton(
                      tooltip: '목표일 제거',
                      onPressed: () => setState(() => _targetDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: AnimatedSwitcher(
                duration: duration,
                child: _saving
                    ? const SizedBox(
                        key: ValueKey<String>('saving'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '저장',
                        key: ValueKey<String>('save'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
