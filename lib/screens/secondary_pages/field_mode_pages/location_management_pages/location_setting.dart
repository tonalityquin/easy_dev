import 'package:flutter/material.dart';

class LocationSetting extends StatefulWidget {
  final Function(dynamic location) onSave;

  const LocationSetting({super.key, required this.onSave});

  @override
  State<LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends State<LocationSetting> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController(); // 단일용

  final FocusNode _locationFocus = FocusNode();

  final List<Map<String, TextEditingController>> _subControllers = []; // 이름+숫자

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
              (map) => map['name']!.text.trim().isNotEmpty);
      isValid = isValid && hasValidSub;
    }

    setState(() {
      _errorMessage = !isValid
          ? (_isSingle
          ? '주차 구역명과 유효한 수용 대수를 입력하세요. (1 이상의 숫자)'
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
    return Scaffold(
      appBar: AppBar(title: const Text('주차 구역 설정')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 유형 선택
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('단일 주차 구역'),
                  selected: _isSingle,
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
            const SizedBox(height: 16),

            // 상위 구역 이름
            TextField(
              controller: _locationController,
              focusNode: _locationFocus,
              decoration: InputDecoration(
                labelText: _isSingle ? '주차 구역명' : '상위 구역명',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            if (_isSingle)
              TextField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '수용 가능 차량 수',
                  border: OutlineInputBorder(),
                ),
              ),

            if (!_isSingle)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('하위 구역 목록',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...List.generate(_subControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _subControllers[index]['name'],
                              decoration: InputDecoration(
                                hintText: '하위 구역 ${index + 1}',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _subControllers[index]['capacity'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '수용',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeSubLocation(index),
                            icon: const Icon(Icons.delete,
                                color: Colors.red),
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
                    style:
                    const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                ],
              ),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            const Spacer(),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red),
                  child: const Text('취소'),
                ),
                ElevatedButton(
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
                          'parent':
                          _locationController.text.trim(),
                          'subs': subs,
                          'totalCapacity':
                          _calculateTotalSubCapacity(),
                        });
                      }
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green),
                  child: const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
