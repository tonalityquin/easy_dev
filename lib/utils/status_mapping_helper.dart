class StatusMappingHelper {
  static const List<String> categories = ['공통'];

  static const Map<String, List<String>> statusMap = {
    '공통': ['VIP', '주의', '키 차안', '키 고객'],
  };

  /// 선택된 카테고리의 하위 상태 리스트 반환
  static List<String> getStatuses(String? category) {
    if (category == null) return [];
    return statusMap[category] ?? [];
  }
}