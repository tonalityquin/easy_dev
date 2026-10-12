import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../application/single_inside_diagnostics.dart';
import '../hot_keys/single_inside_hot_key_content.dart';

Future<SingleInsideHotKeyConfig?> showSingleInsideHotKeySettingsDialog({
  required BuildContext context,
  required SingleInsideHotKeyConfig initial,
  required List<SingleInsideHotKeyContent> available,
  required Future<void> Function() onDeveloperStatus,
}) {
  return showDialog<SingleInsideHotKeyConfig>(
    context: context,
    builder: (context) => _SingleInsideHotKeySettingsDialog(
      initial: initial,
      available: available,
      onDeveloperStatus: onDeveloperStatus,
    ),
  );
}

class _SingleInsideHotKeySettingsDialog extends StatefulWidget {
  const _SingleInsideHotKeySettingsDialog({
    required this.initial,
    required this.available,
    required this.onDeveloperStatus,
  });

  final SingleInsideHotKeyConfig initial;
  final List<SingleInsideHotKeyContent> available;
  final Future<void> Function() onDeveloperStatus;

  @override
  State<_SingleInsideHotKeySettingsDialog> createState() =>
      _SingleInsideHotKeySettingsDialogState();
}

class _SingleInsideHotKeySettingsDialogState
    extends State<_SingleInsideHotKeySettingsDialog> {
  late List<SingleInsideHotKeyContent?> _slots;
  int _selectedSlot = 1;

  @override
  void initState() {
    super.initState();
    _slots = widget.initial.slots.toList(growable: true);
    SingleInsideDiagnostics.log(
      'hotkey',
      'settings_open slot1=${_slots[0]?.name ?? 'empty'} slot2=${_slots[1]?.name ?? 'empty'} slot3=${_slots[2]?.name ?? 'empty'} slot4=${_slots[3]?.name ?? 'empty'} available=${widget.available.map((item) => item.name).join(',')}',
    );
  }

  SingleInsideHotKeyConfig get _config => SingleInsideHotKeyConfig(
        slot1: _slots[0],
        slot2: _slots[1],
        slot3: _slots[2],
        slot4: _slots[3],
      );

  Future<void> _selectSlot(int slot) async {
    if (_selectedSlot == slot) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _selectedSlot = slot);
    SingleInsideDiagnostics.log(
      'hotkey',
      'settings_layout_select slot=$slot value=${_slots[slot - 1]?.name ?? 'empty'}',
    );
  }

  bool _usedByOtherSlot(SingleInsideHotKeyContent content) {
    for (var index = 0; index < _slots.length; index++) {
      if (index == _selectedSlot - 1) continue;
      if (_slots[index] == content) return true;
    }
    return false;
  }

  Future<void> _selectContent(SingleInsideHotKeyContent? value) async {
    if (value != null && _usedByOtherSlot(value)) return;
    final index = _selectedSlot - 1;
    final before = _slots[index];
    if (before == value) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _slots[index] = value);
    SingleInsideDiagnostics.log(
      'hotkey',
      'settings_select slot=$_selectedSlot before=${before?.name ?? 'empty'} after=${value?.name ?? 'empty'}',
    );
  }

  void _cancel() {
    SingleInsideDiagnostics.log(
      'hotkey',
      'settings_cancel slot1=${_slots[0]?.name ?? 'empty'} slot2=${_slots[1]?.name ?? 'empty'} slot3=${_slots[2]?.name ?? 'empty'} slot4=${_slots[3]?.name ?? 'empty'}',
    );
    Navigator.of(context).pop();
  }

  void _save() {
    final next = _config;
    if (next.hasDuplicate) return;
    SingleInsideDiagnostics.log(
      'hotkey',
      'settings_submit slot1=${_slots[0]?.name ?? 'empty'} slot2=${_slots[1]?.name ?? 'empty'} slot3=${_slots[2]?.name ?? 'empty'} slot4=${_slots[3]?.name ?? 'empty'}',
    );
    Navigator.of(context).pop(next);
  }

  Future<void> _showDeveloperStatus() async {
    await HapticFeedback.mediumImpact();
    SingleInsideDiagnostics.log(
      'status',
      'developer_status_request source=hotkey_settings_visual_layout selectedSlot=$_selectedSlot slot1=${_slots[0]?.name ?? 'empty'} slot2=${_slots[1]?.name ?? 'empty'} slot3=${_slots[2]?.name ?? 'empty'} slot4=${_slots[3]?.name ?? 'empty'}',
    );
    await widget.onDeveloperStatus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: viewportHeight * .84,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: _showDeveloperStatus,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Text(
                  '빠른 실행 설정',
                  style: text.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(label: '빠른 실행 배치'),
                    _SlotLayoutPreview(
                      slots: _slots,
                      selectedSlot: _selectedSlot,
                      onSelectSlot: _selectSlot,
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel(label: '콘텐츠'),
                    OpsDockListSurface(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ContentSelectableRow(
                            content: null,
                            selected: _slots[_selectedSlot - 1] == null,
                            disabled: false,
                            onTap: () => _selectContent(null),
                          ),
                          for (final content in widget.available) ...[
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: tokens.borderSubtle,
                            ),
                            _ContentSelectableRow(
                              content: content,
                              selected: _slots[_selectedSlot - 1] == content,
                              disabled: _usedByOtherSlot(content),
                              onTap: () => _selectContent(content),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancel,
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('저장'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        label,
        style: text.labelLarge?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SlotLayoutPreview extends StatelessWidget {
  const _SlotLayoutPreview({
    required this.slots,
    required this.selectedSlot,
    required this.onSelectSlot,
  });

  final List<SingleInsideHotKeyContent?> slots;
  final int selectedSlot;
  final Future<void> Function(int slot) onSelectSlot;

  @override
  Widget build(BuildContext context) {
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          height: 188,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SlotPreviewCell(
                        content: slots[0],
                        selected: selectedSlot == 1,
                        onTap: () => onSelectSlot(1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SlotPreviewCell(
                        content: slots[1],
                        selected: selectedSlot == 2,
                        onTap: () => onSelectSlot(2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SlotPreviewCell(
                        content: slots[2],
                        selected: selectedSlot == 3,
                        onTap: () => onSelectSlot(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SlotPreviewCell(
                        content: slots[3],
                        selected: selectedSlot == 4,
                        onTap: () => onSelectSlot(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotPreviewCell extends StatefulWidget {
  const _SlotPreviewCell({
    required this.content,
    required this.selected,
    required this.onTap,
  });

  final SingleInsideHotKeyContent? content;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SlotPreviewCell> createState() => _SlotPreviewCellState();
}

class _SlotPreviewCellState extends State<_SlotPreviewCell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = widget.content;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: content?.title ?? '비어 있음',
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .975 : 1,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: widget.selected
                    ? tokens.surfaceSelected
                    : _pressed
                        ? tokens.surfaceSelected.withOpacity(.55)
                        : tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      widget.selected ? tokens.accent : tokens.borderSubtle,
                  width: widget.selected ? 1.5 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: AnimatedSwitcher(
                      duration:
                          reduceMotion ? Duration.zero : CommonUiMotion.component,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: .94, end: 1)
                                .animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey<String>(content?.name ?? 'empty'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            content?.icon ?? Icons.add_rounded,
                            size: 24,
                            color: widget.selected
                                ? tokens.accent
                                : tokens.iconSecondary,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            content?.title ?? '비어 있음',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: widget.selected
                                  ? tokens.accent
                                  : tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              height: 1.12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: AnimatedScale(
                      duration:
                          reduceMotion ? Duration.zero : CommonUiMotion.selection,
                      curve: CommonUiMotion.enter,
                      scale: widget.selected ? 1 : 0,
                      child: AnimatedOpacity(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        opacity: widget.selected ? 1 : 0,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: tokens.accent,
                        ),
                      ),
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
}

class _ContentSelectableRow extends StatelessWidget {
  const _ContentSelectableRow({
    required this.content,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final SingleInsideHotKeyContent? content;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final row = OpsDockSelectableRowSurface(
      selected: selected,
      selectionColor: tokens.accent,
      selectedContainer: tokens.surfaceSelected,
      onTap: disabled ? () {} : onTap,
      child: Row(
        children: [
          Icon(
            content?.icon ?? Icons.remove_circle_outline_rounded,
            size: 18,
            color: selected ? tokens.accent : tokens.iconSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              content?.title ?? '비우기',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (disabled)
            Text(
              '사용중',
              style: text.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            )
          else if (selected)
            Icon(Icons.check_rounded, size: 18, color: tokens.accent),
        ],
      ),
    );
    if (!disabled) return row;
    return IgnorePointer(
      child: Opacity(opacity: .56, child: row),
    );
  }
}
