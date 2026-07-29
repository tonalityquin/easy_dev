import '../services/plate_status_record.dart';

enum PlateStatusLookupState {
  idle,
  loading,
  found,
  notFound,
  inactive,
  failed,
}

class PlateStatusLookupResult {
  const PlateStatusLookupResult._({
    required this.state,
    this.record,
    this.sourcePath,
    this.error,
  });

  const PlateStatusLookupResult.found({
    required PlateStatusRecord record,
    required String sourcePath,
  }) : this._(
          state: PlateStatusLookupState.found,
          record: record,
          sourcePath: sourcePath,
        );

  const PlateStatusLookupResult.notFound()
      : this._(state: PlateStatusLookupState.notFound);

  const PlateStatusLookupResult.inactive({
    required PlateStatusRecord record,
    required String sourcePath,
  }) : this._(
          state: PlateStatusLookupState.inactive,
          record: record,
          sourcePath: sourcePath,
        );

  const PlateStatusLookupResult.failed(Object error)
      : this._(
          state: PlateStatusLookupState.failed,
          error: error,
        );

  final PlateStatusLookupState state;
  final PlateStatusRecord? record;
  final String? sourcePath;
  final Object? error;

  bool get isIdle => state == PlateStatusLookupState.idle;
  bool get isLoading => state == PlateStatusLookupState.loading;
  bool get isFound => state == PlateStatusLookupState.found;
  bool get isNotFound => state == PlateStatusLookupState.notFound;
  bool get isInactive => state == PlateStatusLookupState.inactive;
  bool get isFailed => state == PlateStatusLookupState.failed;
}

class PlateStatusConflictException implements Exception {
  const PlateStatusConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlateStatusScopeException implements Exception {
  const PlateStatusScopeException(this.message);

  final String message;

  @override
  String toString() => message;
}
