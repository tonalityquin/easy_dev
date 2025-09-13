class StatusMappingHelper {
  static const List<String> categories = ['공통'];

  static const Map<String, List<String>> statusMap = {
    '공통': ['VIP', '주의', '키 차안', '키 고객'],
  };

  static List<String> getStatuses(String? category) {
    if (category == null) return [];
    return statusMap[category] ?? [];
  }
}