import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

import '../models/plate_log_model.dart';
import '../states/plate/log_plate.dart';
import '../states/plate/modify_plate.dart';
import '../states/area/area_state.dart';
import '../states/user/user_state.dart';
import '../utils/gcs_uploader.dart';

class ModifyPlateService {
  final BuildContext context;
  final List<XFile> capturedImages;
  final List<String> existingImageUrls;
  final String collectionKey;
  final dynamic originalPlate;

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

    for (var image in capturedImages) {
      final file = File(image.path);
      final fileName = '${plateNumber}_${DateTime
          .now()
          .millisecondsSinceEpoch}.jpg';
      final gcsUrl = await uploader.uploadImage(file, 'plates/$fileName');

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

    return await modifyState.updatePlateInfo(
      context: context,
      plate: originalPlate,
      newPlateNumber: plateNumber,
      location: newLocation,
      areaState: areaState,
      userState: userState,
      collectionKey: collectionKey,
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

  Future<void> logPlateChange({
    required String plateNumber,
    required String from,
    required String to,
    required String action,
  }) async {
    final area = context
        .read<AreaState>()
        .currentArea;
    final user = context
        .read<UserState>()
        .user;
    final logState = context.read<LogPlateState>();

    final log = PlateLogModel(
      plateNumber: plateNumber,
      area: area,
      from: from,
      to: to,
      action: action,
      performedBy: user?.name ?? 'Unknown',
      timestamp: DateTime.now(),
    );

    await logState.saveLog(log);
  }
}
