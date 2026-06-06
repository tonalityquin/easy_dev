import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/plate/domain/models/plate_model.dart';
import '../domain/models/personal_saved_vehicle.dart';

class PersonalVehicleStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PlateModel?> fetchCurrentVehiclePlate({
    required String plateNumber,
    required String area,
  }) async {
    final normalizedArea = area.trim();
    final compact = normalizePersonalPlateNumber(plateNumber);
    if (normalizedArea.isEmpty || compact.isEmpty) return null;

    final variants = _plateNumberVariants(compact).take(10).toList(growable: false);
    if (variants.isEmpty) return null;

    final candidates = <PlateModel>[];

    try {
      final snap = await _firestore
          .collection('plates')
          .where(PlateFields.area, isEqualTo: normalizedArea)
          .where(PlateFields.plateNumber, whereIn: variants)
          .limit(20)
          .get();
      candidates.addAll(
        snap.docs
            .map((doc) => PlateModel.fromDocument(doc))
            .where((plate) => _matchesCompact(plate.plateNumber, compact)),
      );
    } catch (_) {}

    if (candidates.isEmpty) {
      final tail = compact.length >= 4 ? compact.substring(compact.length - 4) : compact;
      try {
        final snap = await _firestore
            .collection('plates')
            .where(PlateFields.area, isEqualTo: normalizedArea)
            .where(PlateFields.plateFourDigit, isEqualTo: tail)
            .limit(20)
            .get();
        candidates.addAll(
          snap.docs
              .map((doc) => PlateModel.fromDocument(doc))
              .where((plate) => _matchesCompact(plate.plateNumber, compact)),
        );
      } catch (_) {}
    }

    if (candidates.isEmpty) return null;
    candidates.sort(_comparePlatePriority);
    return candidates.first;
  }

  bool _matchesCompact(String value, String target) {
    return normalizePersonalPlateNumber(value) == target;
  }

  Set<String> _plateNumberVariants(String compact) {
    final out = <String>{};
    if (compact.isEmpty) return out;
    out.add(compact);
    final match = RegExp(r'^(\d{2,3})([가-힣])([0-9]{4})$').firstMatch(compact);
    if (match != null) {
      final head = match.group(1)!;
      final mid = match.group(2)!;
      final tail = match.group(3)!;
      out.add('$head$mid$tail');
      out.add('$head$mid $tail');
      out.add('$head-$mid-$tail');
      out.add('$head $mid $tail');
    }
    return out;
  }

  int _comparePlatePriority(PlateModel a, PlateModel b) {
    final ar = _typeRank(a.typeEnum);
    final br = _typeRank(b.typeEnum);
    if (ar != br) return ar.compareTo(br);
    final ad = a.updatedAt ?? a.requestTime;
    final bd = b.updatedAt ?? b.requestTime;
    return bd.compareTo(ad);
  }

  int _typeRank(PlateType? type) {
    switch (type) {
      case PlateType.parkingCompleted:
        return 0;
      case PlateType.departureRequests:
        return 1;
      case PlateType.departureCompleted:
        return 2;
      case PlateType.parkingRequests:
        return 3;
      case null:
        return 9;
    }
  }
}
