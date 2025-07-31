import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../states/area/area_state.dart';
import 'sections/bill_type_input.dart';
import 'sections/standard_and_amount_row.dart';
import 'sections/error_message_text.dart';
import 'sections/bottom_buttons.dart';

class BillSettingBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic> billData) onSave;

  const BillSettingBottomSheet({super.key, required this.onSave});

  @override
  State<BillSettingBottomSheet> createState() => _BillSettingBottomSheetState();
}

class _BillSettingBottomSheetState extends State<BillSettingBottomSheet> {
  // 일반 정산
  final TextEditingController _billController = TextEditingController();
  final TextEditingController _basicAmountController = TextEditingController();
  final TextEditingController _addAmountController = TextEditingController();
  String? _basicStandardValue;
  String? _addStandardValue;

  // 정기 정산
  final TextEditingController _regularNameController = TextEditingController();
  final TextEditingController _regularPriceController = TextEditingController();
  final TextEditingController _regularDurationController = TextEditingController();
  String? _regularType;

  // 공통
  String? _errorMessage;
  String _selectedMode = '일반';

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

  bool _validateInput() {
    if (_selectedMode == '일반') {
      final fields = [
        _billController.text.trim(),
        _basicAmountController.text.trim(),
        _addAmountController.text.trim(),
      ];
      if (fields.any((e) => e.isEmpty) || _basicStandardValue == null || _addStandardValue == null) {
        setState(() {
          _errorMessage = '모든 항목을 입력해야 합니다.';
        });
        return false;
      }
    } else {
      if (_regularNameController.text.trim().isEmpty ||
          _regularType == null ||
          _regularPriceController.text.trim().isEmpty ||
          _regularDurationController.text.trim().isEmpty) {
        setState(() {
          _errorMessage = '정기 정산 정보를 모두 입력해주세요.';
        });
        return false;
      }
    }

    setState(() {
      _errorMessage = null;
    });
    return true;
  }

  void _handleSave() {
    if (!_validateInput()) return;

    final currentArea = context.read<AreaState>().currentArea;

    Map<String, dynamic> billData;

    if (_selectedMode == '일반') {
      billData = {
        'type': '일반',
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
        'type': '정기',
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
    final viewInsets = MediaQuery.of(context).viewInsets;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
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

                  /// 정산 모드 선택
                  ToggleButtons(
                    isSelected: [_selectedMode == '일반', _selectedMode == '정기'],
                    onPressed: (index) {
                      setState(() {
                        _selectedMode = index == 0 ? '일반' : '정기';
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('일반')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('정기')),
                    ],
                  ),

                  const SizedBox(height: 24),

                  /// 일반 정산
                  if (_selectedMode == '일반') ...[
                    BillTypeInput(controller: _billController),
                    const SizedBox(height: 16),
                    StandardAndAmountRow(
                      selectedValue: _basicStandardValue,
                      options: _basicStandardOptions,
                      onChanged: (val) => setState(() => _basicStandardValue = val),
                      amountController: _basicAmountController,
                      standardLabel: '기본 시간',
                      amountLabel: '기본 요금',
                    ),
                    const SizedBox(height: 16),
                    StandardAndAmountRow(
                      selectedValue: _addStandardValue,
                      options: _addStandardOptions,
                      onChanged: (val) => setState(() => _addStandardValue = val),
                      amountController: _addAmountController,
                      standardLabel: '추가 시간',
                      amountLabel: '추가 요금',
                    ),
                  ],

                  /// 정기 정산
                  if (_selectedMode == '정기') ...[
                    TextField(
                      controller: _regularNameController,
                      decoration: const InputDecoration(
                        labelText: '월 정산 유형',
                        hintText: '예: 월 정기권',
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
                      items: _regularTypeOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setState(() => _regularType = val),
                    ),
                    const SizedBox(height: 16),
                    // 💡 정기 사용 시간 먼저
                    TextField(
                      controller: _regularDurationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '주차 가능 시간',
                        hintText: '예: 720',
                        suffixText: '시간',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 그 다음 정기 요금
                    TextField(
                      controller: _regularPriceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '정기 요금',
                        hintText: '예: 10000',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  ErrorMessageText(message: _errorMessage),
                  const SizedBox(height: 24),
                  BottomButtons(
                    onCancel: () => Navigator.pop(context),
                    onSave: _handleSave,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
