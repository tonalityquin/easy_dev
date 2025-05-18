import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/gcs_uploader.dart';
import '../../states/plate/input_plate.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import 'package:camera/camera.dart';

class InputPlateService {
  static Future<List<String>> uploadCapturedImages(
    List<XFile> images,
    String plateNumber,
    String area,
    String userName,
  ) async {
    final uploader = GCSUploader();
    final List<String> uploadedUrls = [];

    for (var image in images) {
      final file = File(image.path);
      final now = DateTime.now();
      final formattedDate =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final fileName = '${formattedDate}_${area}_${plateNumber}_$userName.jpg';

      final gcsUrl = await uploader.uploadImageFromInput(file, 'plates/$fileName');

      if (gcsUrl == null) {
        debugPrint('이미지 업로드 실패 (파일 경로: ${file.path})');
        throw Exception('이미지 업로드에 실패했습니다. 다시 시도해주세요.');
      }

      uploadedUrls.add(gcsUrl);
    }

    return uploadedUrls;
  }

  static Future<bool> saveInputPlateEntry({
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

    return await inputState.handlePlateEntry(
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
