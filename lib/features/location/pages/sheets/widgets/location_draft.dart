import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/parking_grid_model.dart';

sealed class LocationDraft {
  const LocationDraft();
}

class CompositeParentDraft extends LocationDraft {
  const CompositeParentDraft({
    required this.parent,
    required this.parkingGrid,
  });

  final String parent;
  final ParkingGridModel parkingGrid;
}

class CompositeParentUpdateDraft extends LocationDraft {
  const CompositeParentUpdateDraft({
    required this.parent,
    required this.parkingGrid,
  });

  final String parent;
  final ParkingGridModel parkingGrid;
}

class CompositeChildDraft extends LocationDraft {
  const CompositeChildDraft({
    required this.parent,
    required this.child,
    required this.capacity,
    required this.rect,
    this.childSlotAreaIds = const <String>[],
    this.childSlotNumbersByAreaId = const <String, int>{},
    this.isTower = false,
  });

  final String parent;
  final String child;
  final int capacity;
  final GridRect rect;
  final List<String> childSlotAreaIds;
  final Map<String, int> childSlotNumbersByAreaId;
  final bool isTower;
}

class CompositeChildUpdateDraft extends LocationDraft {
  const CompositeChildUpdateDraft({
    required this.id,
    required this.parent,
    required this.child,
    required this.capacity,
    required this.rect,
    this.childSlotAreaIds = const <String>[],
    this.childSlotNumbersByAreaId = const <String, int>{},
    this.isTower = false,
  });

  final String id;
  final String parent;
  final String child;
  final int capacity;
  final GridRect rect;
  final List<String> childSlotAreaIds;
  final Map<String, int> childSlotNumbersByAreaId;
  final bool isTower;
}

class PlainTextLocationDraft extends LocationDraft {
  const PlainTextLocationDraft({
    required this.name,
    required this.capacity,
  });

  final String name;
  final int capacity;
}

class PlainTextLocationUpdateDraft extends LocationDraft {
  const PlainTextLocationUpdateDraft({
    required this.id,
    required this.name,
    required this.capacity,
  });

  final String id;
  final String name;
  final int capacity;
}
