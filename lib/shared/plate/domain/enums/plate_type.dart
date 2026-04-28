enum PlateType {
  parkingRequests,
  parkingCompleted,
  departureRequests,
  departureCompleted,
}

extension PlateTypeExtension on PlateType {
  String get firestoreValue {
    switch (this) {
      case PlateType.parkingRequests:
        return 'parking_requests';
      case PlateType.parkingCompleted:
        return 'parking_completed';
      case PlateType.departureRequests:
        return 'departure_requests';
      case PlateType.departureCompleted:
        return 'departure_completed';
    }
  }

  String get label {
    switch (this) {
      case PlateType.parkingRequests:
        return '입차 요청';
      case PlateType.parkingCompleted:
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료';
    }
  }
}
