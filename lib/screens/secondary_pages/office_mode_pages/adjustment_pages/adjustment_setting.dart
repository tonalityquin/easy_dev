import 'package:flutter/material.dart';

/// 조정 사항 추가 및 설정 화면
class AdjustmentSetting extends StatefulWidget {
  /// 사용자가 입력한 조정 사항 데이터를 저장하는 콜백
  final Function(String adjustment) onSave;

  const AdjustmentSetting({Key? key, required this.onSave}) : super(key: key);

  @override
  State<AdjustmentSetting> createState() => _AdjustmentSettingState();
}

class _AdjustmentSettingState extends State<AdjustmentSetting> {
  final TextEditingController _adjustmentController = TextEditingController(); // 입력 필드 컨트롤러
  final FocusNode _adjustmentFocus = FocusNode(); // 입력 필드 포커스
  String? _errorMessage; // 에러 메시지 상태

  @override
  void dispose() {
    _adjustmentController.dispose();
    _adjustmentFocus.dispose();
    super.dispose();
  }

  /// 입력값 유효성 검증
  bool _validateInput() {
    if (_adjustmentController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Adjustment is required.'; // 에러 메시지 설정
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
        title: const Text('Add Adjustment'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _adjustmentController,
              focusNode: _adjustmentFocus,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Adjustment',
                border: OutlineInputBorder(),
                hintText: 'Enter adjustment details',
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
                      widget.onSave(_adjustmentController.text); // 유효한 입력값 저장
                      Navigator.pop(context); // 저장 후 화면 닫기
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
