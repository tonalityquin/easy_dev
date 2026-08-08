import '../../domain/enums/plate_type.dart';
import '../../domain/repositories/plate_repository.dart';

class AreaPlateStatusCount {
  const AreaPlateStatusCount({
    required this.area,
    required this.parkingCompleted,
    required this.departureCompleted,
  });

  final String area;
  final int parkingCompleted;
  final int departureCompleted;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'parkingCompleted': parkingCompleted,
      'departureCompleted': departureCompleted,
    };
  }

  static AreaPlateStatusCount? fromJson(
    String area,
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final parkingRaw = raw['parkingCompleted'];
    final departureRaw = raw['departureCompleted'];
    if (parkingRaw is! num || departureRaw is! num) return null;
    return AreaPlateStatusCount(
      area: area.trim(),
      parkingCompleted: parkingRaw.toInt(),
      departureCompleted: departureRaw.toInt(),
    );
  }
}

class AreaPlateStatusBatchResult {
  const AreaPlateStatusBatchResult({
    required this.counts,
    required this.errors,
  });

  final Map<String, AreaPlateStatusCount> counts;
  final Map<String, String> errors;

  bool get hasErrors => errors.isNotEmpty;
}

class AreaPlateStatusCounter {
  const AreaPlateStatusCounter(this._repository);

  final PlateRepository _repository;

  Future<AreaPlateStatusCount> countArea(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      return const AreaPlateStatusCount(
        area: '',
        parkingCompleted: 0,
        departureCompleted: 0,
      );
    }

    final values = await Future.wait<int>(<Future<int>>[
      _repository.countPlatesByAreaAndType(
        area: normalizedArea,
        plateType: PlateType.parkingCompleted,
      ),
      _repository.countPlatesByAreaAndType(
        area: normalizedArea,
        plateType: PlateType.departureCompleted,
      ),
    ]);

    return AreaPlateStatusCount(
      area: normalizedArea,
      parkingCompleted: values[0],
      departureCompleted: values[1],
    );
  }

  Future<AreaPlateStatusBatchResult> countAreas(
    Iterable<String> areas,
  ) async {
    final normalizedAreas = areas
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final entries = await Future.wait<_AreaPlateStatusAttempt>(
      normalizedAreas.map((area) async {
        try {
          final count = await countArea(area);
          return _AreaPlateStatusAttempt.success(count);
        } catch (error) {
          return _AreaPlateStatusAttempt.failure(area, error.toString());
        }
      }),
    );

    final counts = <String, AreaPlateStatusCount>{};
    final errors = <String, String>{};
    for (final entry in entries) {
      final count = entry.count;
      if (count != null) {
        counts[count.area] = count;
      } else if (entry.area.isNotEmpty) {
        errors[entry.area] = entry.error ?? 'unknown_error';
      }
    }

    return AreaPlateStatusBatchResult(
      counts: counts,
      errors: errors,
    );
  }
}

class _AreaPlateStatusAttempt {
  const _AreaPlateStatusAttempt._({
    required this.area,
    this.count,
    this.error,
  });

  factory _AreaPlateStatusAttempt.success(AreaPlateStatusCount count) {
    return _AreaPlateStatusAttempt._(
      area: count.area,
      count: count,
    );
  }

  factory _AreaPlateStatusAttempt.failure(String area, String error) {
    return _AreaPlateStatusAttempt._(
      area: area,
      error: error,
    );
  }

  final String area;
  final AreaPlateStatusCount? count;
  final String? error;
}
