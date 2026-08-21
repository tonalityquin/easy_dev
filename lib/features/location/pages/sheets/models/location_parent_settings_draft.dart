import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/parking_grid_model.dart';

class LocationParentSettingsDraft {
  const LocationParentSettingsDraft({
    required this.name,
    required this.parkingGrid,
  });

  final String name;
  final ParkingGridModel parkingGrid;

  LocationParentSettingsDraft copyWith({
    String? name,
    ParkingGridModel? parkingGrid,
  }) {
    return LocationParentSettingsDraft(
      name: name ?? this.name,
      parkingGrid: parkingGrid ?? this.parkingGrid,
    );
  }

  LocationParentSettingsDraft detached() {
    return LocationParentSettingsDraft(
      name: name,
      parkingGrid: detachedParkingGrid(parkingGrid),
    );
  }

  static ParkingGridModel detachedParkingGrid(ParkingGridModel grid) {
    return ParkingGridModel.fromEnumCells(
      rows: grid.rows,
      cols: grid.cols,
      cells: List<ParkingGridCellType>.from(grid.cells),
      parkingAreas: List<ParkingArea>.from(grid.parkingAreas),
      entranceRects: grid.entranceRects
          .map((rect) => GridRect(
                r0: rect.r0,
                c0: rect.c0,
                r1: rect.r1,
                c1: rect.c1,
              ))
          .toList(growable: false),
      exitRects: grid.exitRects
          .map((rect) => GridRect(
                r0: rect.r0,
                c0: rect.c0,
                r1: rect.r1,
                c1: rect.c1,
              ))
          .toList(growable: false),
      towerRects: grid.towerRects
          .map((rect) => GridRect(
                r0: rect.r0,
                c0: rect.c0,
                r1: rect.r1,
                c1: rect.c1,
              ))
          .toList(growable: false),
      road2Cells: List<int>.from(grid.road2Cells),
    );
  }
}
