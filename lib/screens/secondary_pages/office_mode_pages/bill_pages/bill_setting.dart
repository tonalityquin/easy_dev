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
    if (fields.any((field) => field.isEmpty) || _basicStandardValue == null || _addStandardValue == null) {
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
        title: const Text('Add Bill'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Count Type 입력 필드
            TextField(
              controller: _billController,
              focusNode: _billFocus,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Count Type',
                border: OutlineInputBorder(),
                hintText: 'Enter Count type details',
              ),
            ),
            const SizedBox(height: 16),
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
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_validateInput()) {
                      final currentArea = context.read<AreaState>().currentArea;

                      // Dropdown에서 선택된 값이 String이므로, 정확히 변환되었는지 확인
                      final basicStandardInt = _basicStandardValue != null
                          ? int.tryParse(_basicStandardValue!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
                          : 0;
                      final addStandardInt = _addStandardValue != null
                          ? int.tryParse(_addStandardValue!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
                          : 0;
                      final basicAmountInt = int.tryParse(_basicAmountController.text) ?? 0;
                      final addAmountInt = int.tryParse(_addAmountController.text) ?? 0;

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
