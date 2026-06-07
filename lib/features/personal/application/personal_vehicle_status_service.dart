import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/plate/domain/models/plate_model.dart';
import '../../../shared/plate/domain/services/plate_status_record.dart';
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

      for (final doc in snap.docs) {
        try {
          final plate = PlateModel.fromDocument(doc);
          if (_matchesCompact(plate.plateNumber, compact)) {
            candidates.add(plate);
          }
        } catch (e, st) {
          await DevFirebaseDebugDialog.show(
            operation: 'personal.plates.exactPlateQuery.parse',
            error: e,
            stackTrace: st,
            details: <String, Object?>{
              'collection': 'plates',
              'docId': doc.id,
              'area': normalizedArea,
              'plateNumberInput': plateNumber,
              'compact': compact,
              'query': 'where(area == $normalizedArea).where(plateNumber whereIn variants).limit(20)',
              'rawKeys': doc.data().keys.take(40).toList(growable: false),
            },
          );
        }
      }
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        operation: 'personal.plates.exactPlateQuery',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'plates',
          'area': normalizedArea,
          'plateNumberInput': plateNumber,
          'compact': compact,
          'variants': variants,
          'query': 'where(area == $normalizedArea).where(plateNumber whereIn variants).limit(20)',
          'filters': <String, Object?>{
            PlateFields.area: normalizedArea,
            PlateFields.plateNumber: 'whereIn(${variants.length})',
          },
          'orderBy': 'none',
          'limit': 20,
          'queryShape': 'compound-equality-plus-whereIn',
          'indexDebug': 'if FirebaseException.code == failed-precondition, firebase.message usually contains the composite index creation link',
          'compositeIndexCandidate': 'plates: area ASC, ${PlateFields.plateNumber} ASC',
        },
      );
    }

    if (candidates.isEmpty) {
      final tail = compact.length >= 4 ? compact.substring(compact.length - 4) : compact;
      try {
        final snap = await _firestore
            .collection('plates')
            .where(PlateFields.area, isEqualTo: normalizedArea)
            .where(PlateFields.plateFourDigit, isEqualTo: tail)
            .limit(20)
            .get();

        for (final doc in snap.docs) {
          try {
            final plate = PlateModel.fromDocument(doc);
            if (_matchesCompact(plate.plateNumber, compact)) {
              candidates.add(plate);
            }
          } catch (e, st) {
            await DevFirebaseDebugDialog.show(
              operation: 'personal.plates.tail4Query.parse',
              error: e,
              stackTrace: st,
              details: <String, Object?>{
                'collection': 'plates',
                'docId': doc.id,
                'area': normalizedArea,
                'plateNumberInput': plateNumber,
                'compact': compact,
                'tail4': tail,
                'query': 'where(area == $normalizedArea).where(plate_four_digit == $tail).limit(20)',
                'rawKeys': doc.data().keys.take(40).toList(growable: false),
              },
            );
          }
        }
      } catch (e, st) {
        await DevFirebaseDebugDialog.show(
          operation: 'personal.plates.tail4Query',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'plates',
            'area': normalizedArea,
            'plateNumberInput': plateNumber,
            'compact': compact,
            'tail4': tail,
            'query': 'where(area == $normalizedArea).where(plate_four_digit == $tail).limit(20)',
            'filters': <String, Object?>{
              PlateFields.area: normalizedArea,
              PlateFields.plateFourDigit: tail,
            },
            'orderBy': 'none',
            'limit': 20,
            'queryShape': 'compound-equality',
            'indexDebug': 'if FirebaseException.code == failed-precondition, firebase.message usually contains the composite index creation link',
            'compositeIndexCandidate': 'plates: area ASC, ${PlateFields.plateFourDigit} ASC',
          },
        );
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort(_comparePlatePriority);
    return candidates.first;
  }


  Future<PlateStatusRecord?> fetchMonthlyParkingStatus({
    required String plateNumber,
    required String area,
  }) async {
    final normalizedArea = area.trim();
    final compact = normalizePersonalPlateNumber(plateNumber);
    if (normalizedArea.isEmpty || compact.isEmpty) return null;

    final canonical = _canonicalPlateNumber(compact);
    final docId = '${canonical}_$normalizedArea';

    try {
      final doc = await _firestore.collection('monthly_plate_status').doc(docId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      return PlateStatusRecord.fromMap(data, docId: docId);
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        operation: 'personal.monthlyPlateStatus.fetch',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': docId,
          'area': normalizedArea,
          'plateNumberInput': plateNumber,
          'compact': compact,
          'canonical': canonical,
          'query': 'monthly_plate_status/$docId',
        },
      );
      return null;
    }
  }

  String _canonicalPlateNumber(String compact) {
    final raw = compact.trim().replaceAll(' ', '').replaceAll('-', '');
    final match = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(raw);
    if (match == null) return compact.trim();
    return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
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

  bool _matchesCompact(String value, String compact) {
    return normalizePersonalPlateNumber(value) == compact;
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
