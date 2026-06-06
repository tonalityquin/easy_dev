import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/personal_saved_vehicle.dart';

Future<PersonalVehicleEditorResult?> showPersonalVehicleEditorDialog({
  required BuildContext context,
  PersonalSavedVehicle? vehicle,
}) {
  return showDialog<PersonalVehicleEditorResult>(
    context: context,
    barrierDismissible: true,
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
  State<PersonalVehicleEditorDialog> createState() => _PersonalVehicleEditorDialogState();
}

class _PersonalVehicleEditorDialogState extends State<PersonalVehicleEditorDialog> {
  late final TextEditingController _plateController;
  late final TextEditingController _labelController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plateController = TextEditingController(text: widget.vehicle?.displayPlate ?? '');
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
      setState(() => _error = '번호판 전체를 입력하세요. 예: 12가3456');
      return;
    }
    final now = DateTime.now();
    final base = widget.vehicle;
    final vehicle = PersonalSavedVehicle(
      id: personalVehicleIdFromPlate(compact),
      plateNumber: compact,
      label: _labelController.text.trim().isEmpty ? '내 차량' : _labelController.text.trim(),
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
      lastUsedAt: base?.lastUsedAt,
    );
    Navigator.of(context).pop(PersonalVehicleEditorResult.save(vehicle));
  }

  bool _validPlate(String value) {
    return RegExp(r'^\d{2,3}[가-힣]\d{4}$').hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final editing = widget.vehicle != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.directions_car_filled_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              editing ? '차량 수정' : '차량 추가',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '내 차량을 저장하면 검색 없이 도면에서 위치를 확인하고 출차 요청을 시작할 수 있습니다.',
                style: text.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _plateController,
                autofocus: !editing,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                decoration: InputDecoration(
                  labelText: '번호판 전체',
                  hintText: '12가3456',
                  helperText: '공백 없이 입력해도 자동으로 정리됩니다.',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '차량 별칭',
                  hintText: '내 차, 가족 차량 등',
                  prefixIcon: Icon(Icons.sell_outlined),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(PersonalVehicleEditorResult.delete(widget.vehicle!.id)),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('삭제'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
