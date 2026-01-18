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

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

import '../../../../models/plate_model.dart';
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/gcs/gcs_image_uploader.dart';
import '../../../../enums/plate_type.dart';
import '../../../../models/plate_log_model.dart';

class MinorModifyPlateService {
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

  MinorModifyPlateService({
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

  // ─────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────
  static const String _tPlate = 'plate';
  static const String _tPlateMinor = 'plate/minor';
  static const String _tPlateModify = 'plate/modify';
  static const String _tPlateUpload = 'plate/upload';
  static const String _tPlateRepo = 'plate/repo';
  static const String _tGcs = 'gcs';
  static const String _tGcsList = 'gcs/list';
  static const String _tAuth = 'google/auth';

  static const Duration _uploadRetryDelay = Duration(milliseconds: 500);
  static const int _uploadMaxAttempts = 3;

  static Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {
      // 로깅 실패는 기능에 영향 없도록 무시
    }
  }

  static Map<String, dynamic> _ctxBasic({
    String? plateNumber,
    String? area,
    String? division,
    String? performedBy,
    String? filePath,
    String? gcsPath,
    String? yearMonth,
    int? index,
    int? total,
    int? attempt,
    int? existingUrls,
    int? uploadedUrls,
  }) {
    return <String, dynamic>{
      if (plateNumber != null) 'plateNumber': plateNumber,
      if (area != null) 'area': area,
      if (division != null) 'division': division,
      if (performedBy != null) 'performedByLen': performedBy.trim().length,
      if (filePath != null) 'filePath': filePath,
      if (gcsPath != null) 'gcsPath': gcsPath,
      if (yearMonth != null) 'yearMonth': yearMonth,
      if (index != null) 'index': index,
      if (total != null) 'total': total,
      if (attempt != null) 'attempt': attempt,
      if (existingUrls != null) 'existingUrls': existingUrls,
      if (uploadedUrls != null) 'uploadedUrls': uploadedUrls,
    };
  }

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
    required String performedBy,
  }) {
    final dateStr = _buildDateStrUtc(nowUtc);
    final timeStr = nowUtc.millisecondsSinceEpoch.toString();
    return '${dateStr}_${timeStr}_${plateNumber}_$performedBy.jpg';
  }

  /// ✅ 변경된 업로드 경로 규칙:
  ///   $division/$area/images/$yyyy-MM/$fileName
  static String _buildGcsPathUtc({
    required String division,
    required String area,
    required DateTime nowUtc,
    required String fileName,
  }) {
    final monthStr = _buildMonthStrUtc(nowUtc);
    return '$division/$area/images/$monthStr/$fileName';
  }

  String composePlateNumber() {
    return '${controllerFrontdigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  // ─────────────────────────────────────────
  // ✅ 이미지 업로드 + merge: 디버그 로깅 + 재시도 + 월 폴더 규칙
  // ─────────────────────────────────────────
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

        await _logApiError(
          tag: 'MinorModifyPlateService.uploadAndMergeImages',
          message: '업로드 대상 파일이 존재하지 않음',
          error: Exception('file_not_found'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            performedBy: performedBy,
            filePath: file.path,
            index: i + 1,
            total: capturedImages.length,
          ),
          tags: const <String>[_tPlate, _tPlateMinor, _tPlateModify, _tPlateUpload],
        );
        continue;
      }

      final nowUtc = DateTime.now().toUtc();

      final fileName = _buildFileNameUtc(
        nowUtc: nowUtc,
        plateNumber: plateNumber,
        performedBy: performedBy,
      );

      final gcsPath = _buildGcsPathUtc(
        division: division,
        area: area,
        nowUtc: nowUtc,
        fileName: fileName,
      );

      String? gcsUrl;
      for (int attempt = 0; attempt < _uploadMaxAttempts; attempt++) {
        try {
          // NOTE: GcsImageUploader가 중앙 OAuth 세션 사용
          gcsUrl = await uploader.modifyUploadImage(file, gcsPath);
          if (gcsUrl != null) break;

          await _logApiError(
            tag: 'MinorModifyPlateService.uploadAndMergeImages',
            message: 'GCS 업로드 결과가 null',
            error: Exception('upload_returned_null'),
            extra: _ctxBasic(
              plateNumber: plateNumber,
              area: area,
              division: division,
              performedBy: performedBy,
              filePath: file.path,
              gcsPath: gcsPath,
              index: i + 1,
              total: capturedImages.length,
              attempt: attempt + 1,
            ),
            tags: const <String>[_tPlate, _tPlateMinor, _tPlateModify, _tPlateUpload, _tGcs],
          );
        } catch (e) {
          await _logApiError(
            tag: 'MinorModifyPlateService.uploadAndMergeImages',
            message: 'GCS 업로드 예외',
            error: e,
            extra: _ctxBasic(
              plateNumber: plateNumber,
              area: area,
              division: division,
              performedBy: performedBy,
              filePath: file.path,
              gcsPath: gcsPath,
              index: i + 1,
              total: capturedImages.length,
              attempt: attempt + 1,
            ),
            tags: const <String>[_tPlate, _tPlateMinor, _tPlateModify, _tPlateUpload, _tGcs],
          );

          await Future.delayed(_uploadRetryDelay);
        }
      }

      if (gcsUrl != null) {
        uploadedImageUrls.add(gcsUrl);
      } else {
        failedFiles.add(file.path);

        await _logApiError(
          tag: 'MinorModifyPlateService.uploadAndMergeImages',
          message: 'GCS 업로드 최종 실패(재시도 소진)',
          error: Exception('upload_failed_final'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            performedBy: performedBy,
            filePath: file.path,
            gcsPath: gcsPath,
            index: i + 1,
            total: capturedImages.length,
          ),
          tags: const <String>[_tPlate, _tPlateMinor, _tPlateModify, _tPlateUpload, _tGcs],
        );
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 실패 파일이 있어도 merge는 수행(기존 정책 유지)
    if (failedFiles.isNotEmpty) {
      await _logApiError(
        tag: 'MinorModifyPlateService.uploadAndMergeImages',
        message: '일부 이미지 업로드 실패',
        error: Exception('partial_upload_failed'),
        extra: _ctxBasic(
          plateNumber: plateNumber,
          area: area,
          division: division,
          performedBy: performedBy,
          existingUrls: existingImageUrls.length,
          uploadedUrls: uploadedImageUrls.length,
        ),
        tags: const <String>[_tPlate, _tPlateMinor, _tPlateModify, _tPlateUpload],
      );
    }

    return <String>[...existingImageUrls, ...uploadedImageUrls];
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
        timestamp: DateTime.now().toUtc(),
        billingType: updatedPlate.billingType,
        updatedFields: changes,
      );
    }

    try {
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
    } catch (e) {
      await _logApiError(
        tag: 'MinorModifyPlateService.updatePlateInfo',
        message: 'PlateRepository.updatePlate 실패',
        error: e,
        extra: <String, dynamic>{
          'docId': '${originalPlate.plateNumber}_${originalPlate.area}',
          'area': areaState.currentArea,
          'division': areaState.currentDivision,
          'performedByLen': userState.name.trim().length,
          'originalPlateNumber': originalPlate.plateNumber,
          'newPlateNumber': plateNumber,
          'imageUrlsCount': imageUrls.length,
          'statusCount': updatedStatusList.length,
          'hasLog': log != null,
          'changedFieldsCount': changes.length,
        },
        tags: const <String>[_tPlate, _tPlateMinor, _tPlateModify, _tPlateRepo],
      );
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // GCS 목록 조회 (중앙 세션 사용) + 월 단위 조회 옵션 + 디버그 로깅
  // ─────────────────────────────────────────
  static Future<gcs.StorageApi> _storage() async {
    try {
      final client = await GoogleAuthSession.instance.safeClient();
      return gcs.StorageApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'MinorModifyPlateService._storage',
        message: 'GoogleAuthSession.safeClient 또는 StorageApi 생성 실패',
        error: e,
        tags: const <String>[_tGcs, _tAuth],
      );
      rethrow;
    }
  }

  static String _sanitizeYearMonth(String raw) {
    final ym = raw.trim();
    final ok = RegExp(r'^\d{4}-\d{2}$').hasMatch(ym);
    if (!ok) {
      throw ArgumentError('yearMonth must be in yyyy-MM format. got="$raw"');
    }
    return ym;
  }

  /// ✅ 서비스계정/개별 OAuth 제거 → 중앙 OAuth로 GCS 객체 목록 조회
  ///
  /// ✅ yearMonth(yyyy-MM) 옵션 추가:
  /// - yearMonth가 주어지면: prefix = '$division/$area/images/$yearMonth/' 로 월 단위만 조회
  /// - yearMonth가 없으면: prefix = '$division/$area/images/' 로 전체(모든 월) 조회 (호환성 유지)
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
    try {
      if (yearMonth != null && yearMonth.trim().isNotEmpty) {
        final ym = _sanitizeYearMonth(yearMonth);
        prefix = '$division/$area/images/$ym/';
      } else {
        prefix = '$division/$area/images/';
      }
    } catch (e) {
      await _logApiError(
        tag: 'MinorModifyPlateService.listPlateImages',
        message: 'yearMonth 파라미터 검증 실패',
        error: e,
        extra: _ctxBasic(
          plateNumber: plateNumber,
          area: area,
          division: division,
          yearMonth: yearMonth,
        ),
        tags: const <String>[_tPlate, _tPlateMinor, _tGcsList],
      );
      rethrow;
    }

    final urls = <String>[];

    String? pageToken;
    try {
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
    } catch (e) {
      await _logApiError(
        tag: 'MinorModifyPlateService.listPlateImages',
        message: 'GCS objects.list 실패',
        error: e,
        extra: <String, dynamic>{
          'bucket': bucketName,
          'prefix': prefix,
          'plateNumber': plateNumber,
          'found': urls.length,
        },
        tags: const <String>[_tPlate, _tPlateMinor, _tGcs, _tGcsList],
      );
      rethrow;
    }
  }
}
