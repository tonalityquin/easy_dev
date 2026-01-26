import 'package:flutter/material.dart';

import 'documents/single_document_box_sheet.dart';

class SingleInsideDocumentBoxButtonSection extends StatelessWidget {
  final bool isDisabled;

  const SingleInsideDocumentBoxButtonSection({
    super.key,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: BorderSide(color: cs.primary, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      onPressed: isDisabled ? null : () => openSingleDocumentBox(context),
    );
  }
}
