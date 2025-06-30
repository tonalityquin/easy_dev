class StatusMappingHelper {
  static const List<String> categories = ['병원', '카페'];

  static const Map<String, List<String>> statusMap = {
    '병원': ['VIP', '목발', '휠체어', '장애인'],
    '카페': ['VIP', 'SUV', '경차'],
  };

  /// 선택된 카테고리의 하위 상태 리스트 반환
  static List<String> getStatuses(String? category) {
    if (category == null) return [];
    return statusMap[category] ?? [];
  }
}
