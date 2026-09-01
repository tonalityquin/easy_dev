import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_location_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/location_plain_settings_draft.dart';

class LocationPlainSectionEditorDialog extends StatefulWidget {
  const LocationPlainSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.trace,
    required this.onApply,
  });

  final LocationPlainSettingsSection section;
  final LocationPlainSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final ValueChanged<LocationPlainSettingsDraft> onApply;

  @override
  State<LocationPlainSectionEditorDialog> createState() =>
      _LocationPlainSectionEditorDialogState();
}

class _LocationPlainSectionEditorDialogState
    extends State<LocationPlainSectionEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialDraft.name);
    _capacityController = TextEditingController(
      text: widget.initialDraft.capacity.toString(),
    );
    widget.trace.log(
      '텍스트형 구역 section editor open section=${widget.section.name} nameLength=${widget.initialDraft.name.length} capacity=${widget.initialDraft.capacity}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case LocationPlainSettingsSection.identity:
        return '텍스트형 구역 기본 정보';
      case LocationPlainSettingsSection.capacity:
        return '수용 가능 차량 수';
    }
  }

  String get _nameError {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return '구역명을 입력해 주세요.';
    if (name.length > 40) return '구역명은 40자 이하로 입력해 주세요.';
    return '';
  }

  int? get _capacity => int.tryParse(_capacityController.text.trim());

  String get _capacityError {
    final value = _capacity;
    if (value == null || value < 0) {
      return '수용 가능 차량 수는 0 이상이어야 합니다.';
    }
    if (value > 9999) return '수용 가능 차량 수는 9999 이하로 입력해 주세요.';
    return '';
  }

  void _apply() {
    setState(() => _submitted = true);
    switch (widget.section) {
      case LocationPlainSettingsSection.identity:
        if (_nameError.isNotEmpty) {
          widget.trace.log('텍스트형 구역 기본 정보 validation fail reason=$_nameError');
          return;
        }
        final name =
            _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        widget.trace.log('텍스트형 구역 기본 정보 apply nameLength=${name.length}');
        widget.onApply(widget.initialDraft.copyWith(name: name));
        Navigator.of(context, rootNavigator: true).pop(true);
        return;
      case LocationPlainSettingsSection.capacity:
        if (_capacityError.isNotEmpty) {
          widget.trace.log('텍스트형 구역 수용 대수 validation fail reason=$_capacityError');
          return;
        }
        final capacity = _capacity!;
        widget.trace.log('텍스트형 구역 수용 대수 apply capacity=$capacity');
        widget.onApply(widget.initialDraft.copyWith(capacity: capacity));
        Navigator.of(context, rootNavigator: true).pop(true);
        return;
    }
  }

  void _cancel() {
    widget.trace.log('텍스트형 구역 section editor cancel section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log(
      '텍스트형 구역 section developer status requested section=${widget.section.name}',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      failure: _submitted &&
          ((widget.section == LocationPlainSettingsSection.identity &&
                  _nameError.isNotEmpty) ||
              (widget.section == LocationPlainSettingsSection.capacity &&
                  _capacityError.isNotEmpty)),
    );
  }

  Widget _buildEditor(BuildContext context) {
    switch (widget.section) {
      case LocationPlainSettingsSection.identity:
        return TextField(
          controller: _nameController,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
          ],
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          onSubmitted: (_) => _apply(),
          decoration: opsInputDecoration(
            context,
            label: '구역명',
            prefixIcon: const Icon(Icons.text_fields_rounded),
            errorText:
                _submitted && _nameError.isNotEmpty ? _nameError : null,
          ),
        );
      case LocationPlainSettingsSection.capacity:
        return TextField(
          controller: _capacityController,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          onSubmitted: (_) => _apply(),
          decoration: opsInputDecoration(
            context,
            label: '수용 가능 차량 수',
            prefixIcon: const Icon(Icons.local_parking_rounded),
            errorText: _submitted && _capacityError.isNotEmpty
                ? _capacityError
                : null,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.surfaceRaised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (widget.trace.developerMode)
                    IconButton(
                      tooltip: '상태 확인',
                      onPressed: _showDeveloperTrace,
                      icon: const Icon(Icons.bug_report_rounded),
                    ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: _cancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.02, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey<LocationPlainSettingsSection>(widget.section),
                  child: _buildEditor(context),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: CommonButton(
                      label: '취소',
                      onPressed: _cancel,
                      variant: CommonButtonVariant.secondary,
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CommonButton(
                      label: '적용',
                      icon: Icons.check_rounded,
                      onPressed: _apply,
                      haptic: CommonHaptic.medium,
                      expand: true,
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
