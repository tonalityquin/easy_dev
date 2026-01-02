// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/document_item.dart
import 'package:flutter/foundation.dart';

enum DocumentType {
  generic,
  statementForm,
  workStartReportForm,
  workEndReportForm,
}

@immutable
class DocumentItem {
  final String id;
  final String title;
  final String? subtitle;
  final DateTime updatedAt;
  final DocumentType type;

  const DocumentItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.subtitle,
    this.type = DocumentType.generic,
  });
}
