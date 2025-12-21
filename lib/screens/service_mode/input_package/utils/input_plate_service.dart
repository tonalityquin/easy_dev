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

class InputPlateService {
  // ─────────────────────────────────────────
  // 날짜/경로 유틸 (UTC 기준 통일 + 월 폴더 분리)
  // ─────────────────────────────────────────
  static String _twoDigits(int v) => v.toString().padLeft(2, '0');

  /// yyyy-MM-dd (UTC)
  static String _buildDateStrUtc(DateTime nowUtc) {
    return '${nowUtc.year.toString().padLeft(4, '0')}-${_twoDigits(nowUtc.month)}-${_twoDigits(nowUtc.day)}';
  }

  /// yyyy-MM (UTC)
  static String _buildMonthStrUtc(DateTime nowUtc) {
    return '${nowUtc.year.toString().padLeft(4, '0')}-${_twoDigits(nowUtc.month)}';
  }

  static String _buildFileNameUtc({
    required DateTime nowUtc,
    required String plateNumber,
    required String userName,
  }) {
    final dateStr = _buildDateStrUtc(nowUtc);
    final timeStr = nowUtc.millisecondsSinceEpoch.toString();
    return '${dateStr}_${timeStr}_${plateNumber}_$userName.jpg';
  }

  /// ✅ 변경된 업로드 경로 규칙:
  ///   $division/$area/images/$yyyyMM/$fileName
  static String _buildGcsPathUtc({
    required String division,
    required String area,
    required DateTime nowUtc,
    required String fileName,
  }) {
    final monthStr = _buildMonthStrUtc(nowUtc);
    return '$division/$area/images/$monthStr/$fileName';
  }

  static String _sanitizeYearMonth(String raw) {
    final ym = raw.trim();
    final ok = RegExp(r'^\d{4}-\d{2}$').hasMatch(ym);
    if (!ok) {
      throw ArgumentError('yearMonth must be in yyyy-MM format. got="$raw"');
    }
    return ym;
  }

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

      // ✅ 로컬 시간 대신 UTC로 통일
      final nowUtc = DateTime.now().toUtc();

      final fileName = _buildFileNameUtc(
        nowUtc: nowUtc,
        plateNumber: plateNumber,
        userName: userName,
      );

      // ✅ images 하위에 yyyy-MM 월 폴더 1단계 추가
      final gcsPath = _buildGcsPathUtc(
        division: division,
        area: area,
        nowUtc: nowUtc,
        fileName: fileName,
      );

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
  // GCS 목록 조회 (중앙 세션 사용) + 월 단위 조회 옵션
  // ─────────────────────────────────────────
  static Future<gcs.StorageApi> _storage() async {
    final client = await GoogleAuthSession.instance.safeClient();
    return gcs.StorageApi(client);
  }

  /// ✅ 중앙 OAuth로 GCS 객체 목록 조회
  ///
  /// ✅ yearMonth(yyyy-MM) 옵션:
  /// - yearMonth 지정 시: images/yyyy-MM/ prefix만 list
  /// - 미지정 시: images/ prefix 전체 list (기존 호환)
  static Future<List<String>> listPlateImages({
    required BuildContext context,
    required String plateNumber,
    String? yearMonth, // ✅ 추가
  }) async {
    const bucketName = 'easydev-image';
    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;

    final storage = await _storage();

    final String prefix;
    if (yearMonth != null && yearMonth.trim().isNotEmpty) {
      final ym = _sanitizeYearMonth(yearMonth);
      prefix = '$division/$area/images/$ym/';
    } else {
      prefix = '$division/$area/images/';
    }

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
