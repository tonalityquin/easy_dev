import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

// GCS
import 'package:googleapis/storage/v1.dart' as gcs;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

// OAuth (google_sign_in v7 + extension)
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../../../models/plate_model.dart';
import '../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/gcs_image_uploader.dart';
import '../../../enums/plate_type.dart';
import '../../../models/plate_log_model.dart';

/// ✅ GSI v7: 웹 애플리케이션 클라이언트 ID
const String _kWebClientId =
    '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

class _OAuthHelper {
  static bool _inited = false;

  static Future<void> _ensureInit() async {
    if (_inited) return;
    try {
      await GoogleSignIn.instance.initialize(serverClientId: _kWebClientId);
    } catch (_) {}
    _inited = true;
  }

  static Future<GoogleSignInAccount> _waitForSignIn() async {
    final signIn = GoogleSignIn.instance;
    final c = Completer<GoogleSignInAccount>();
    late final StreamSubscription sub;
    sub = signIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          if (!c.isCompleted) c.complete(event.user);
        case GoogleSignInAuthenticationEventSignOut():
          break;
      }
    }, onError: (e) {
      if (!c.isCompleted) c.completeError(e);
    });

    try {
      try {
        await signIn.attemptLightweightAuthentication();
      } catch (_) {}
      if (signIn.supportsAuthenticate()) {
        await signIn.authenticate();
      }
      return await c.future
          .timeout(const Duration(seconds: 90), onTimeout: () => throw Exception('Google 로그인 응답 시간 초과'));
    } finally {
      await sub.cancel();
    }
  }

  /// GCS 읽기 전용 클라이언트
  static Future<auth.AuthClient> gcsReadonlyClient() async {
    await _ensureInit();
    const scopes = [gcs.StorageApi.devstorageReadOnlyScope];
    final user = await _waitForSignIn();

    var authorization =
    await user.authorizationClient.authorizationForScopes(scopes);
    authorization ??= await user.authorizationClient.authorizeScopes(scopes);

    return authorization.authClient(scopes: scopes);
  }
}

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
          // NOTE: GcsImageUploader가 OAuth 사용한다고 가정
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

  /// 🔧 여기서 repo.updatePlate 한 번으로 모든 변경 반영
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

  /// ✅ 서비스계정 제거 → OAuth로 GCS 객체 목록 조회
  static Future<List<String>> listPlateImages({
    required BuildContext context,
    required String plateNumber,
  }) async {
    const bucketName = 'easydev-image';
    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;

    auth.AuthClient? client;
    try {
      client = await _OAuthHelper.gcsReadonlyClient();
      final storage = gcs.StorageApi(client);

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
    } finally {
      client?.close();
    }
  }
}
