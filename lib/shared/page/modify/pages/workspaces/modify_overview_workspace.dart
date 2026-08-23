import 'package:flutter/material.dart';

import '../../../../plate/domain/models/plate_model.dart';
import '../../../../plate/editor/domain/plate_editor_workspace.dart';
import '../../../../plate/editor/domain/plate_parking_display.dart';
import '../../../../plate/editor/widgets/plate_editor_overview.dart';
import '../../controllers/modify_plate_controller.dart';

class ModifyOverviewWorkspace extends StatelessWidget {
  const ModifyOverviewWorkspace({
    super.key,
    required this.controller,
    required this.plate,
    required this.policy,
    required this.statusContextResolving,
    required this.statusContextError,
    required this.onRegionTap,
    required this.onWorkspaceTap,
  });

  final ModifyPlateController controller;
  final PlateModel plate;
  final PlateEditorPolicy policy;
  final bool statusContextResolving;
  final String? statusContextError;
  final VoidCallback onRegionTap;
  final ValueChanged<PlateEditorWorkspace> onWorkspaceTap;

  bool get _hasVariableBillingSelection =>
      controller.selectedBillType == '변동' && controller.hasBillingSelection;

  bool get _hasRegularBillingSelection =>
      controller.selectedBillType == '정기' && controller.hasBillingSelection;

  String _variableBillingSummary() {
    if (!_hasVariableBillingSelection) return '';
    final countType = controller.selectedBillCountType?.trim().isNotEmpty == true
        ? controller.selectedBillCountType!.trim()
        : controller.selectedBill?.trim() ?? '';
    if (countType.isEmpty) return '';
    return '$countType · ${controller.selectedBasicStandard}분 · ${controller.selectedBasicAmount}원';
  }

  String _regularBillingSummary() {
    if (!_hasRegularBillingSelection) return '';
    final countType = controller.selectedBillCountType?.trim().isNotEmpty == true
        ? controller.selectedBillCountType!.trim()
        : controller.selectedBill?.trim() ?? '';
    if (countType.isEmpty) return '';
    return '$countType · ${controller.selectedRegularDurationHours}시간 · ${controller.selectedRegularAmount}원';
  }

  String _parkingSummary() {
    final location = controller.locationController.text.trim();
    final priorityCount = controller.selectedParkingPriorities.length;
    final locationValue = location.isEmpty
        ? ''
        : plateParkingOverviewLocation(location);
    if (priorityCount == 0) return locationValue;
    if (locationValue.isEmpty) return '우선 $priorityCount';
    return '$locationValue · 우선 $priorityCount';
  }

  PlateEditorSectionStatus _changed(bool value) {
    return value
        ? PlateEditorSectionStatus.changed
        : PlateEditorSectionStatus.none;
  }

  @override
  Widget build(BuildContext context) {
    final memo = controller.customStatusController.text.trim();
    final sections = <Widget>[
      PlateEditorVehicleIdentitySection(
        region: controller.dropdownValue,
        plate: controller.currentPlateNumberDisplay,
        regionStatus: _changed(controller.hasRegionChanges),
        plateStatus: PlateEditorSectionStatus.none,
        onRegionTap: onRegionTap,
        onPlateTap: null,
      ),
      PlateEditorOverviewSection(
        icon: Icons.local_parking_rounded,
        title: '주차',
        value: _parkingSummary(),
        status: _changed(controller.hasLocationChanges),
        onTap: () => onWorkspaceTap(PlateEditorWorkspace.parking),
      ),
      PlateEditorOverviewPhotoSection(
        summary:
            '등록 ${plate.imageUrls?.length ?? 0} · 신규 ${controller.capturedImages.length}',
        status: _changed(controller.hasPhotoChanges),
        onTap: () => onWorkspaceTap(PlateEditorWorkspace.camera),
      ),
      if (policy.hasSector)
        PlateEditorOverviewSection(
          icon: Icons.place_rounded,
          title: '방문 구역',
          value: controller.selectedSectorName?.trim().isNotEmpty == true
              ? controller.selectedSectorName!.trim()
              : '',
          status: _changed(controller.hasSectorChanges),
          onTap: () => onWorkspaceTap(PlateEditorWorkspace.sector),
        ),
      if (policy.hasBill)
        PlateEditorOverviewSection(
          icon: Icons.receipt_long_rounded,
          title: '변동 정산',
          value: _variableBillingSummary(),
          status: _hasVariableBillingSelection
              ? _changed(controller.hasBillingChanges)
              : PlateEditorSectionStatus.none,
          onTap: () => onWorkspaceTap(PlateEditorWorkspace.variableBilling),
        ),
      if (policy.hasBill)
        PlateEditorOverviewSection(
          icon: Icons.calendar_month_rounded,
          title: '정기 정산',
          value: _regularBillingSummary(),
          status: _hasRegularBillingSelection
              ? _changed(controller.hasBillingChanges)
              : PlateEditorSectionStatus.none,
          onTap: () => onWorkspaceTap(PlateEditorWorkspace.regularBilling),
        ),
      PlateEditorOverviewSection(
        icon: statusContextError != null
            ? Icons.warning_amber_rounded
            : Icons.notes_rounded,
        title: '상태 메모',
        value: statusContextResolving
            ? '상태 정보 확인 중'
            : statusContextError != null
                ? '상태 정보를 확인하지 못했습니다.'
                : memo,
        status: statusContextResolving
            ? PlateEditorSectionStatus.loading
            : statusContextError != null
                ? PlateEditorSectionStatus.error
                : _changed(controller.hasStatusChanges),
        onTap: () => onWorkspaceTap(PlateEditorWorkspace.memo),
      ),
    ];

    return PlateEditorOverview(
      title: '차량 정보',
      subtitle: controller.changeCount == 0
          ? '변경 없음'
          : '변경 ${controller.changeCount}개',
      sections: sections,
    );
  }
}
