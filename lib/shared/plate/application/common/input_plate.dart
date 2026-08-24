import 'package:flutter/material.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_status_draft.dart';
import '../../domain/models/plate_status_lookup_result.dart';
import '../../domain/repositories/plate_repository.dart';

class InputPlate with ChangeNotifier {
  final PlateRepository _plateRepository;

  InputPlate(this._plateRepository);

  Future<bool> commonRegisterPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required AreaState areaState,
    required UserState userState,
    required String selectedBillType,
    String? billingType,
    required bool statusWriteRequested,
    required PlateStatusLookupState statusLookupState,
    required bool statusEditedByUser,
    required PlateStatusDraft expectedOriginalStatus,
    String? expectedStatusSourcePath,
    int basicStandard = 0,
    int basicAmount = 0,
    int addStandard = 0,
    int addAmount = 0,
    int? regularAmount,
    int? regularDurationHours,
    required String region,
    List<String>? imageUrls,
    int? lockedFee,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    String? customStatus,
    String? manufacturerName,
    String? modelName,
    String? priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
    String? sectorId,
    String? sectorName,
  }) async {
    final correctedLocation = location.isEmpty ? '미지정' : location;
    final plateType = isLocationSelected
        ? PlateType.parkingCompleted
        : PlateType.parkingRequests;
    debugPrint(
      '[InputPlate][Sector] plate=$plateNumber area=${areaState.currentArea} '
      'sectorId=${(sectorId ?? '').trim()} '
      'sectorName=${(sectorName ?? '').trim()} type=${plateType.firestoreValue}',
    );

    try {
      await _plateRepository.addPlate(
        plateNumber: plateNumber,
        location: correctedLocation,
        area: areaState.currentArea,
        division: areaState.currentDivision,
        userName: userState.name,
        plateType: plateType,
        billingType: billingType,
        statusWriteRequested: statusWriteRequested,
        statusLookupState: statusLookupState,
        statusEditedByUser: statusEditedByUser,
        expectedOriginalStatus: expectedOriginalStatus,
        expectedStatusSourcePath: expectedStatusSourcePath,
        basicStandard: basicStandard,
        basicAmount: basicAmount,
        addStandard: addStandard,
        addAmount: addAmount,
        regularAmount: regularAmount,
        regularDurationHours: regularDurationHours,
        region: region,
        imageUrls: imageUrls,
        isLockedFee: isLockedFee,
        lockedAtTimeInSeconds: lockedAtTimeInSeconds,
        lockedFeeAmount: lockedFeeAmount,
        customStatus: customStatus,
        selectedBillType: selectedBillType,
        manufacturerName: manufacturerName,
        modelName: modelName,
        priority1SlotKey: priority1SlotKey,
        priority2SlotKey: priority2SlotKey,
        priority3SlotKey: priority3SlotKey,
        sectorId: sectorId,
        sectorName: sectorName,
      );

      notifyListeners();
      return true;
    } on PlateStatusConflictException {
      rethrow;
    } on PlateStatusScopeException {
      rethrow;
    } catch (error) {
      if (!context.mounted) return false;
      if (error.toString().contains('이미 등록된 번호판')) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.duplicateActiveEntry,
        );
      } else {
        showFailedSnackbar(context, '오류 발생: $error');
      }
      return false;
    }
  }
}
