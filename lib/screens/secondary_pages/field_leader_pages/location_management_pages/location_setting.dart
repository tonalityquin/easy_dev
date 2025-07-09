import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationSetting extends StatefulWidget {
  final Function(dynamic location) onSave;

  const LocationSetting({super.key, required this.onSave});

  @override
  State<LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends State<LocationSetting> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();

  final FocusNode _locationFocus = FocusNode();

  final List<Map<String, TextEditingController>> _subControllers = [];

  String? _errorMessage;
  bool _isSingle = true;

  @override
  void dispose() {
    _locationController.dispose();
    _capacityController.dispose();
    _locationFocus.dispose();
    for (var pair in _subControllers) {
      pair['name']!.dispose();
      pair['capacity']!.dispose();
    }
    super.dispose();
  }

  bool _validateInput() {
    bool isValid = _locationController.text.trim().isNotEmpty;

    if (_isSingle) {
      final capacityText = _capacityController.text.trim();
      final parsed = int.tryParse(capacityText);
      isValid = isValid &&
          capacityText.isNotEmpty &&
          parsed != null &&
          parsed > 0;
    } else {
      bool hasValidSub = _subControllers.any(
            (map) => map['name']!.text.trim().isNotEmpty,
      );
      isValid = isValid && hasValidSub;
    }

    setState(() {
      _errorMessage = !isValid
          ? (_isSingle
          ? '주차 구역명과 1 이상의 유효한 수용 대수를 입력하세요.'
          : '상위 구역명과 하나 이상의 하위 구역이 필요합니다.')
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
      _subControllers[index]['name']!.dispose();
      _subControllers[index]['capacity']!.dispose();
      _subControllers.removeAt(index);
    });
  }

  int _calculateTotalSubCapacity() {
    return _subControllers.fold(0, (total, map) {
      final cap = int.tryParse(map['capacity']!.text.trim()) ?? 0;
      return total + cap;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '주차 구역 설정',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 3,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 유형 선택
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('단일 주차 구역'),
                      selected: _isSingle,
                      selectedColor: Colors.green,
                      backgroundColor: Colors.purple.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: _isSingle ? Colors.white : Colors.black,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _isSingle = true;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('복합 주차 구역'),
                      selected: !_isSingle,
                      selectedColor: Colors.green,
                      backgroundColor: Colors.purple.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: !_isSingle ? Colors.white : Colors.black,
                      ),
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

                // 이름 입력
                TextField(
                  controller: _locationController,
                  focusNode: _locationFocus,
                  decoration: InputDecoration(
                    labelText: _isSingle ? '주차 구역명' : '상위 구역명',
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isSingle)
                  TextField(
                    controller: _capacityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '수용 가능 차량 수',
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),

                if (!_isSingle)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Text(
                        '하위 구역 목록',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(_subControllers.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _subControllers[index]['name'],
                                  decoration: InputDecoration(
                                    hintText: '하위 구역 ${index + 1}',
                                    focusedBorder: OutlineInputBorder(
                                      borderSide:
                                      const BorderSide(color: Colors.green),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _subControllers[index]['capacity'],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: InputDecoration(
                                    hintText: '수용',
                                    focusedBorder: OutlineInputBorder(
                                      borderSide:
                                      const BorderSide(color: Colors.green),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
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
                      Text(
                        '총 수용 가능 차량 수: ${_calculateTotalSubCapacity()}대',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                    ),
                  ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.withOpacity(0.2),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          if (_validateInput()) {
                            if (_isSingle) {
                              final parsedCapacity = int.parse(
                                  _capacityController.text.trim());
                              widget.onSave({
                                'type': 'single',
                                'name': _locationController.text.trim(),
                                'capacity': parsedCapacity,
                              });
                            } else {
                              final subs = _subControllers
                                  .where((map) =>
                              map['name']!.text.trim().isNotEmpty)
                                  .map((map) {
                                final cap = int.tryParse(
                                    map['capacity']!.text.trim()) ??
                                    0;
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
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
