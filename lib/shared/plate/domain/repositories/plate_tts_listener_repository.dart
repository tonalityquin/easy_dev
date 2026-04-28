import '../enums/plate_type.dart';

class PlateTtsBaselineCursor {
  final DateTime? updatedAt;
  final String? docId;

  const PlateTtsBaselineCursor({
    required this.updatedAt,
    required this.docId,
  });
}

enum PlateTtsChangeType { added, modified, removed }

class PlateTtsDocChange {
  final PlateTtsChangeType type;
  final String docId;
  final Map<String, dynamic>? data;

  const PlateTtsDocChange({
    required this.type,
    required this.docId,
    required this.data,
  });
}

class PlateTtsChangeBatch {
  final bool isFromCache;
  final bool hasPendingWrites;
  final List<PlateTtsDocChange> changes;

  const PlateTtsChangeBatch({
    required this.isFromCache,
    required this.hasPendingWrites,
    required this.changes,
  });
}

abstract interface class PlateTtsListenerRepository {
  Future<PlateTtsBaselineCursor> fetchBaseline({
    required String area,
    required List<PlateType> types,
  });

  Stream<PlateTtsChangeBatch> watchChanges({
    required String area,
    required List<PlateType> types,
    DateTime? startAfterUpdatedAt,
    String? startAfterDocumentId,
  });
}
