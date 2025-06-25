import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';

import '../../utils/gcs_uploader.dart';
import '../../states/plate/input_plate.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';

class InputPlateService {
  static Future<List<String>> uploadCapturedImages(List<XFile> images,
      String plateNumber,
      String area,
      String userName,
      String division,) async {
    final uploader = GCSUploader();
    final List<String> uploadedUrls = [];
    final List<String> failedFiles = [];

    debugPrint('📸 총 업로드 시도 이미지 수: ${images.length}');

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final file = File(image.path);

      if (!file.existsSync()) {
        debugPrint('❌ [${i + 1}/${images.length}] 파일이 존재하지 않음: ${file.path}');
        failedFiles.add(file.path);
        continue;
      }

      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final timeStr = now.millisecondsSinceEpoch.toString();
      final fileName = '${dateStr}_${timeStr}_${plateNumber}_$userName.jpg';
      final gcsPath = '$division/$area/images/$fileName';

      String? gcsUrl;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          debugPrint('⬆️ [${i + 1}/${images.length}] 업로드 시도 #${attempt + 1}: $gcsPath');
          gcsUrl = await uploader.inputUploadImage(file, gcsPath);
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
        uploadedUrls.add(gcsUrl);
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (failedFiles.isNotEmpty) {
      debugPrint('⚠️ 업로드 실패 (${failedFiles.length}/${images.length})');
      for (final f in failedFiles) {
        debugPrint(' - 실패 파일: $f');
      }
    }

    return uploadedUrls;
  }

  static Future<bool> saveInputPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required List<String> imageUrls,
    required String? selectedBill,
    required List<String> selectedStatuses,
    required int basicStandard,
    required int basicAmount,
    required int addStandard,
    required int addAmount,
    required String region,
    String? customStatus,
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
      billingType: selectedBill,
      statusList: selectedStatuses,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
      region: region,
      imageUrls: imageUrls,
      customStatus: customStatus,
    );
  }

  /// ✅ GCS에 저장된 동일 번호판 이미지 목록 가져오기
  static Future<List<String>> listPlateImages({
    required BuildContext context,
    required String plateNumber,
  }) async {
    final bucketName = 'easydev-image';
    final serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';
    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;

    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageReadOnlyScope]);
    final storage = StorageApi(client);

    final prefix = '$division/$area/images/';
    final objects = await storage.objects.list(bucketName, prefix: prefix);

    final urls = <String>[];

    for (final obj in objects.items ?? []) {
      final name = obj.name;
      if (name != null && name.endsWith('.jpg') && name.contains(plateNumber)) {
        urls.add('https://storage.googleapis.com/$bucketName/$name');
      }
    }

    client.close();
    return urls;
  }
}
