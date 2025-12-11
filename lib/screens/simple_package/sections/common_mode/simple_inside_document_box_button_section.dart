// lib/screens/simple_package/simple_inside_package/sections/simple_inside_document_box_button_section.dart
import 'package:flutter/material.dart';

import '../documents/simple_document_box_sheet.dart';

class SimpleInsideDocumentBoxButtonSection extends StatelessWidget {
  final bool isDisabled;

  const SimpleInsideDocumentBoxButtonSection({
    super.key,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.folder_open),
      label: const Text(
        '서류함 열기',
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
      // ✅ 이제 실제로 문서철 바텀시트를 연다
      onPressed: isDisabled ? null : () => openDocumentBox(context),
    );
  }
}
