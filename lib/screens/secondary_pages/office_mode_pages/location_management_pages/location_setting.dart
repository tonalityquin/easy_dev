import 'package:flutter/material.dart';

class LocationSetting extends StatefulWidget {
  final Function(String location) onSave;

  const LocationSetting({super.key, required this.onSave});

  @override
  State<LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends State<LocationSetting> {
  final TextEditingController _locationController = TextEditingController();
  final FocusNode _locationFocus = FocusNode();
  String? _errorMessage;

  // 주차 구역 유형 상태 (true: 단일, false: 복합)
  bool _isSingle = true;

  @override
  void dispose() {
    _locationController.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  bool _validateInput() {
    final isValid = _locationController.text.isNotEmpty;
    setState(() {
      _errorMessage = isValid ? null : 'Parking location is required.';
    });
    return isValid;
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
            // 단일/복합 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('단일 주차 구역'),
                  selected: _isSingle,
                  onSelected: (selected) {
                    setState(() {
                      _isSingle = true;
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('복합 주차 구역'),
                  selected: !_isSingle,
                  onSelected: (selected) {
                    setState(() {
                      _isSingle = false;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 위치 입력 필드
            TextField(
              controller: _locationController,
              focusNode: _locationFocus,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Parking Location',
                border: OutlineInputBorder(),
                hintText: 'Enter parking location name',
              ),
            ),
            const SizedBox(height: 16),

            // 에러 메시지
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),

            const Spacer(),

            // 버튼 영역
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
                      widget.onSave(_locationController.text);
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
