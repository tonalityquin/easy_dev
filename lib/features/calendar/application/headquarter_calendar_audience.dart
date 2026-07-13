bool isHeadquarterCalendarStaffScope({
  required String role,
  required String position,
  required String division,
}) {
  final text = '$role $position $division'.toLowerCase();
  return text.contains('head') ||
      text.contains('hq') ||
      text.contains('headquarter') ||
      text.contains('본사') ||
      text.contains('총괄');
}
