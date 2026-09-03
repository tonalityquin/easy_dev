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

  bool get isValid =>
      userId.trim().isNotEmpty &&
      userName.trim().isNotEmpty &&
      area.trim().isNotEmpty &&
      division.trim().isNotEmpty;
}
