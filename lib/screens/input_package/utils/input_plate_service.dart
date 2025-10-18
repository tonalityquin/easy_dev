import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

// GCS
import 'package:googleapis/storage/v1.dart' as gcs;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

// OAuth (google_sign_in v7 + extension)
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../../../utils/gcs_image_uploader.dart';
import '../../../states/plate/input_plate.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';

/// ✅ GSI v7: 웹 애플리케이션 클라이언트 ID (Android에선 serverClientId로 사용)
const String _kWebClientId =
    '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com';

class _OAuthHelper {
  static bool _inited = false;

  static Future<void> _ensureInit() async {
    if (_inited) return;
    try {
      // 28444 방지: Android는 반드시 serverClientId 지정
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
        await signIn.authenticate(); // 필요 시 UI
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

class InputPlateService {
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
          // NOTE: GcsImageUploader가 내부에서 OAuth를 사용하도록 이미 리팩터링되어 있다고 가정
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
    } finally {
      client?.close();
    }
  }
}
