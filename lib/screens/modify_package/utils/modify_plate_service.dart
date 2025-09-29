// lib/screens/modify_package/utils/modify_plate_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';

import '../../../models/plate_model.dart';
import '../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/gcs_image_uploader.dart';
import '../../../enums/plate_type.dart';
import '../../../models/plate_log_model.dart';

class ModifyPlateService {
  final BuildContext context;
  final List<XFile> capturedImages;
  final List<String> existingImageUrls;
  final PlateType collectionKey;
  final PlateModel originalPlate;

  final TextEditingController controllerFrontdigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final TextEditingController locationController;

  final List<String> selectedStatuses;
  final int selectedBasicStandard;
  final int selectedBasicAmount;
  final int selectedAddStandard;
  final int selectedAddAmount;
  final int selectedRegularAmount;
  final int selectedRegularDurationHours;

  final String? selectedBill;
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
    required this.selectedBill,
    required this.dropdownValue,
    required this.selectedRegularAmount,
    required this.selectedRegularDurationHours,
  });

  String composePlateNumber() {
    return '${controllerFrontdigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  Future<List<String>> uploadAndMergeImages(String plateNumber) async {
    final uploader = GcsImageUploader();
    final uploadedImageUrls = <String>[];
    final failedFiles = <String>[];

    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;
    final user = context.read<UserState>().user;
    final performedBy = user?.name ?? 'Unknown';

    for (int i = 0; i < capturedImages.length; i++) {
      final image = capturedImages[i];
      final file = File(image.path);
      if (!file.existsSync()) {
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
          gcsUrl = await uploader.modifyUploadImage(file, gcsPath);
          if (gcsUrl != null) break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (gcsUrl != null) {
        uploadedImageUrls.add(gcsUrl);
      } else {
        failedFiles.add(file.path);
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    return [...existingImageUrls, ...uploadedImageUrls];
  }

  /// 🔧 리팩터링 포인트:
  /// - 여기서 **한 번의 repo.updatePlate**로 모든 변경을 반영 (사전조회 + write 1)
  /// - 컨트롤러의 직접 plates.update 제거, ModifyPlate.modifyPlateInfo 호출 제거
  Future<bool> updatePlateInfo({
    required String plateNumber,
    required List<String> imageUrls,
    required String newLocation,
    required String? newBillingType,
    required String updatedCustomStatus,
    required List<String> updatedStatusList,
  }) async {
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    final repo = context.read<PlateRepository>();

    // 최종 문서 필드 기준으로 갱신본 구성
    final updatedPlate = originalPlate.copyWith(
      plateNumber: plateNumber,
      location: newLocation,
      billingType: newBillingType,
      statusList: updatedStatusList,
      basicStandard: selectedBasicStandard,
      basicAmount: selectedBasicAmount,
      addStandard: selectedAddStandard,
      addAmount: selectedAddAmount,
      region: dropdownValue,
      imageUrls: imageUrls,
      customStatus: updatedCustomStatus,
      regularAmount: selectedRegularAmount,
      regularDurationHours: selectedRegularDurationHours,
    );

    // 변경점 계산 (로그용)
    final changes = originalPlate.diff(updatedPlate);

    // 로그 생성(있을 때만)
    PlateLogModel? log;
    if (changes.isNotEmpty) {
      log = PlateLogModel(
        plateNumber: updatedPlate.plateNumber,
        type: updatedPlate.type,
        area: areaState.currentArea,
        from: originalPlate.type,
        to: updatedPlate.type,
        action: '정보 수정',
        performedBy: userState.name,
        timestamp: DateTime.now(),
        billingType: updatedPlate.billingType,
        updatedFields: changes,
      );
    }

    // 한 번의 update로 모든 필드 반영 (PlateWriteService.updatePlate 내부에서 prefetch READ 1 + WRITE 1 + 계측)
    await repo.updatePlate(
      '${originalPlate.plateNumber}_${originalPlate.area}', // 문서 ID는 기존 유지
      <String, dynamic>{
        if (originalPlate.location != newLocation) 'location': newLocation,
        if (originalPlate.billingType != newBillingType) 'billingType': newBillingType,
        if (originalPlate.plateNumber != plateNumber) 'plate_number': plateNumber,

        // 상태/커스텀 상태도 여기서 동시 반영 → 컨트롤러의 직접 update 제거
        'statusList': updatedStatusList,
        'customStatus': updatedCustomStatus,

        // 이미지 및 요금 필드 모두 포함
        'imageUrls': imageUrls,
        'region': dropdownValue,
        'basicStandard': selectedBasicStandard,
        'basicAmount': selectedBasicAmount,
        'addStandard': selectedAddStandard,
        'addAmount': selectedAddAmount,
        'regularAmount': selectedRegularAmount,
        'regularDurationHours': selectedRegularDurationHours,

        // ✅ 수정 직후 선택 해제 (추가 클릭 불필요)
        'isSelected': false,
        'selectedBy': null,

        'updatedAt': Timestamp.now(),
      },
      log: log,
    );

    return true;
  }

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
