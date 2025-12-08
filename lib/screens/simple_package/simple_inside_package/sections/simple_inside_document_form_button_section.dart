// lib/screens/simple_package/simple_inside_package/sections/simple_inside_document_form_button_section.dart

import 'package:flutter/material.dart';

/// 팀원 모드용 "서류 양식" 버튼 섹션
class SimpleInsideDocumentFormButtonSection extends StatelessWidget {
  const SimpleInsideDocumentFormButtonSection({
    super.key,
    this.isDisabled = false,
  });

  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.description_outlined),
      label: const Text(
        '서류 양식',
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
      onPressed: isDisabled
          ? null
          : () {
        // TODO: 실제 서류 양식 기능(예: 템플릿 선택 바텀시트, AppRoutes.attendanceSheet 이동 등)으로 교체
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('서류 양식 기능은 아직 연결되지 않았습니다.'),
          ),
        );
      },
    );
  }
}
