import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

// GCS
import 'package:googleapis/storage/v1.dart' as gcs;

// ✅ 중앙 OAuth 세션만 사용
import 'package:easydev/utils/google_auth_session.dart';

import '../../../models/plate_model.dart';
import '../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/gcs/gcs_image_uploader.dart';
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
      final dateStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = now.millisecondsSinceEpoch.toString();
      final fileName = '${dateStr}_${timeStr}_${plateNumber}_$performedBy.jpg';
      final gcsPath = '$division/$area/images/$fileName';

      String? gcsUrl;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          // NOTE: GcsImageUploader가 중앙 OAuth 세션 사용
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

  /// 🔧 repo.updatePlate 한 번으로 변경 반영
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

    final changes = originalPlate.diff(updatedPlate);

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

    await repo.updatePlate(
      '${originalPlate.plateNumber}_${originalPlate.area}', // 기존 문서 ID 유지
      <String, dynamic>{
        if (originalPlate.location != newLocation) 'location': newLocation,
        if (originalPlate.billingType != newBillingType) 'billingType': newBillingType,
        if (originalPlate.plateNumber != plateNumber) 'plate_number': plateNumber,
        'statusList': updatedStatusList,
        'customStatus': updatedCustomStatus,
        'imageUrls': imageUrls,
        'region': dropdownValue,
        'basicStandard': selectedBasicStandard,
        'basicAmount': selectedBasicAmount,
        'addStandard': selectedAddStandard,
        'addAmount': selectedAddAmount,
        'regularAmount': selectedRegularAmount,
        'regularDurationHours': selectedRegularDurationHours,
        'isSelected': false,
        'selectedBy': null,
        'updatedAt': Timestamp.now(),
      },
      log: log,
    );

    return true;
  }

  // ─────────────────────────────────────────
  // GCS 목록 조회 (중앙 세션 사용)
  // ─────────────────────────────────────────
  static Future<gcs.StorageApi> _storage() async {
    final client = await GoogleAuthSession.instance.safeClient();
    return gcs.StorageApi(client);
  }

  /// ✅ 서비스계정/개별 OAuth 제거 → 중앙 OAuth로 GCS 객체 목록 조회
  static Future<List<String>> listPlateImages({
    required BuildContext context,
    required String plateNumber,
  }) async {
    const bucketName = 'easydev-image';
    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;

    final storage = await _storage();
    final prefix = '$division/$area/images/';
    final urls = <String>[];

    String? pageToken;
    do {
      final res = await storage.objects.list(
        bucketName,
        prefix: prefix,
        pageToken: pageToken,
      );
      final items = res.items ?? const <gcs.Object>[];
      for (final obj in items) {
        final name = obj.name;
        if (name != null && name.endsWith('.jpg') && name.contains(plateNumber)) {
          urls.add('https://storage.googleapis.com/$bucketName/$name');
        }
      }
      pageToken = res.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    return urls;
  }
}
