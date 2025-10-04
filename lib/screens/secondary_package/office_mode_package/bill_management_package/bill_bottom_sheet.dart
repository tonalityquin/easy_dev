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

  String? _errorMessage;

  static const List<String> _basicStandardOptions = ['1분', '5분', '30분', '60분', '120분', '240분'];
  static const List<String> _addStandardOptions = ['1분', '10분', '30분', '60분'];

  @override
  void dispose() {
    _billController.dispose();
    _basicAmountController.dispose();
    _addAmountController.dispose();
    super.dispose();
  }

  int? _digitsToInt(String s) {
    final onlyDigits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) return null;
    return int.tryParse(onlyDigits);
  }

  bool _validateInput() {
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

    setState(() => _errorMessage = null);
    return true;
  }

  void _handleSave() {
    if (!_validateInput()) return;

    final currentArea = context.read<AreaState>().currentArea;

    final billData = {
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

                // ===== 본문 스크롤 영역 =====
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      children: [
                        // 변동 정산 입력 섹션
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
