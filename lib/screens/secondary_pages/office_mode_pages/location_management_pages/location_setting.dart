import 'package:flutter/material.dart';

/// 주차 구역 추가 및 설정 화면
class LocationSetting extends StatefulWidget {
  /// 사용자가 입력한 주차 구역 데이터를 저장하는 콜백
  final Function(String location) onSave;

  const LocationSetting({Key? key, required this.onSave}) : super(key: key);

  @override
  State<LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends State<LocationSetting> {
  final TextEditingController _locationController = TextEditingController(); // 입력 필드 컨트롤러
  final FocusNode _locationFocus = FocusNode(); // 입력 필드 포커스
  String? _errorMessage; // 에러 메시지 상태

  @override
  void dispose() {
    _locationController.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  /// 입력값 유효성 검증
  bool _validateInput() {
    if (_locationController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Parking location is required.';
      });
      return false;
    }
    setState(() {
      _errorMessage = null;
    });
    return true;
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
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context), // 취소 버튼
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_validateInput()) {
                      widget.onSave(_locationController.text); // 유효한 입력값 저장
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
