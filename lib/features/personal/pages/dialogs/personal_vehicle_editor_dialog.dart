import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../domain/models/personal_saved_vehicle.dart';
import '../widgets/personal_common_components.dart';

Future<PersonalVehicleEditorResult?> showPersonalVehicleEditorDialog({
  required BuildContext context,
  PersonalSavedVehicle? vehicle,
}) {
  return showCommonOverlayDialog<PersonalVehicleEditorResult>(
    context: context,
    builder: (_) => PersonalVehicleEditorDialog(vehicle: vehicle),
  );
}

class PersonalVehicleEditorResult {
  const PersonalVehicleEditorResult.save(this.vehicle) : deleteId = null;
  const PersonalVehicleEditorResult.delete(this.deleteId) : vehicle = null;

  final PersonalSavedVehicle? vehicle;
  final String? deleteId;

  bool get shouldDelete => deleteId != null;
}

class PersonalVehicleEditorDialog extends StatefulWidget {
  const PersonalVehicleEditorDialog({super.key, this.vehicle});

  final PersonalSavedVehicle? vehicle;

  @override
  State<PersonalVehicleEditorDialog> createState() =>
      _PersonalVehicleEditorDialogState();
}

class _PersonalVehicleEditorDialogState
    extends State<PersonalVehicleEditorDialog> {
  late final TextEditingController _plateController;
  late final TextEditingController _labelController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plateController = TextEditingController(
      text: widget.vehicle?.displayPlate ?? '',
    );
    _labelController = TextEditingController(text: widget.vehicle?.label ?? '');
  }

  @override
  void dispose() {
    _plateController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _save() {
    final compact = normalizePersonalPlateNumber(_plateController.text);
    if (!_validPlate(compact)) {
      HapticFeedback.mediumImpact();
      setState(() => _error = '번호판 전체를 입력하세요. 예: 12가3456');
      return;
    }
    final now = DateTime.now();
    final base = widget.vehicle;
    final vehicle = PersonalSavedVehicle(
      id: personalVehicleIdFromPlate(compact),
      plateNumber: compact,
      label: _labelController.text.trim().isEmpty
          ? '내 차량'
          : _labelController.text.trim(),
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
      lastUsedAt: base?.lastUsedAt,
    );
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(PersonalVehicleEditorResult.save(vehicle));
  }

  bool _validPlate(String value) {
    return RegExp(r'^\d{2,3}[가-힣]\d{4}$').hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final editing = widget.vehicle != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
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
                          CommonUiShapes.control,
                        ),
                        border: Border.all(
                          color: tokens.accent.withOpacity(.24),
                        ),
                      ),
                      child: Icon(
                        Icons.directions_car_filled_rounded,
                        color: tokens.onAccentContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        editing ? '차량 수정' : '차량 추가',
                        style: textTheme.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    CommonIconButton(
                      icon: Icons.close_rounded,
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).pop(),
                      haptic: CommonHaptic.selection,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PersonalCommonPanel(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '내 차량을 저장하면 검색 없이 도면에서 위치를 확인하고 출차 요청을 시작할 수 있습니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CommonAnimatedReveal(
                  child: TextField(
                    controller: _plateController,
                    autofocus: !editing,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    decoration: InputDecoration(
                      labelText: '번호판 전체',
                      prefixIcon: const Icon(Icons.pin_rounded),
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                CommonAnimatedReveal(
                  delay: const Duration(milliseconds: 40),
                  child: TextField(
                    controller: _labelController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '차량 별칭',
                      prefixIcon: Icon(Icons.sell_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (editing)
                      CommonButton(
                        label: '삭제',
                        icon: Icons.delete_outline_rounded,
                        variant: CommonButtonVariant.destructive,
                        haptic: CommonHaptic.heavy,
                        onPressed: () => Navigator.of(context).pop(
                          PersonalVehicleEditorResult.delete(
                            widget.vehicle!.id,
                          ),
                        ),
                      ),
                    CommonButton(
                      label: '취소',
                      variant: CommonButtonVariant.tertiary,
                      haptic: CommonHaptic.selection,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    CommonButton(
                      label: '저장',
                      icon: Icons.check_rounded,
                      haptic: CommonHaptic.light,
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
