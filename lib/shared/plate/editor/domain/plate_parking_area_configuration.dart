import '../../../../features/location/domain/models/location_model.dart';

enum PlateParkingAreaMode {
  empty,
  plain,
  diagram,
  mixed,
}

class PlateParkingAreaConfiguration {
  const PlateParkingAreaConfiguration({
    required this.mode,
    required this.plainLocations,
    required this.diagramParents,
  });

  final PlateParkingAreaMode mode;
  final List<LocationModel> plainLocations;
  final List<LocationModel> diagramParents;

  int get plainCount => plainLocations.length;
  int get diagramCount => diagramParents.length;

  static PlateParkingAreaConfiguration resolve(
    Iterable<LocationModel> locations,
  ) {
    final plain = <LocationModel>[];
    final diagram = <LocationModel>[];

    for (final location in locations) {
      if (_isCompositeChild(location)) continue;
      if (_isDiagramParent(location)) {
        diagram.add(location);
        continue;
      }
      if (_isPlain(location)) {
        plain.add(location);
      }
    }

    final mode = plain.isNotEmpty && diagram.isNotEmpty
        ? PlateParkingAreaMode.mixed
        : plain.isNotEmpty
            ? PlateParkingAreaMode.plain
            : diagram.isNotEmpty
                ? PlateParkingAreaMode.diagram
                : PlateParkingAreaMode.empty;

    return PlateParkingAreaConfiguration(
      mode: mode,
      plainLocations: List<LocationModel>.unmodifiable(plain),
      diagramParents: List<LocationModel>.unmodifiable(diagram),
    );
  }

  static bool _isCompositeChild(LocationModel location) {
    return location.isCompositeChild ||
        (location.parent ?? '').trim().isNotEmpty ||
        (location.parentId ?? '').trim().isNotEmpty;
  }

  static bool _isDiagramParent(LocationModel location) {
    if (location.isCompositeParent) return true;
    final type = (location.type ?? '').trim().toLowerCase();
    return type == 'composite_parent';
  }

  static bool _isPlain(LocationModel location) {
    final type = (location.type ?? 'single').trim().toLowerCase();
    return type.isEmpty || type == 'single';
  }
}
