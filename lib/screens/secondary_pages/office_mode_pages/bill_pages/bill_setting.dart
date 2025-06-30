import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../states/area/area_state.dart';

class BillSetting extends StatefulWidget {
  final Function(Map<String, dynamic> billData) onSave;

  const BillSetting({super.key, required this.onSave});

  @override
  State<BillSetting> createState() => _BillSettingState();
}

class _BillSettingState extends State<BillSetting> {
  final TextEditingController _billController = TextEditingController();
  final TextEditingController _basicAmountController = TextEditingController();
  final TextEditingController _addAmountController = TextEditingController();
  final FocusNode _billFocus = FocusNode();
  final FocusNode _basicAmountFocus = FocusNode();
  final FocusNode _addAmountFocus = FocusNode();

  String? _errorMessage;
  String? _basicStandardValue;
  String? _addStandardValue;

  static const List<String> _basicStandardOptions = ['1분', '5분', '30분', '60분'];
  static const List<String> _addStandardOptions = ['1분', '10분', '30분', '60분'];

  @override
  void dispose() {
    _billController.dispose();
    _basicAmountController.dispose();
    _addAmountController.dispose();
    _billFocus.dispose();
    _basicAmountFocus.dispose();
    _addAmountFocus.dispose();
    super.dispose();
  }

  bool _validateInput() {
    final fields = [
      _billController.text,
      _basicAmountController.text,
      _addAmountController.text,
    ];
    if (fields.any((field) => field.isEmpty) ||
        _basicStandardValue == null ||
        _addStandardValue == null) {
      setState(() {
        _errorMessage = '모든 필드를 입력하세요.';
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '요금 설정',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Count Type 입력 필드
                TextField(
                  controller: _billController,
                  focusNode: _billFocus,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '요금 종류',
                    hintText: '예: 기본 요금',
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _basicStandardValue,
                        decoration: InputDecoration(
                          labelText: '기본 시간',
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        dropdownColor: Colors.white,
                        iconEnabledColor: Colors.green,
                        items: _basicStandardOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                            .toList(),
                        onChanged: (newValue) {
                          setState(() {
                            _basicStandardValue = newValue;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _basicAmountController,
                        focusNode: _basicAmountFocus,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '기본 요금',
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _addStandardValue,
                        decoration: InputDecoration(
                          labelText: '추가 시간',
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        dropdownColor: Colors.white,
                        iconEnabledColor: Colors.green,
                        items: _addStandardOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                            .toList(),
                        onChanged: (newValue) {
                          setState(() {
                            _addStandardValue = newValue;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _addAmountController,
                        focusNode: _addAmountFocus,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '추가 요금',
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.withOpacity(0.2),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_validateInput()) {
                            final currentArea = context.read<AreaState>().currentArea;

                            final basicStandardInt = _basicStandardValue != null
                                ? int.tryParse(
                                _basicStandardValue!.replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0
                                : 0;
                            final addStandardInt = _addStandardValue != null
                                ? int.tryParse(
                                _addStandardValue!.replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0
                                : 0;
                            final basicAmountInt =
                                int.tryParse(_basicAmountController.text) ?? 0;
                            final addAmountInt =
                                int.tryParse(_addAmountController.text) ?? 0;

                            debugPrint(
                                "📌 저장 전 변환된 값 - basicStandard: $basicStandardInt, addStandard: $addStandardInt, basicAmount: $basicAmountInt, addAmount: $addAmountInt");

                            widget.onSave({
                              'CountType': _billController.text,
                              'basicStandard': basicStandardInt,
                              'basicAmount': basicAmountInt,
                              'addStandard': addStandardInt,
                              'addAmount': addAmountInt,
                              'area': currentArea,
                              'isSelected': false,
                            });
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
