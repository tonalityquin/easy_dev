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
  final TextEditingController controller3digit;
  final TextEditingController controller1digit;
  final TextEditingController controller4digit;
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
    required this.controller3digit,
    required this.controller1digit,
    required this.controller4digit,
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
    return '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
  }

  Future<List<String>> uploadAndMergeImages(String plateNumber) async {
    final uploader = GCSUploader();
    final uploadedImageUrls = <String>[];
    final area = context.read<AreaState>().currentArea;
    final user = context.read<UserState>().user;

    final performedBy = user?.name ?? 'Unknown';

    for (var image in capturedImages) {
      final file = File(image.path);
      final now = DateTime.now();
      final formattedDate =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final fileName = '${formattedDate}_${area}_${plateNumber}_$performedBy.jpg';
      final gcsUrl = await uploader.uploadImageFromModify(file, 'plates/$fileName');

      if (gcsUrl != null) {
        debugPrint('✅ 이미지 업로드 완료: $gcsUrl');
        uploadedImageUrls.add(gcsUrl);
      } else {
        debugPrint('❌ 이미지 업로드 실패: ${file.path}');
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

    // ✅ 수정된 Plate 인스턴스 생성
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

    // ✅ 변경 사항 비교 및 로그 저장
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
        updatedFields: changes, // ✅ 반드시 포함
      );

      await GCSUploader().uploadLogJson(
        log.toMap(),
        updatedPlate.plateNumber,
        log.division,
        log.area,
      );
    }

    // ✅ 실제 저장
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
