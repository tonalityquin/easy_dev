import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationSettingBottomSheet extends StatefulWidget {
  final Function(dynamic location) onSave;

  const LocationSettingBottomSheet({super.key, required this.onSave});

  @override
  State<LocationSettingBottomSheet> createState() => _LocationSettingBottomSheetState();
}

class _LocationSettingBottomSheetState extends State<LocationSettingBottomSheet> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final List<Map<String, TextEditingController>> _subControllers = [];
  String? _errorMessage;
  bool _isSingle = true;

  @override
  void dispose() {
    _locationController.dispose();
    _capacityController.dispose();
    for (var pair in _subControllers) {
      pair['name']?.dispose();
      pair['capacity']?.dispose();
    }
    super.dispose();
  }

  bool _validateInput() {
    bool isValid = _locationController.text.trim().isNotEmpty;

    if (_isSingle) {
      final capacityText = _capacityController.text.trim();
      final parsed = int.tryParse(capacityText);
      isValid = isValid && capacityText.isNotEmpty && parsed != null && parsed > 0;
    } else {
      bool hasValidSub = _subControllers.any(
            (map) => map['name']!.text.trim().isNotEmpty,
      );
      isValid = isValid && hasValidSub;
    }

    setState(() {
      _errorMessage = !isValid
          ? (_isSingle ? '주차 구역명과 1 이상의 유효한 수용 대수를 입력하세요.' : '상위 구역명과 하나 이상의 하위 구역이 필요합니다.')
          : null;
    });

    return isValid;
  }

  void _addSubLocation() {
    setState(() {
      _subControllers.add({
        'name': TextEditingController(),
        'capacity': TextEditingController(),
      });
    });
  }

  void _removeSubLocation(int index) {
    setState(() {
      _subControllers[index]['name']?.dispose();
      _subControllers[index]['capacity']?.dispose();
      _subControllers.removeAt(index);
    });
  }

  int _calculateTotalSubCapacity() {
    return _subControllers.fold(0, (total, map) {
      final cap = int.tryParse(map['capacity']!.text.trim()) ?? 0;
      return total + cap;
    });
  }

  void _handleSave() {
    FocusScope.of(context).unfocus();
    if (!_validateInput()) return;

    if (_isSingle) {
      widget.onSave({
        'type': 'single',
        'name': _locationController.text.trim(),
        'capacity': int.parse(_capacityController.text.trim()),
      });
    } else {
      final subs = _subControllers
          .where((map) => map['name']!.text.trim().isNotEmpty)
          .map((map) {
        final cap = int.tryParse(map['capacity']!.text.trim()) ?? 0;
        return {
          'name': map['name']!.text.trim(),
          'capacity': cap,
        };
      }).toList();

      widget.onSave({
        'type': 'composite',
        'parent': _locationController.text.trim(),
        'subs': subs,
        'totalCapacity': _calculateTotalSubCapacity(),
      });
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                '주차 구역 설정',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 유형 선택
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('단일'),
                    selected: _isSingle,
                    selectedColor: Colors.green,
                    backgroundColor: Colors.purple.withOpacity(0.2),
                    labelStyle: TextStyle(color: _isSingle ? Colors.white : Colors.black),
                    onSelected: (selected) {
                      if (selected) setState(() => _isSingle = true);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('복합'),
                    selected: !_isSingle,
                    selectedColor: Colors.green,
                    backgroundColor: Colors.purple.withOpacity(0.2),
                    labelStyle: TextStyle(color: !_isSingle ? Colors.white : Colors.black),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _isSingle = false;
                          if (_subControllers.isEmpty) _addSubLocation();
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 이름 필드
              TextField(
                controller: _locationController,
                decoration: _inputDecoration(_isSingle ? '구역명' : '상위 구역명'),
              ),
              const SizedBox(height: 16),

              if (_isSingle)
                TextField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration('수용 가능 차량 수'),
                ),

              if (!_isSingle)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('하위 구역', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._subControllers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final map = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: map['name'],
                                decoration: _inputDecoration('하위 ${index + 1}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: map['capacity'],
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: _inputDecoration('수용'),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeSubLocation(index),
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _addSubLocation,
                        icon: const Icon(Icons.add),
                        label: const Text('하위 구역 추가'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('총 수용 차량: ${_calculateTotalSubCapacity()}대'),
                  ],
                ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('저장'),
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

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.green),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
