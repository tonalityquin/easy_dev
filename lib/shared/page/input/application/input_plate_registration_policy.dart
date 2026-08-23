import '../../../../features/payment/applications/bill_state.dart';
import '../../../plate/editor/domain/plate_editor_workspace.dart';
import '../controllers/input_plate_controller.dart';

class InputPlateRegistrationPolicy {
  const InputPlateRegistrationPolicy({
    required this.identityComplete,
    required this.parkingRequired,
    required this.parkingComplete,
    required this.billingRequired,
    required this.billingComplete,
    required this.sectorRequired,
    required this.sectorComplete,
    required this.statusReady,
  });

  final bool identityComplete;
  final bool parkingRequired;
  final bool parkingComplete;
  final bool billingRequired;
  final bool billingComplete;
  final bool sectorRequired;
  final bool sectorComplete;
  final bool statusReady;

  factory InputPlateRegistrationPolicy.resolve({
    required InputPlateController controller,
    required PlateEditorPolicy editorPolicy,
    required BillState billState,
  }) {
    final hasAnyBill =
        billState.generalBills.isNotEmpty || billState.regularBills.isNotEmpty;
    final billingRequired = editorPolicy.hasBill && hasAnyBill;
    final monthlyValue = controller.countTypeController.text.trim();
    final selectedBill = controller.selectedBill?.trim() ?? '';
    final billingComplete = !billingRequired ||
        (controller.selectedBillType == '정기'
            ? selectedBill.isNotEmpty || monthlyValue.isNotEmpty
            : selectedBill.isNotEmpty);
    final sectorRequired = editorPolicy.hasSector;
    return InputPlateRegistrationPolicy(
      identityComplete: controller.isInputValid(),
      parkingRequired: !controller.isMinorMode,
      parkingComplete: controller.isMinorMode ||
          controller.locationController.text.trim().isNotEmpty,
      billingRequired: billingRequired,
      billingComplete: billingComplete,
      sectorRequired: sectorRequired,
      sectorComplete: !sectorRequired ||
          ((controller.selectedSectorId?.trim().isNotEmpty ?? false) &&
              (controller.selectedSectorName?.trim().isNotEmpty ?? false)),
      statusReady: controller.statusLookupReadyForSubmit,
    );
  }

  int get requiredCount {
    var count = 1;
    if (parkingRequired) count++;
    if (billingRequired) count++;
    if (sectorRequired) count++;
    return count;
  }

  int get completedCount {
    var count = 0;
    if (identityComplete && statusReady) count++;
    if (parkingRequired && parkingComplete) count++;
    if (billingRequired && billingComplete) count++;
    if (sectorRequired && sectorComplete) count++;
    return count;
  }

  bool get canSubmit =>
      identityComplete &&
      statusReady &&
      parkingComplete &&
      billingComplete &&
      sectorComplete;
}
