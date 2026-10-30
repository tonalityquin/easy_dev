import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../shared/plate/domain/services/plate_document_paths.dart';

class EndWorkReportPaths {
  const EndWorkReportPaths._();

  static String rootId({required String companyId, required String area}) {
    return PlateDocumentPaths.viewId(area, companyId: companyId);
  }

  static DocumentReference<Map<String, dynamic>> root(
    FirebaseFirestore firestore, {
    required String companyId,
    required String area,
  }) {
    return firestore.collection('end_work_reports').doc(
      rootId(companyId: companyId, area: area),
    );
  }

  static Map<String, dynamic> scope({
    required String companyId,
    required String area,
  }) {
    final id = PlateDocumentPaths.companyFor(area, companyId: companyId);
    return <String, dynamic>{
      'companyId': id,
      'division': id,
      'areaId': PlateDocumentPaths.areaId(area, companyId: id),
      'area': area.trim(),
    };
  }

  static String areaFromRootId(String id) {
    final marker = id.indexOf('~');
    if (marker > 0) {
      final company = id.substring(0, marker);
      final suffix = id.substring(marker + 1);
      final prefix = '$company-';
      if (suffix.startsWith(prefix)) return suffix.substring(prefix.length);
    }
    return id.startsWith('area_') ? id.substring(5) : id;
  }
}
