import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';

import '../../models/plate_model.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../states/plate/modify_plate.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/gcs_image_uploader.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_log_model.dart';

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

  Future<bool> updatePlateInfo({
    required String plateNumber,
    required List<String> imageUrls,
    required String newLocation,
    required String? newBillingType,
  }) async {
    final modifyState = context.read<ModifyPlate>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();

    final updatedPlate = originalPlate.copyWith(
      plateNumber: plateNumber,
      location: newLocation,
      billingType: newBillingType,
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
        billingType: updatedPlate.billingType,
        updatedFields: changes,
      );

      await context.read<PlateRepository>().updatePlate(
        '${originalPlate.plateNumber}_${originalPlate.area}',
        {
          if (originalPlate.location != newLocation) 'location': newLocation,
          if (originalPlate.billingType != newBillingType) 'billingType': newBillingType,
          if (originalPlate.plateNumber != plateNumber) 'plate_number': plateNumber,
          'updatedAt': Timestamp.now(),
        },
        log: log,
      );
    }

    return await modifyState.modifyPlateInfo(
      context: context,
      plate: originalPlate,
      newPlateNumber: plateNumber,
      location: newLocation,
      areaState: areaState,
      userState: userState,
      collectionKey: collectionKey.name,
      billingType: newBillingType,
      statusList: selectedStatuses,
      basicStandard: selectedBasicStandard,
      basicAmount: selectedBasicAmount,
      addStandard: selectedAddStandard,
      addAmount: selectedAddAmount,
      region: dropdownValue,
      imageUrls: imageUrls,
    );
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
