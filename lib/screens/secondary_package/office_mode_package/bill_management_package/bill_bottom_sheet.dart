import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 숫자만 입력
import 'package:provider/provider.dart';

import '../../../../states/area/area_state.dart';
import 'sections/bill_type_input_section.dart';
import 'sections/bill_standard_and_amount_row_section.dart';
import 'sections/bill_error_message_text_section.dart';
import 'sections/bill_bottom_buttons_section.dart';

/// 서비스 카드 팔레트(일관 색상 적용)
const serviceCardBase = Color(0xFF0D47A1);
const serviceCardDark = Color(0xFF09367D);
const serviceCardLight = Color(0xFF5472D3);
const serviceCardFg = Colors.white; // 버튼/아이콘 전경
const serviceCardBg = Colors.white; // 카드/시트 배경

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
      final addAmount = _digitsToInt(_addAmountController.text);

      // 0 허용(음수만 금지)
      if (!countTypeOk ||
          !basicStdOk ||
          !addStdOk ||
          basicAmount == null ||
          basicAmount < 0 ||
          addAmount == null ||
          addAmount < 0) {
        setState(() => _errorMessage = '모든 항목을 올바르게 입력하세요. 금액은 0 이상만 가능합니다.');
        return false;
      }
    } else {
      final nameOk = _regularNameController.text.trim().isNotEmpty;
      final typeOk = _regularType != null;
      final price = _digitsToInt(_regularPriceController.text);
      final dur = _digitsToInt(_regularDurationController.text);

      // 금액 0 허용, 시간은 1 이상
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

  // 공통 InputDecoration(서비스 팔레트 적용)
  InputDecoration _decoration(String label, {String? hint, String? suffixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: serviceCardBase, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
    );
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
              color: serviceCardBg,
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

                // 토글 버튼(서비스 팔레트 적용)
                ToggleButtons(
                  isSelected: [_selectedMode == '변동', _selectedMode == '고정'],
                  onPressed: (index) {
                    setState(() {
                      _selectedMode = index == 0 ? '변동' : '고정';
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black87,
                  // 일반 텍스트
                  selectedColor: serviceCardFg,
                  // 선택 텍스트
                  fillColor: serviceCardBase,
                  // 선택 배경
                  borderColor: serviceCardLight,
                  // 테두리
                  selectedBorderColor: serviceCardBase,
                  // 선택 테두리
                  constraints: const BoxConstraints(minHeight: 40, minWidth: 72),
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
                          // CountType
                          BillTypeInputSection(controller: _billController),
                          const SizedBox(height: 16),

                          // 기본 기준/금액
                          BillStandardAndAmountRowSection(
                            selectedValue: _basicStandardValue,
                            options: _basicStandardOptions,
                            onChanged: (val) => setState(() => _basicStandardValue = val),
                            amountController: _basicAmountController,
                            standardLabel: '기본 시간',
                            amountLabel: '기본 요금',
                            amountInputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            // 내부 위젯의 InputDecoration이 있다면 동일 팔레트로 스타일링되어 있어야 함
                          ),
                          const SizedBox(height: 16),

                          // 추가 기준/금액
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
                            decoration: _decoration('고정 유형', hint: '예: 일일 주차'),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _regularType,
                            decoration: _decoration('일&월 주차 선택'),
                            items: _regularTypeOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            onChanged: (val) => setState(() => _regularType = val),
                            dropdownColor: serviceCardBg,
                            iconEnabledColor: serviceCardBase,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _regularDurationController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _decoration('주차 가능 시간', hint: '예: 720', suffixText: '시간'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _regularPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _decoration('일일 요금', hint: '예: 10000'),
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
                  child: Theme(
                    // 하단 공용 섹션 버튼들도 팔레트 느낌 살리기
                    data: Theme.of(context).copyWith(
                      elevatedButtonTheme: ElevatedButtonThemeData(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: serviceCardBase,
                          foregroundColor: serviceCardFg,
                          shape: const StadiumBorder(),
                        ),
                      ),
                      outlinedButtonTheme: OutlinedButtonThemeData(
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          side: const BorderSide(color: serviceCardLight),
                          foregroundColor: serviceCardDark,
                        ),
                      ),
                    ),
                    child: BillBottomButtonsSection(
                      onCancel: () => Navigator.pop(context),
                      onSave: _handleSave,
                    ),
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
