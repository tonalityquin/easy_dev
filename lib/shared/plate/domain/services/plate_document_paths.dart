import '../../../area_remote_settings/application/area_snapshot_scope.dart';

class PlateDocumentPaths {
  const PlateDocumentPaths._();

  static String companyFor(String area, {String? companyId}) {
    final company = (companyId ?? AreaSnapshotScope.division).trim();
    final name = area.trim();
    if (company.isEmpty || name.isEmpty ||
        company.contains('~') || name.contains('~') ||
        company.contains('/') || name.contains('/')) {
      throw StateError('PLATE_SCOPE_INVALID');
    }
    if (companyId == null &&
        (!AreaSnapshotScope.isBound || AreaSnapshotScope.area != name)) {
      throw StateError('PLATE_SCOPE_NOT_BOUND');
    }
    return company;
  }

  static String areaId(String area, {String? companyId}) {
    final company = companyFor(area, companyId: companyId);
    return '$company-${area.trim()}';
  }

  static String viewId(String area, {String? companyId}) {
    final company = companyFor(area, companyId: companyId);
    return '$company~${areaId(area, companyId: company)}';
  }

  static String counterId(String area, {String? companyId}) =>
      viewId(area, companyId: companyId);

  static String plateNumberFromId(String id) {
    final pos = id.lastIndexOf('~');
    return pos >= 0 ? id.substring(pos + 1) : id.split('_').first;
  }

  static String areaFromId(String id, {String? companyId}) {
    final company = (companyId ?? AreaSnapshotScope.division).trim();
    final prefix = '$company~$company-';
    if (id.startsWith(prefix)) {
      final rest = id.substring(prefix.length);
      final end = rest.lastIndexOf('~');
      if (end > 0) return rest.substring(0, end);
    }
    return AreaSnapshotScope.area;
  }

  static String plateKey(String plateNumber) {
    final value = plateNumber.replaceAll(RegExp(r'[\s-]'), '').trim();
    if (value.isEmpty || value.contains('/') || value.contains('~')) {
      throw StateError('PLATE_NUMBER_INVALID');
    }
    return value;
  }

  static String vehicleId(String plateNumber, String area, {String? companyId}) {
    final company = companyFor(area, companyId: companyId);
    return '$company~${areaId(area, companyId: company)}~${plateKey(plateNumber)}';
  }
}
