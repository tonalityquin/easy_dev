enum PlateCollection {
  parkingRequests,
  parkingCompleted,
  departureRequests,
  departureCompleted,
}

extension PlateCollectionExtension on PlateCollection {
  String get name {
    switch (this) {
      case PlateCollection.parkingRequests:
        return 'parking_requests';
      case PlateCollection.parkingCompleted:
        return 'parking_completed';
      case PlateCollection.departureRequests:
        return 'departure_requests';
      case PlateCollection.departureCompleted:
        return 'departure_completed';
    }
  }

  String get label {
    switch (this) {
      case PlateCollection.parkingRequests:
        return '입차 요청';
      case PlateCollection.parkingCompleted:
        return '입차 완료';
      case PlateCollection.departureRequests:
        return '출차 요청';
      case PlateCollection.departureCompleted:
        return '출차 완료';
    }
  }
}
