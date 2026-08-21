import 'package:flutter/material.dart';

import 'widgets/parking_grid_2d_editor.dart';

enum LocationParentToolCategory { structure, parking, facility, cleanup }

class LocationParentToolSpec {
  const LocationParentToolSpec({
    required this.tool,
    required this.category,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final GridEditTool tool;
  final LocationParentToolCategory category;
  final String label;
  final String detail;
  final IconData icon;
}

const List<LocationParentToolSpec> locationParentToolSpecs =
    <LocationParentToolSpec>[
  LocationParentToolSpec(
    tool: GridEditTool.wall,
    category: LocationParentToolCategory.structure,
    label: '벽',
    detail: '부모구역 내부 벽을 셀 단위로 배치합니다.',
    icon: Icons.view_week_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.road,
    category: LocationParentToolCategory.structure,
    label: '도로 1',
    detail: '기본 이동 통로를 배치합니다.',
    icon: Icons.route_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.road2,
    category: LocationParentToolCategory.structure,
    label: '도로 2',
    detail: '보조 이동 통로를 배치합니다.',
    icon: Icons.alt_route_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.pillar,
    category: LocationParentToolCategory.structure,
    label: '기둥',
    detail: '기둥을 셀 단위로 배치합니다.',
    icon: Icons.domain_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingCompact12,
    category: LocationParentToolCategory.parking,
    label: '경형 1×2',
    detail: '경형 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingCompact21,
    category: LocationParentToolCategory.parking,
    label: '경형 2×1',
    detail: '경형 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingStandard12,
    category: LocationParentToolCategory.parking,
    label: '일반형 1×2',
    detail: '일반 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingStandard21,
    category: LocationParentToolCategory.parking,
    label: '일반형 2×1',
    detail: '일반 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingExtendedA12,
    category: LocationParentToolCategory.parking,
    label: '확장형 A 1×2',
    detail: '확장형 A 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingExtendedA21,
    category: LocationParentToolCategory.parking,
    label: '확장형 A 2×1',
    detail: '확장형 A 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingExtendedB22,
    category: LocationParentToolCategory.parking,
    label: '확장형 B 2×2',
    detail: '확장형 B 주차면을 배치합니다.',
    icon: Icons.local_parking_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvCompact12,
    category: LocationParentToolCategory.parking,
    label: '전기차 경형 1×2',
    detail: '전기차 경형 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvCompact21,
    category: LocationParentToolCategory.parking,
    label: '전기차 경형 2×1',
    detail: '전기차 경형 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvStandard12,
    category: LocationParentToolCategory.parking,
    label: '전기차 일반형 1×2',
    detail: '전기차 일반 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvStandard21,
    category: LocationParentToolCategory.parking,
    label: '전기차 일반형 2×1',
    detail: '전기차 일반 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvExtendedA12,
    category: LocationParentToolCategory.parking,
    label: '전기차 확장형 A 1×2',
    detail: '전기차 확장형 A 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvExtendedA21,
    category: LocationParentToolCategory.parking,
    label: '전기차 확장형 A 2×1',
    detail: '전기차 확장형 A 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEvExtendedB22,
    category: LocationParentToolCategory.parking,
    label: '전기차 확장형 B 2×2',
    detail: '전기차 확장형 B 주차면을 배치합니다.',
    icon: Icons.ev_station_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingPregnantExtendedA12,
    category: LocationParentToolCategory.parking,
    label: '임산부 1×2',
    detail: '임산부 전용 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.pregnant_woman_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingPregnantExtendedA21,
    category: LocationParentToolCategory.parking,
    label: '임산부 2×1',
    detail: '임산부 전용 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.pregnant_woman_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingPregnantExtendedB22,
    category: LocationParentToolCategory.parking,
    label: '임산부 2×2',
    detail: '임산부 전용 확장 주차면을 배치합니다.',
    icon: Icons.pregnant_woman_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingDisabledStandard12,
    category: LocationParentToolCategory.parking,
    label: '장애인 일반형 1×2',
    detail: '장애인 전용 일반 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.accessible_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingDisabledStandard21,
    category: LocationParentToolCategory.parking,
    label: '장애인 일반형 2×1',
    detail: '장애인 전용 일반 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.accessible_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingDisabledExtendedA12,
    category: LocationParentToolCategory.parking,
    label: '장애인 확장형 A 1×2',
    detail: '장애인 전용 확장 주차면을 세로 방향으로 배치합니다.',
    icon: Icons.accessible_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingDisabledExtendedA21,
    category: LocationParentToolCategory.parking,
    label: '장애인 확장형 A 2×1',
    detail: '장애인 전용 확장 주차면을 가로 방향으로 배치합니다.',
    icon: Icons.accessible_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingDisabledExtendedB22,
    category: LocationParentToolCategory.parking,
    label: '장애인 확장형 B 2×2',
    detail: '장애인 전용 확장 주차면을 배치합니다.',
    icon: Icons.accessible_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.entranceRect,
    category: LocationParentToolCategory.facility,
    label: '입구',
    detail: '입구 영역을 드래그하여 배치합니다.',
    icon: Icons.login_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.exitRect,
    category: LocationParentToolCategory.facility,
    label: '출구',
    detail: '출구 영역을 드래그하여 배치합니다.',
    icon: Icons.logout_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.towerRect,
    category: LocationParentToolCategory.facility,
    label: '주차 타워',
    detail: '주차 타워 영역을 드래그하여 배치합니다.',
    icon: Icons.apartment_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.empty,
    category: LocationParentToolCategory.cleanup,
    label: '셀 지우기',
    detail: '벽·도로·기둥 셀을 빈칸으로 되돌립니다.',
    icon: Icons.delete_outline_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.parkingEraser,
    category: LocationParentToolCategory.cleanup,
    label: '주차면 삭제',
    detail: '선택한 주차면을 삭제합니다.',
    icon: Icons.delete_sweep_rounded,
  ),
  LocationParentToolSpec(
    tool: GridEditTool.rectEraser,
    category: LocationParentToolCategory.cleanup,
    label: '시설 영역 삭제',
    detail: '입구·출구·주차 타워 영역을 삭제합니다.',
    icon: Icons.layers_clear_rounded,
  ),
];

String locationParentToolCategoryLabel(LocationParentToolCategory category) {
  switch (category) {
    case LocationParentToolCategory.structure:
      return '기본 구조';
    case LocationParentToolCategory.parking:
      return '주차 구역';
    case LocationParentToolCategory.facility:
      return '시설';
    case LocationParentToolCategory.cleanup:
      return '삭제 및 정리';
  }
}

IconData locationParentToolCategoryIcon(LocationParentToolCategory category) {
  switch (category) {
    case LocationParentToolCategory.structure:
      return Icons.grid_view_rounded;
    case LocationParentToolCategory.parking:
      return Icons.local_parking_rounded;
    case LocationParentToolCategory.facility:
      return Icons.apartment_rounded;
    case LocationParentToolCategory.cleanup:
      return Icons.cleaning_services_rounded;
  }
}

LocationParentToolSpec locationParentToolSpec(GridEditTool tool) {
  return locationParentToolSpecs.firstWhere((spec) => spec.tool == tool);
}
