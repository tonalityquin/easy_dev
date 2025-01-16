import 'package:flutter/material.dart';

class LocationSetting extends StatefulWidget {
  /// **저장 콜백 함수**
  /// - 사용자가 입력한 주차 구역 데이터를 저장하는 역할
  final Function(String location) onSave;

  const LocationSetting({Key? key, required this.onSave}) : super(key: key);

  @override
  State<LocationSetting> createState() => _LocationSettingState();
}

class _LocationSettingState extends State<LocationSetting> {
  final TextEditingController _locationController = TextEditingController(); // 주차 구역 입력 컨트롤러
  final FocusNode _locationFocus = FocusNode(); // 주차 구역 입력 포커스
  String? _errorMessage; // 에러 메시지 상태

  @override
  void dispose() {
    _locationController.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  /// **입력값 유효성 검증**
  /// - 주차 구역 입력값이 비어 있으면 에러 메시지 표시
  bool _validateInput() {
    if (_locationController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Parking location is required.';
      });
      return false;
    }
    setState(() {
      _errorMessage = null; // 에러 메시지 초기화
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Parking Location'), // 페이지 제목
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
              keyboardType: TextInputType.text, // 텍스트 입력용 키보드
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
                      widget.onSave(_locationController.text); // 입력값 저장
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
