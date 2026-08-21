import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'widgets/location_draft.dart';

class LocationSettingBottomSheet extends StatefulWidget {
  const LocationSettingBottomSheet({
    super.key,
    required this.existingNameKeysInArea,
    required this.editingPlainTextId,
    required this.editingPlainTextName,
    required this.editingPlainTextCapacity,
    required this.onSave,
  });

  final Set<String> existingNameKeysInArea;
  final String editingPlainTextId;
  final String editingPlainTextName;
  final int editingPlainTextCapacity;
  final Future<bool> Function(LocationDraft draft) onSave;

  @override
  State<LocationSettingBottomSheet> createState() =>
      _LocationSettingBottomSheetState();
}

class _LocationSettingBottomSheetState extends State<LocationSettingBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late final String _originalNameKey;
  DeveloperOperationTrace? _trace;
  String? _error;
  bool _saving = false;
  bool _reduceMotion = false;

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.editingPlainTextName.trim());
    _capacityController = TextEditingController(
      text: widget.editingPlainTextCapacity.toString(),
    );
    _originalNameKey = _nameKey(widget.editingPlainTextName);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '텍스트 구역 수정',
        initialMessage: '텍스트 구역 수정 화면을 열었습니다.',
        useCommonUi: true,
        showDialogImmediately: false,
      );
      if (!mounted) return;
      setState(() => _trace = trace);
    });
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
    _trace?.dispose();
    super.dispose();
  }

  String? _validate() {
    final name = _normalizeName(_nameController.text);
    final nameKey = _nameKey(name);
    final capacityText = _capacityController.text.trim();
    final capacity = int.tryParse(capacityText);
    if (name.isEmpty) return '구역명을 입력해 주세요.';
    if (name.length > 40) return '구역명은 40자 이하로 입력해 주세요.';
    if (nameKey != _originalNameKey &&
        widget.existingNameKeysInArea.contains(nameKey)) {
      return '이미 사용 중인 주차 구역명입니다.';
    }
    if (capacity == null || capacity < 0) {
      return '수용 가능 차량 수는 0 이상이어야 합니다.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      _trace?.log('validation_failed message=$validation');
      return;
    }
    final name = _normalizeName(_nameController.text);
    final capacity = int.parse(_capacityController.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    _trace?.log('save_started name=$name capacity=$capacity', progress: .25);
    final ok = await widget.onSave(
      PlainTextLocationUpdateDraft(
        id: widget.editingPlainTextId,
        name: name,
        capacity: capacity,
      ),
    );
    if (!mounted) return;
    if (ok) {
      _trace?.succeed('텍스트 구역 수정이 완료되었습니다.');
      Navigator.of(context).pop();
      return;
    }
    _trace?.fail('텍스트 구역 수정에 실패했습니다. 입력 내용은 유지됩니다.');
    setState(() {
      _saving = false;
      _error = '저장에 실패했습니다. 입력 내용을 확인한 뒤 다시 시도해 주세요.';
    });
  }

  Future<void> _showDeveloperStatus() async {
    final trace = _trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    trace.log(
      'developer_status_requested name=${_normalizeName(_nameController.text)} capacity=${_capacityController.text.trim()} saving=$_saving',
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: '텍스트 구역 수정 상태',
      description: '현재 입력과 저장 상태의 debugPrint 기록입니다.',
      failure: _error != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final trace = _trace;
    return SafeArea(
      child: AnimatedContainer(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 14,
          bottom: 14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '텍스트 구역 수정',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (trace?.developerMode ?? false)
                  IconButton(
                    tooltip: '상태 확인',
                    onPressed: _showDeveloperStatus,
                    icon: const Icon(Icons.bug_report_rounded),
                  ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: (value) {
                if (_error != null) setState(() => _error = null);
                _trace?.log('name_changed length=${value.trim().length}');
              },
              decoration: opsInputDecoration(
                context,
                label: '구역명',
                prefixIcon: const Icon(Icons.text_fields_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textInputAction: TextInputAction.done,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onSubmitted: (_) => _save(),
              onChanged: (value) {
                if (_error != null) setState(() => _error = null);
                _trace?.log('capacity_changed value=${value.trim()}');
              },
              decoration: opsInputDecoration(
                context,
                label: '수용 가능 차량 수',
                prefixIcon: const Icon(Icons.local_parking_rounded),
              ),
            ),
            AnimatedSize(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              child: _error == null
                  ? const SizedBox(height: 16)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.danger,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '취소',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    variant: CommonButtonVariant.secondary,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CommonButton(
                    label: '수정 완료',
                    onPressed: _saving ? null : _save,
                    loading: _saving,
                    icon: Icons.check_rounded,
                    haptic: CommonHaptic.medium,
                    expand: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
