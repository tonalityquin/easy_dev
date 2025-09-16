import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 숫자만 입력
import 'package:provider/provider.dart';

import '../../../../states/area/area_state.dart';
import 'sections/bill_type_input_section.dart';
import 'sections/bill_standard_and_amount_row_section.dart';
import 'sections/bill_error_message_text_section.dart';
import 'sections/bill_bottom_buttons_section.dart';

class BillSettingBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic> billData) onSave;

  const BillSettingBottomSheet({super.key, required this.onSave});

  @override
  State<BillSettingBottomSheet> createState() => _BillSettingBottomSheetState();
}

class _BillSettingBottomSheetState extends State<BillSettingBottomSheet> {
  // 일반(변동) 정산
  final TextEditingController _billController = TextEditingController();
  final TextEditingController _basicAmountController = TextEditingController();
  final TextEditingController _addAmountController = TextEditingController();
  String? _basicStandardValue;
  String? _addStandardValue;

  // 고정 정산
  final TextEditingController _regularNameController = TextEditingController();
  final TextEditingController _regularPriceController = TextEditingController();
  final TextEditingController _regularDurationController = TextEditingController();
  String? _regularType;

  String? _errorMessage;
  String _selectedMode = '변동';

  static const List<String> _basicStandardOptions = ['1분', '5분', '30분', '60분'];
  static const List<String> _addStandardOptions = ['1분', '10분', '30분', '60분'];
  static const List<String> _regularTypeOptions = ['일 주차', '월 주차'];

  @override
  void dispose() {
    _billController.dispose();
    _basicAmountController.dispose();
    _addAmountController.dispose();
    _regularNameController.dispose();
    _regularPriceController.dispose();
    _regularDurationController.dispose();
    super.dispose();
  }

  int? _digitsToInt(String s) {
    final onlyDigits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) return null;
    return int.tryParse(onlyDigits);
  }

  bool _validateInput() {
    if (_selectedMode == '변동') {
      final countTypeOk = _billController.text.trim().isNotEmpty;
      final basicStdOk = _basicStandardValue != null;
      final addStdOk = _addStandardValue != null;

      final basicAmount = _digitsToInt(_basicAmountController.text);
      final addAmount   = _digitsToInt(_addAmountController.text);

      // ⬇️ 0 허용: <= 0  →  < 0
      if (!countTypeOk ||
          !basicStdOk ||
          !addStdOk ||
          basicAmount == null || basicAmount < 0 ||
          addAmount   == null || addAmount   < 0) {
        setState(() => _errorMessage = '모든 항목을 올바르게 입력하세요. 금액은 0 이상만 가능합니다.');
        return false;
      }
    } else {
      final nameOk = _regularNameController.text.trim().isNotEmpty;
      final typeOk = _regularType != null;
      final price  = _digitsToInt(_regularPriceController.text);
      final dur    = _digitsToInt(_regularDurationController.text);

      // ⬇️ 고정 요금도 0 허용하려면 price <= 0 → price < 0 로 변경
      //    (이용 시간은 0 불가 유지: dur <= 0 그대로)
      if (!nameOk || !typeOk || price == null || price < 0 || dur == null || dur <= 0) {
        setState(() => _errorMessage = '고정 정산 정보를 확인하세요. 금액은 0 이상, 시간은 1 이상이어야 합니다.');
        return false;
      }
    }

    setState(() => _errorMessage = null);
    return true;
  }


  void _handleSave() {
    if (!_validateInput()) return;

    final currentArea = context.read<AreaState>().currentArea;

    Map<String, dynamic> billData;

    if (_selectedMode == '변동') {
      billData = {
        'type': '변동',
        // ✅ 대문자 키 유지
        'CountType': _billController.text.trim(),
        'basicStandard': int.tryParse(_basicStandardValue!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        'basicAmount': int.tryParse(_basicAmountController.text) ?? 0,
        'addStandard': int.tryParse(_addStandardValue!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        'addAmount': int.tryParse(_addAmountController.text) ?? 0,
        'area': currentArea,
        'isSelected': false,
      };
    } else {
      billData = {
        'type': '고정',
        // ✅ 대문자 키 유지
        'CountType': _regularNameController.text.trim(),
        'regularType': _regularType,
        'regularAmount': int.tryParse(_regularPriceController.text) ?? 0,
        'regularDurationHours': int.tryParse(_regularDurationController.text) ?? 0,
        'area': currentArea,
        'isSelected': false,
      };
    }

    debugPrint('📦 저장할 데이터: $billData');
    widget.onSave(billData);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 최상단까지 차오르도록 높이 고정 + 키보드 여백 반영
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset), // 키보드 여백
        child: SizedBox(
          height: effectiveHeight, // 화면 높이(키보드 제외)만큼 고정
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // ===== 상단 헤더 영역 =====
                const SizedBox(height: 16),
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
                  '정산 유형 추가',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ToggleButtons(
                  isSelected: [_selectedMode == '변동', _selectedMode == '고정'],
                  onPressed: (index) {
                    setState(() {
                      _selectedMode = index == 0 ? '변동' : '고정';
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('변동'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('고정'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ===== 본문 스크롤 영역 =====
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      children: [
                        if (_selectedMode == '변동') ...[
                          BillTypeInputSection(controller: _billController),
                          const SizedBox(height: 16),
                          BillStandardAndAmountRowSection(
                            selectedValue: _basicStandardValue,
                            options: _basicStandardOptions,
                            onChanged: (val) => setState(() => _basicStandardValue = val),
                            amountController: _basicAmountController,
                            standardLabel: '기본 시간',
                            amountLabel: '기본 요금',
                            amountInputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                          const SizedBox(height: 16),
                          BillStandardAndAmountRowSection(
                            selectedValue: _addStandardValue,
                            options: _addStandardOptions,
                            onChanged: (val) => setState(() => _addStandardValue = val),
                            amountController: _addAmountController,
                            standardLabel: '추가 시간',
                            amountLabel: '추가 요금',
                            amountInputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ],
                        if (_selectedMode == '고정') ...[
                          TextField(
                            controller: _regularNameController,
                            decoration: const InputDecoration(
                              labelText: '고정 유형',
                              hintText: '예: 일일 주차',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _regularType,
                            decoration: const InputDecoration(
                              labelText: '일&월 주차 선택',
                              border: OutlineInputBorder(),
                            ),
                            items: _regularTypeOptions
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (val) => setState(() => _regularType = val),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _regularDurationController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: '주차 가능 시간',
                              hintText: '예: 720',
                              suffixText: '시간',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _regularPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: '일일 요금',
                              hintText: '예: 10000',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        BillErrorMessageTextSection(message: _errorMessage),
                      ],
                    ),
                  ),
                ),

                // ===== 하단 버튼 고정 영역 =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: BillBottomButtonsSection(
                    onCancel: () => Navigator.pop(context),
                    onSave: _handleSave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
