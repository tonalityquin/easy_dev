import 'account_role.dart';
import 'account_role_diagnostics.dart';

class AccountAreaAccess {
  const AccountAreaAccess._();

  static const String notAssigned = '현재 계정에 허용되지 않은 지역입니다.';
  static const String modeUnavailable = '이 지역에서 사용할 수 있는 업무 모드가 없습니다.';
  static const String headquarterUnavailable = '본사 계정에서만 사용할 수 있는 지역입니다.';

  static bool isAssigned(Iterable<String> areas, String area) {
    final normalized = area.trim();
    return normalized.isNotEmpty &&
        areas.any((value) => value.trim() == normalized);
  }

  static bool isHeadOfficeRole(String? role) =>
      RoleType.fromName(role)?.isHeadOffice ?? false;

  static bool canUseHeadquarter({
    required String? role,
    required String division,
    required Iterable<String> divisions,
    required Iterable<String> areas,
    required String area,
  }) =>
      isHeadOfficeRole(role) &&
      area.trim() == division.trim() &&
      division.trim().isNotEmpty &&
      divisions.any((value) => value.trim() == division.trim()) &&
      isAssigned(areas, area);

  static bool canUseArea({
    required String? role,
    required String division,
    required Iterable<String> divisions,
    required Iterable<String> areas,
    required String area,
    required bool isHeadquarter,
  }) {
    final companyAllowed = division.trim().isNotEmpty &&
        divisions.any((value) => value.trim() == division.trim());
    final assigned = isAssigned(areas, area);
    final allowed = companyAllowed && assigned &&
        (!isHeadquarter ||
            canUseHeadquarter(
              role: role,
              division: division,
              divisions: divisions,
              areas: areas,
              area: area,
            ));
    AccountRoleDiagnostics.record(
      'area_access role=${role ?? 'unknown'} assigned=$assigned companyAllowed=$companyAllowed headquarter=$isHeadquarter allowed=$allowed',
    );
    return allowed;
  }

  static String deniedReason({
    required bool isAssigned,
    required bool isHeadquarter,
    required bool isHeadOffice,
    required bool modeAvailable,
  }) {
    if (!isAssigned) return notAssigned;
    if (isHeadquarter && !isHeadOffice) return headquarterUnavailable;
    if (!isHeadquarter && !modeAvailable) return modeUnavailable;
    return '';
  }
}
