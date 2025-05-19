import 'package:flutter/material.dart';

class LocationSetting extends StatefulWidget {
  final Function(dynamic location) onSave;

  const LocationSetting({super.key, required this.onSave});

  @override
  State<LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends State<LocationSetting> {
  final TextEditingController _locationController = TextEditingController(); // 단일 또는 상위
  final FocusNode _locationFocus = FocusNode();

  List<TextEditingController> _subControllers = []; // 하위 구역 리스트

  String? _errorMessage;
  bool _isSingle = true; // 기본값: 단일 주차 구역

  @override
  void dispose() {
    _locationController.dispose();
    _locationFocus.dispose();
    for (var controller in _subControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _validateInput() {
    bool isValid = _locationController.text.isNotEmpty;

    if (!_isSingle) {
      bool hasValidSub = _subControllers.any((c) => c.text.trim().isNotEmpty);
      isValid = isValid && hasValidSub;
    }

    setState(() {
      if (!isValid) {
        _errorMessage = _isSingle
            ? 'Parking location is required.'
            : 'Both parent and at least one sub-location are required.';
      } else {
        _errorMessage = null;
      }
    });

    return isValid;
  }

  void _addSubLocation() {
    setState(() {
      _subControllers.add(TextEditingController());
    });
  }

  void _removeSubLocation(int index) {
    setState(() {
      _subControllers[index].dispose();
      _subControllers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Parking Location'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 토글 선택
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

            // 입력 필드
            TextField(
              controller: _locationController,
              focusNode: _locationFocus,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: _isSingle ? 'Parking Location' : 'Parent Parking Area',
                border: const OutlineInputBorder(),
                hintText: _isSingle
                    ? 'Enter parking location name'
                    : 'Enter parent area name',
              ),
            ),
            const SizedBox(height: 16),

            // 복합 주차 구역: 하위 입력 리스트
            if (!_isSingle)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sub Parking Areas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_subControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _subControllers[index],
                              decoration: InputDecoration(
                                hintText: 'Sub-location ${index + 1}',
                                border: const OutlineInputBorder(),
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
                      label: const Text('Add Sub-location'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            // 에러 메시지
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),

            const Spacer(),

            // 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_validateInput()) {
                      if (_isSingle) {
                        widget.onSave(_locationController.text);
                      } else {
                        final parent = _locationController.text.trim();
                        final subs = _subControllers
                            .map((c) => c.text.trim())
                            .where((text) => text.isNotEmpty)
                            .toList();
                        widget.onSave({'parent': parent, 'subs': subs});
                      }
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
