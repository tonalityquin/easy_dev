// lib/screens/simple_package/simple_inside_package/sections/simple_inside_document_form_button_section.dart

import 'package:flutter/material.dart';

import '../widgets/simple_payment_document_sheet.dart';


/// 팀원 모드용 "결재 서류" 버튼 섹션
class SimpleInsideDocumentFormButtonSection extends StatelessWidget {
  const SimpleInsideDocumentFormButtonSection({
    super.key,
    this.isDisabled = false,
  });

  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      // 결제/영수증 느낌의 아이콘
      icon: const Icon(Icons.receipt_long),
      label: const Text(
        '결재 서류',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // ✅ 이제 실제로 결재 서류 선택 바텀시트를 연다
      onPressed:
      isDisabled ? null : () => openSimplePaymentDocumentSheet(context),
    );
  }
}
