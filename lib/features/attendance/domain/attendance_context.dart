class AttendanceContext {
  const AttendanceContext({
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.isHeadquarter,
    required this.modeKey,
    required this.source,
  });

  final String userId;
  final String userName;
  final String area;
  final String division;
  final bool isHeadquarter;
  final String modeKey;
  final String source;

  String get contextKey => isHeadquarter ? 'headquarter' : modeKey;

  bool get isValid {
    if (userId.trim().isEmpty ||
        userName.trim().isEmpty ||
        area.trim().isEmpty ||
        division.trim().isEmpty) {
      return false;
    }
    if (isHeadquarter) {
      return modeKey.trim().isEmpty;
    }
    return modeKey.trim().isNotEmpty;
  }
}
