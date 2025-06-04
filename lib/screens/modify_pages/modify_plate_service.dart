import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

import '../../states/plate/modify_plate.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/gcs_uploader.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../models/plate_log_model.dart';

class ModifyPlateService {
  final BuildContext context;
  final List<XFile> capturedImages;
  final List<String> existingImageUrls;
  final PlateType collectionKey;
  final PlateModel originalPlate;

  // form controllers
  final TextEditingController controllerFrontdigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final TextEditingController locationController;

  final List<String> selectedStatuses;
  final int selectedBasicStandard;
  final int selectedBasicAmount;
  final int selectedAddStandard;
  final int selectedAddAmount;
  final String? selectedAdjustment;
  final String dropdownValue;

  ModifyPlateService({
    required this.context,
    required this.capturedImages,
    required this.existingImageUrls,
    required this.collectionKey,
    required this.originalPlate,
    required this.controllerFrontdigit,
    required this.controllerMidDigit,
    required this.controllerBackDigit,
    required this.locationController,
    required this.selectedStatuses,
    required this.selectedBasicStandard,
    required this.selectedBasicAmount,
    required this.selectedAddStandard,
    required this.selectedAddAmount,
    required this.selectedAdjustment,
    required this.dropdownValue,
  });

  String composePlateNumber() {
    return '${controllerFrontdigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  Future<List<String>> uploadAndMergeImages(String plateNumber) async {
    final uploader = GCSUploader();
    final uploadedImageUrls = <String>[];
    final failedFiles = <String>[];

    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;
    final user = context.read<UserState>().user;
    final performedBy = user?.name ?? 'Unknown';

    debugPrint('📸 총 업로드 시도 이미지 수: ${capturedImages.length}');

    for (int i = 0; i < capturedImages.length; i++) {
      final image = capturedImages[i];
      final file = File(image.path);

      if (!file.existsSync()) {
        debugPrint('❌ [${i + 1}/${capturedImages.length}] 파일이 존재하지 않음: ${file.path}');
        failedFiles.add(file.path);
        continue;
      }

      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final timeStr = now.millisecondsSinceEpoch.toString();

      final fileName = '${dateStr}_${timeStr}_${plateNumber}_$performedBy.jpg';
      final gcsPath = '$division/$area/images/$fileName';

      String? gcsUrl;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          debugPrint('⬆️ [${i + 1}/${capturedImages.length}] 업로드 시도 #${attempt + 1}: $gcsPath');
          gcsUrl = await uploader.uploadImageFromModify(file, gcsPath);
          if (gcsUrl != null) {
            debugPrint('✅ 업로드 성공: $gcsUrl');
            break;
          }
        } catch (e) {
          debugPrint('❌ [시도 ${attempt + 1}] 업로드 실패 (${file.path}): $e');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (gcsUrl == null) {
        debugPrint('❌ 업로드 최종 실패: ${file.path}');
        failedFiles.add(file.path);
      } else {
        uploadedImageUrls.add(gcsUrl);
      }

      await Future.delayed(const Duration(milliseconds: 100)); // 업로드 간 간격 확보
    }

    if (failedFiles.isNotEmpty) {
      debugPrint('⚠️ 업로드 실패 (${failedFiles.length}/${capturedImages.length})');
      for (final f in failedFiles) {
        debugPrint(' - 실패 파일: $f');
      }
    }

    return [...existingImageUrls, ...uploadedImageUrls];
  }

  Future<bool> updatePlateInfo({
    required String plateNumber,
    required List<String> imageUrls,
    required String newLocation,
    required String? newAdjustmentType,
  }) async {
    final modifyState = context.read<ModifyPlate>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();

    final updatedPlate = originalPlate.copyWith(
      plateNumber: plateNumber,
      location: newLocation,
      adjustmentType: newAdjustmentType,
      statusList: selectedStatuses,
      basicStandard: selectedBasicStandard,
      basicAmount: selectedBasicAmount,
      addStandard: selectedAddStandard,
      addAmount: selectedAddAmount,
      region: dropdownValue,
      imageUrls: imageUrls,
    );

    final changes = originalPlate.diff(updatedPlate);
    if (changes.isNotEmpty) {
      final log = PlateLogModel(
        plateNumber: updatedPlate.plateNumber,
        division: areaState.currentDivision,
        area: areaState.currentArea,
        from: originalPlate.type,
        to: updatedPlate.type,
        action: '정보 수정',
        performedBy: userState.name,
        timestamp: DateTime.now(),
        adjustmentType: updatedPlate.adjustmentType,
        updatedFields: changes,
      );

      await GCSUploader().uploadLogJson(
        log.toMap(),
        updatedPlate.plateNumber,
        log.division,
        log.area,
      );
    }

    return await modifyState.updatePlateInfo(
      context: context,
      plate: originalPlate,
      newPlateNumber: plateNumber,
      location: newLocation,
      areaState: areaState,
      userState: userState,
      collectionKey: collectionKey.name,
      adjustmentType: newAdjustmentType,
      statusList: selectedStatuses,
      basicStandard: selectedBasicStandard,
      basicAmount: selectedBasicAmount,
      addStandard: selectedAddStandard,
      addAmount: selectedAddAmount,
      region: dropdownValue,
      imageUrls: imageUrls,
    );
  }
}
