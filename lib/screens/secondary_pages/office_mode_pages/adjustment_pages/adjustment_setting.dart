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
  final TextEditingController _basicAmountController = TextEditingController(); // 기본 금액 컨트롤러
  final TextEditingController _addAmountController = TextEditingController(); // 추가 금액 컨트롤러

  final FocusNode _adjustmentFocus = FocusNode(); // 입력 필드 포커스
  final FocusNode _basicAmountFocus = FocusNode(); // 기본 금액 포커스
  final FocusNode _addAmountFocus = FocusNode(); // 추가 금액 포커스

  String? _errorMessage; // 에러 메시지 상태

  // 기본 및 추가 드롭다운 메뉴의 초기 값
  String? _basicStandardValue;
  String? _addStandardValue;

  // 드롭다운 옵션 목록
  final List<String> _basicStandardOptions = ['30분', '60분'];
  final List<String> _addStandardOptions = ['10분', '30분', '60분'];

  @override
  void dispose() {
    _adjustmentController.dispose();
    _basicAmountController.dispose();
    _addAmountController.dispose();
    _adjustmentFocus.dispose();
    _basicAmountFocus.dispose();
    _addAmountFocus.dispose();
    super.dispose();
  }

  /// 입력값 유효성 검증
  bool _validateInput() {
    if (_adjustmentController.text.isEmpty ||
        _basicStandardValue == null ||
        _addStandardValue == null ||
        _basicAmountController.text.isEmpty ||
        _addAmountController.text.isEmpty) {
      setState(() {
        _errorMessage = 'All fields are required.';
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
            // Count Type 입력 필드
            TextField(
              controller: _adjustmentController,
              focusNode: _adjustmentFocus,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Count Type',
                border: OutlineInputBorder(),
                hintText: 'Enter Count type details',
              ),
            ),
            const SizedBox(height: 16),

            // 기본 선택 옵션 (드롭다운)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _basicStandardValue,
                    onChanged: (newValue) {
                      setState(() {
                        _basicStandardValue = newValue;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Basic Standard',
                      border: OutlineInputBorder(),
                    ),
                    items: _basicStandardOptions.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 16),

                // 기본 금액 입력 필드 (숫자만 입력 가능)
                Expanded(
                  child: TextField(
                    controller: _basicAmountController,
                    focusNode: _basicAmountFocus,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Basic Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 추가 선택 옵션 (드롭다운)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _addStandardValue,
                    onChanged: (newValue) {
                      setState(() {
                        _addStandardValue = newValue;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Add Standard',
                      border: OutlineInputBorder(),
                    ),
                    items: _addStandardOptions.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 16),

                // 추가 금액 입력 필드 (숫자만 입력 가능)
                Expanded(
                  child: TextField(
                    controller: _addAmountController,
                    focusNode: _addAmountFocus,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Add Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 에러 메시지 표시
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const Spacer(),

            // 취소 및 저장 버튼
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
