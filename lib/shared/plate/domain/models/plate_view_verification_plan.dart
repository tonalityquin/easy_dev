import '../enums/plate_type.dart';

class PlateViewVerificationPlan {
  const PlateViewVerificationPlan({
    required this.plateDocId,
    required this.expectedPlateNumber,
    required this.areaAfter,
    required this.expectedType,
    required this.viewResult,
    this.areaBefore,
    this.viewActions = const <String>[],
    this.verificationEligible = true,
  });

  final String plateDocId;
  final String expectedPlateNumber;
  final String areaAfter;
  final String? areaBefore;
  final PlateType? expectedType;
  final String viewResult;
  final List<String> viewActions;
  final bool verificationEligible;

  static String? collectionFor(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return 'parking_requests_view';
      case PlateType.parkingCompleted:
        return 'parking_completed_view';
      case PlateType.departureRequests:
        return 'departure_requests_view';
      case PlateType.departureCompleted:
      case null:
        return null;
    }
  }

  Map<String, Object?> toDetails() => <String, Object?>{
        'verificationPlanVersion': 1,
        'plateDocId': plateDocId,
        'expectedPlateNumber': expectedPlateNumber,
        'areaAfter': areaAfter,
        if (areaBefore != null) 'areaBefore': areaBefore,
        'expectedPlateType': expectedType?.firestoreValue,
        'expectedViewCollection': collectionFor(expectedType),
        'expectedViewPresence': expectedType == PlateType.departureCompleted
            ? 'ABSENT'
            : expectedType == null
                ? 'UNKNOWN'
                : 'PRESENT',
        'viewResult': viewResult,
        'viewActions': List<String>.unmodifiable(viewActions),
        'verificationEligible': verificationEligible &&
            expectedType != null &&
            areaAfter.trim().isNotEmpty &&
            expectedPlateNumber.trim().isNotEmpty,
        'verification': 'NOT_VERIFIED',
      };
}
