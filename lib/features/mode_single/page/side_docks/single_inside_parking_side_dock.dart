import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../application/single_inside_diagnostics.dart';
import '../widgets/single_inside_spatial_dot_map.dart';

class SingleInsideParkingSideDock extends StatelessWidget {
  const SingleInsideParkingSideDock({
    super.key,
    required this.area,
    required this.refreshRevision,
    required this.controller,
    required this.onDetailStateChanged,
    required this.onClose,
    required this.onDeveloperStatus,
  });

  final String area;
  final int refreshRevision;
  final SingleInsideSpatialDotMapController controller;
  final ValueChanged<bool> onDetailStateChanged;
  final VoidCallback onClose;
  final Future<void> Function() onDeveloperStatus;

  @override
  Widget build(BuildContext context) {
    final areaLabel = area.trim().isEmpty ? '현재 근무지' : area.trim();
    return CommonSideDockFrame(
      title: '주차 구역',
      subtitle: areaLabel,
      icon: Icons.local_parking_rounded,
      showCloseTooltip: false,
      onClose: onClose,
      onLongPress: () {
        SingleInsideDiagnostics.log(
          'status',
          'developer_status_request source=parking_side_dock_header',
        );
        unawaited(onDeveloperStatus());
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleInsideSpatialDotMap(
          area: area,
          refreshRevision: refreshRevision,
          controller: controller,
          onDetailStateChanged: onDetailStateChanged,
        ),
      ),
    );
  }
}
