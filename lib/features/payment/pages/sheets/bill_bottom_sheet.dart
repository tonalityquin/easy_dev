import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';

import '../../../dev/application/area_state.dart';
import 'widgets/bill_bottom_buttons_section.dart';
import 'widgets/bill_error_message_text_section.dart';
import 'widgets/bill_standard_and_amount_row_section.dart';
import 'widgets/bill_type_input_section.dart';

class BillSettingBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic> billData) onSave;

  const BillSettingBottomSheet({super.key, required this.onSave});

  @override
  State<BillSettingBottomSheet> createState() => _BillSettingBottomSheetState();
}

class _BillSettingBottomSheetState extends State<BillSettingBottomSheet> {
  
  static const String _sheetTag = 'bill setting';

  
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

  
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Semantics(
            label: 'sheet_tag: $_sheetTag',
            child: Text(_sheetTag, style: style),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset), 
        child: SizedBox(
          height: effectiveHeight, 
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                child: Column(
                  children: [
                    
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: cs.outlineVariant.withOpacity(.65),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      '정산 유형 추가',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          children: [
                            
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

                            const SizedBox(height: 16),
                            BillErrorMessageTextSection(message: _errorMessage),
                          ],
                        ),
                      ),
                    ),

                    
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Theme(
                        
                        data: Theme.of(context).copyWith(
                          elevatedButtonTheme: ElevatedButtonThemeData(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              shape: const StadiumBorder(),
                            ),
                          ),
                          outlinedButtonTheme: OutlinedButtonThemeData(
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              side: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
                              foregroundColor: cs.onSurface,
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

              
              _buildScreenTag(context),
            ],
          ),
        ),
      ),
    );
  }
}
