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

class _SprintProjectEditSheetState extends State<_SprintProjectEditSheet> {
  late final TextEditingController _nameController;
  late String _iconKey;
  DateTime? _targetStartDate;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.project.name);
    _iconKey = widget.project.iconKey;
    _targetStartDate = widget.project.targetStartDate;
    _targetDate = widget.project.targetDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTargetStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _targetStartDate ?? today;
    final firstDate = current.isBefore(today) ? current : today;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _targetStartDate = selected);
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minimum = _targetStartDate ?? today;
    var initial = _targetDate ?? minimum.add(const Duration(days: 7));
    if (initial.isBefore(minimum)) initial = minimum;
    final existing = _targetDate;
    final firstDate = _targetStartDate != null
        ? minimum
        : existing != null && existing.isBefore(minimum)
            ? existing
            : minimum;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _targetDate = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      sprintShowMessage(
        context: context,
        message: '프로젝트 이름을 입력하세요.',
      );
      return;
    }
    if (_targetStartDate != null &&
        _targetDate != null &&
        _targetStartDate!.isAfter(_targetDate!)) {
      sprintShowMessage(
        context: context,
        message: '목표 시작일은 목표 완료일보다 늦을 수 없습니다.',
      );
      return;
    }
    setState(() => _saving = true);
    final result = await widget.store.updateProject(
      projectId: widget.project.id,
      name: name,
      iconKey: _iconKey,
      targetStartDate: _targetStartDate,
      targetDate: _targetDate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    sprintShowMessage(context: context, message: result.message);
    if (result.success) {
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
    final invalidRange = _targetStartDate != null &&
        _targetDate != null &&
        _targetStartDate!.isAfter(_targetDate!);
    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
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
            _ProjectDateField(
              title: '목표 시작일',
              icon: Icons.play_circle_outline_rounded,
              value: _targetStartDate,
              duration: duration,
              onPick: _saving ? null : _pickTargetStartDate,
              onClear: _saving || _targetStartDate == null
                  ? null
                  : () => setState(() => _targetStartDate = null),
            ),
            const SizedBox(height: 10),
            _ProjectDateField(
              title: '목표 완료일',
              icon: Icons.flag_outlined,
              value: _targetDate,
              duration: duration,
              onPick: _saving ? null : _pickTargetDate,
              onClear: _saving || _targetDate == null
                  ? null
                  : () => setState(() => _targetDate = null),
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: invalidRange
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '목표 시작일은 목표 완료일보다 늦을 수 없습니다.',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving || invalidRange ? null : _save,
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

class _ProjectDateField extends StatelessWidget {
  const _ProjectDateField({
    required this.title,
    required this.icon,
    required this.value,
    required this.duration,
    required this.onPick,
    required this.onClear,
  });

  final String title;
  final IconData icon;
  final DateTime? value;
  final Duration duration;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SprintSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      backgroundColor: colors.surfaceContainerLow,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: duration,
                  child: Text(
                    value == null ? '설정하지 않음' : sprintFormatDate(value!),
                    key: ValueKey<String>(
                      '$title-${value?.toIso8601String() ?? 'none'}',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPick,
            child: const Text('선택'),
          ),
          if (value != null)
            IconButton(
              tooltip: '$title 제거',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}
