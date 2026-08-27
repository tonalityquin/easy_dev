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
    required this.isMinorMode,
    required this.onRegionTap,
    required this.onWorkspaceTap,
  });

  final ModifyPlateController controller;
  final PlateModel plate;
  final PlateEditorPolicy policy;
  final bool statusContextResolving;
  final String? statusContextError;
  final bool isMinorMode;
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

  @override
  Widget build(BuildContext context) {
    final memo = controller.customStatusController.text.trim();
    final parkingValue = _parkingSummary();
    final hasParking = parkingValue.trim().isNotEmpty;
    final hasPhotos = (plate.imageUrls?.isNotEmpty ?? false) ||
        controller.capturedImages.isNotEmpty;
    final hasSector = controller.selectedSectorName?.trim().isNotEmpty == true;
    final sections = <Widget>[
      PlateEditorVehicleIdentitySection(
        region: controller.dropdownValue,
        plate: controller.currentPlateNumberDisplay,
        regionStatus: controller.dropdownValue.trim().isNotEmpty
            ? PlateEditorSectionStatus.complete
            : PlateEditorSectionStatus.incomplete,
        plateStatus: controller.currentPlateNumberDisplay.trim().isNotEmpty
            ? PlateEditorSectionStatus.complete
            : PlateEditorSectionStatus.incomplete,
        onRegionTap: onRegionTap,
        onPlateTap: null,
      ),
      PlateEditorOverviewSection(
        icon: Icons.local_parking_rounded,
        title: '주차 구역',
        value: parkingValue,
        status: hasParking
            ? PlateEditorSectionStatus.complete
            : isMinorMode
                ? PlateEditorSectionStatus.optional
                : PlateEditorSectionStatus.incomplete,
        onTap: () => onWorkspaceTap(PlateEditorWorkspace.parking),
      ),
      PlateEditorOverviewPhotoSection(
        summary:
            '등록 ${plate.imageUrls?.length ?? 0} · 신규 ${controller.capturedImages.length}',
        status: hasPhotos
            ? PlateEditorSectionStatus.complete
            : PlateEditorSectionStatus.none,
        onTap: () => onWorkspaceTap(PlateEditorWorkspace.camera),
      ),
      if (policy.hasSector)
        PlateEditorOverviewSection(
          icon: Icons.place_rounded,
          title: '방문 구역',
          value: controller.selectedSectorName?.trim().isNotEmpty == true
              ? controller.selectedSectorName!.trim()
              : '',
          status: hasSector
              ? PlateEditorSectionStatus.complete
              : PlateEditorSectionStatus.incomplete,
          onTap: () => onWorkspaceTap(PlateEditorWorkspace.sector),
        ),
      if (policy.hasBill)
        PlateEditorOverviewSection(
          icon: Icons.receipt_long_rounded,
          title: '정산 유형',
          value: _variableBillingSummary(),
          enabled: !controller.billingLocked,
          status: _hasVariableBillingSelection
              ? PlateEditorSectionStatus.complete
              : PlateEditorSectionStatus.none,
          onTap: () => onWorkspaceTap(PlateEditorWorkspace.variableBilling),
        ),
      if (policy.hasBill)
        PlateEditorOverviewSection(
          icon: Icons.calendar_month_rounded,
          title: '정기 등록',
          value: _regularBillingSummary(),
          enabled: !controller.billingLocked,
          interactionEnabled: false,
          status: _hasRegularBillingSelection
              ? PlateEditorSectionStatus.complete
              : PlateEditorSectionStatus.none,
          onTap: null,
        ),
      PlateEditorOverviewSection(
        icon: statusContextError != null
            ? Icons.warning_amber_rounded
            : Icons.notes_rounded,
        title: '상태 메모',
        enabled: !controller.billingLocked,
        value: statusContextResolving
            ? '상태 정보 확인 중'
            : statusContextError != null
                ? '상태 정보를 확인하지 못했습니다.'
                : memo,
        status: statusContextResolving
            ? PlateEditorSectionStatus.loading
            : statusContextError != null
                ? PlateEditorSectionStatus.error
                : memo.isNotEmpty
                    ? PlateEditorSectionStatus.complete
                    : PlateEditorSectionStatus.none,
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
