// lib/screens/simple_package/sections/documents/document_item.dart
import 'package:flutter/foundation.dart';

/// 문서 유형
///
/// - [statementForm]
///   - 경위서, 출퇴근 기록, 휴게시간 기록 등 "진술/사유서" 계열 문서
/// - [generic]
///   - 연차(결근) 신청서, 사직서 등 일반 신청/기타 문서
/// - [workStartReportForm], [workEndReportForm], [handoverForm]
///   - 기존 서비스 모드에서 사용하던 업무 시작/종료/인수인계 양식용 타입
enum DocumentType {
  generic,
  statementForm,
  workStartReportForm,
  workEndReportForm,
  handoverForm,
}

/// 문서철에 표시되는 1개의 문서 정보
@immutable
class DocumentItem {
  /// 라우팅/분기용 ID (예: 'template-statement', 'template-commute-record')
  final String id;

  /// 문서 제목 (리스트에 표시되는 메인 타이틀)
  final String title;

  /// 부제목 (선택)
  final String? subtitle;

  /// 최근 갱신 시각 (UI 하단 "수정: yyyy-MM-dd HH:mm" 표시용)
  final DateTime updatedAt;

  /// 문서 유형 (레이블/아이콘/색상 기본값 결정)
  final DocumentType type;

  const DocumentItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.subtitle,
    this.type = DocumentType.generic,
  });
}
