import 'package:flutter/foundation.dart';

enum SupportDocumentType {
  generic,
  statementForm,
  workStartReportForm,
  workEndReportForm,
  handoverForm,
}

/// 문서철에 표시되는 1개의 문서 정보
@immutable
class SupportDocumentItem {
  /// 라우팅/분기용 ID (예: 'template-statement', 'template-commute-record')
  final String id;

  /// 문서 제목 (리스트에 표시되는 메인 타이틀)
  final String title;

  /// 부제목 (선택)
  final String? subtitle;

  /// 최근 갱신 시각 (UI 하단 "수정: yyyy-MM-dd HH:mm" 표시용)
  final DateTime updatedAt;

  /// 문서 유형 (레이블/아이콘/색상 기본값 결정)
  final SupportDocumentType type;

  const SupportDocumentItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.subtitle,
    this.type = SupportDocumentType.generic,
  });
}
