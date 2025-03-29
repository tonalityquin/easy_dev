import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/gcs_uploader.dart';
import '../states/plate/input_plate.dart';
import '../states/area/area_state.dart';
import '../states/user/user_state.dart';
import 'package:camera/camera.dart';

class InputPlateService {
  /// 이미지 업로드
  static Future<List<String>> uploadCapturedImages(
      List<XFile> images,
      String plateNumber,
      ) async {
    final uploader = GCSUploader();
    final List<String> uploadedUrls = [];

    for (var image in images) {
      final file = File(image.path);
      final fileName = '${plateNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final gcsUrl = await uploader.uploadImage(file, 'plates/$fileName');

      if (gcsUrl != null) {
        debugPrint('✅ 이미지 업로드 완료: $gcsUrl');
        uploadedUrls.add(gcsUrl);
      } else {
        debugPrint('❌ 이미지 업로드 실패: ${file.path}');
      }
    }

    return uploadedUrls;
  }

  /// plate 저장 처리
  static Future<void> savePlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required List<String> imageUrls,
    required String? selectedAdjustment,
    required List<String> selectedStatuses,
    required int basicStandard,
    required int basicAmount,
    required int addStandard,
    required int addAmount,
    required String region,
  }) async {
    final inputState = context.read<InputPlate>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();

    await inputState.handlePlateEntry(
      context: context,
      plateNumber: plateNumber,
      location: location,
      isLocationSelected: isLocationSelected,
      areaState: areaState,
      userState: userState,
      adjustmentType: selectedAdjustment,
      statusList: selectedStatuses,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
      region: region,
      imageUrls: imageUrls,
    );
  }
}
