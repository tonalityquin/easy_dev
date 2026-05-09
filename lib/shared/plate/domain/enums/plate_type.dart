enum PlateType {
  parkingRequests,
  parkingCompleted,
  departureRequests,
  departureCompleted,
}

class PlateTypeFirestoreValue {
  const PlateTypeFirestoreValue._();

  static const String parkingRequests = '입차 요청';
  static const String parkingCompleted = '입차 완료';
  static const String departureRequests = '출차 요청';
  static const String departureCompleted = '출차 완료';
}

class PlateTypeLegacyFirestoreValue {
  const PlateTypeLegacyFirestoreValue._();

  static const String parkingRequests = 'parking_requests';
  static const String parkingCompleted = 'parking_completed';
  static const String departureRequests = 'departure_requests';
  static const String departureCompleted = 'departure_completed';
}

extension PlateTypeExtension on PlateType {
  String get firestoreValue {
    switch (this) {
      case PlateType.parkingRequests:
        return PlateTypeFirestoreValue.parkingRequests;
      case PlateType.parkingCompleted:
        return PlateTypeFirestoreValue.parkingCompleted;
      case PlateType.departureRequests:
        return PlateTypeFirestoreValue.departureRequests;
      case PlateType.departureCompleted:
        return PlateTypeFirestoreValue.departureCompleted;
    }
  }

  String get legacyFirestoreValue {
    switch (this) {
      case PlateType.parkingRequests:
        return PlateTypeLegacyFirestoreValue.parkingRequests;
      case PlateType.parkingCompleted:
        return PlateTypeLegacyFirestoreValue.parkingCompleted;
      case PlateType.departureRequests:
        return PlateTypeLegacyFirestoreValue.departureRequests;
      case PlateType.departureCompleted:
        return PlateTypeLegacyFirestoreValue.departureCompleted;
    }
  }

  String get label => firestoreValue;
}

PlateType? plateTypeFromFirestoreValue(dynamic value) {
  final normalized = (value ?? '').toString().trim();
  switch (normalized) {
    case PlateTypeFirestoreValue.parkingRequests:
    case PlateTypeLegacyFirestoreValue.parkingRequests:
      return PlateType.parkingRequests;
    case PlateTypeFirestoreValue.parkingCompleted:
    case PlateTypeLegacyFirestoreValue.parkingCompleted:
      return PlateType.parkingCompleted;
    case PlateTypeFirestoreValue.departureRequests:
    case PlateTypeLegacyFirestoreValue.departureRequests:
      return PlateType.departureRequests;
    case PlateTypeFirestoreValue.departureCompleted:
    case PlateTypeLegacyFirestoreValue.departureCompleted:
      return PlateType.departureCompleted;
    default:
      return null;
  }
}

String normalizePlateTypeFirestoreValue(dynamic value) {
  final type = plateTypeFromFirestoreValue(value);
  if (type != null) return type.firestoreValue;
  return (value ?? '').toString().trim();
}
