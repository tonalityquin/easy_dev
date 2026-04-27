import 'package:flutter/foundation.dart';

enum SingleDocumentType {
  generic,
  statementForm,
  workStartReportForm,
  workEndReportForm,
  handoverForm,
}

@immutable
class SingleDocumentItem {
  final String id;
  final String title;
  final String? subtitle;
  final DateTime updatedAt;
  final SingleDocumentType type;

  const SingleDocumentItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.subtitle,
    this.type = SingleDocumentType.generic,
  });
}
