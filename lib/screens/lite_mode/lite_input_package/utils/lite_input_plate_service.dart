// lib/screens/input_package/utils/input_plate_service.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

// GCS
import 'package:googleapis/storage/v1.dart' as gcs;

// ✅ 중앙 OAuth 세션만 사용 (최초 1회 로그인 후 재사용)
import '../../../../utils/google_auth_session.dart';

import '../../../../utils/gcs/gcs_image_uploader.dart';
import '../../../../states/plate/input_plate.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';

class LiteInputPlateService {
  static Future<List<String>> uploadCapturedImages(
      List<XFile> images,
      String plateNumber,
      String area,
      String userName,
      String division,
      ) async {
    final uploader = GcsImageUploader();
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
      final dateStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = now.millisecondsSinceEpoch.toString();
      final fileName = '${dateStr}_${timeStr}_${plateNumber}_$userName.jpg';
      final gcsPath = '$division/$area/images/$fileName';

      String? gcsUrl;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          debugPrint('⬆️ [${i + 1}/${images.length}] 업로드 시도 #${attempt + 1}: $gcsPath');
          // NOTE: GcsImageUploader 내부가 OAuth(중앙 세션) 사용하도록 리팩터링되어 있다고 가정
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

  static Future<bool> registerPlateEntry({
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
    required String selectedBillType,
  }) async {
    final inputState = context.read<InputPlate>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();

    int finalBasicStandard = basicStandard;
    int finalBasicAmount = basicAmount;
    int finalAddStandard = addStandard;
    int finalAddAmount = addAmount;

    if (selectedBillType == '정기') {
      finalBasicStandard = 0;
      finalBasicAmount = 0;
      finalAddStandard = 0;
      finalAddAmount = 0;
    }

    return await inputState.registerPlateEntry(
      context: context,
      plateNumber: plateNumber,
      location: location,
      isLocationSelected: isLocationSelected,
      areaState: areaState,
      userState: userState,
      billingType: selectedBill,
      statusList: selectedStatuses,
      basicStandard: finalBasicStandard,
      basicAmount: finalBasicAmount,
      addStandard: finalAddStandard,
      addAmount: finalAddAmount,
      region: region,
      imageUrls: imageUrls,
      customStatus: customStatus ?? '',
      selectedBillType: selectedBillType,
    );
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
    final division = context.read<AreaState>().currentDivision; // ← ✅ 여기 오탈자 수정

    final storage = await _storage();
    final prefix = '$division/$area/images/';
    final urls = <String>[];

    // 페이지네이션 대응
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
