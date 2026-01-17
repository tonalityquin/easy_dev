import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

// GCS
import 'package:googleapis/storage/v1.dart' as gcs;

// ✅ 중앙 OAuth 세션만 사용 (최초 1회 로그인 후 재사용)
import '../../../../utils/google_auth_session.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

import '../../../../utils/gcs/gcs_image_uploader.dart';
import '../../../../states/plate/input_plate.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';

class DoubleInputPlateService {
  // ─────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────
  static const String _tPlate = 'plate';
  static const String _tPlateDouble = 'plate/double';
  static const String _tPlateUpload = 'plate/upload';
  static const String _tPlateRegister = 'plate/register';
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
    String? userName,
    String? filePath,
    String? gcsPath,
    String? yearMonth,
    int? index,
    int? total,
    int? attempt,
  }) {
    return <String, dynamic>{
      if (plateNumber != null) 'plateNumber': plateNumber,
      if (area != null) 'area': area,
      if (division != null) 'division': division,
      if (userName != null) 'userNameLen': userName.trim().length,
      if (filePath != null) 'filePath': filePath,
      if (gcsPath != null) 'gcsPath': gcsPath,
      if (yearMonth != null) 'yearMonth': yearMonth,
      if (index != null) 'index': index,
      if (total != null) 'total': total,
      if (attempt != null) 'attempt': attempt,
    };
  }

  // ─────────────────────────────────────────
  // 날짜/경로 유틸 (UTC 기준 통일)
  // ─────────────────────────────────────────
  static String _twoDigits(int v) => v.toString().padLeft(2, '0');

  /// yyyy-MM-dd (UTC)
  static String _buildDateStrUtc(DateTime nowUtc) {
    return '${nowUtc.year.toString().padLeft(4, '0')}-${_twoDigits(nowUtc.month)}-${_twoDigits(nowUtc.day)}';
  }

  /// yyyy-MM (UTC)  (✅ 월 폴더명)
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

  /// ✅ 업로드 경로 규칙(UTC 월 기준):
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

  // ─────────────────────────────────────────
  // ✅ 업로드: 디버그 로깅 + 재시도 + 월 폴더 규칙
  // ─────────────────────────────────────────
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

        await _logApiError(
          tag: 'DoubleInputPlateService.uploadCapturedImages',
          message: '업로드 대상 파일이 존재하지 않음',
          error: Exception('file_not_found'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            userName: userName,
            filePath: file.path,
            index: i + 1,
            total: images.length,
          ),
          tags: const <String>[_tPlate, _tPlateDouble, _tPlateUpload],
        );

        continue;
      }

      final nowUtc = DateTime.now().toUtc();

      final fileName = _buildFileNameUtc(
        nowUtc: nowUtc,
        plateNumber: plateNumber,
        userName: userName,
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
          debugPrint('⬆️ [${i + 1}/${images.length}] 업로드 시도 #${attempt + 1}: $gcsPath');
          // NOTE: GcsImageUploader 내부가 OAuth(중앙 세션) 사용하도록 리팩터링되어 있다고 가정
          gcsUrl = await uploader.inputUploadImage(file, gcsPath);
          if (gcsUrl != null) {
            debugPrint('✅ 업로드 성공: $gcsUrl');
            break;
          }

          // null 반환도 실패로 간주(상세 로그)
          await _logApiError(
            tag: 'DoubleInputPlateService.uploadCapturedImages',
            message: 'GCS 업로드 결과가 null',
            error: Exception('upload_returned_null'),
            extra: _ctxBasic(
              plateNumber: plateNumber,
              area: area,
              division: division,
              userName: userName,
              filePath: file.path,
              gcsPath: gcsPath,
              index: i + 1,
              total: images.length,
              attempt: attempt + 1,
            ),
            tags: const <String>[_tPlate, _tPlateDouble, _tPlateUpload, _tGcs],
          );
        } catch (e) {
          debugPrint('❌ [시도 ${attempt + 1}] 업로드 실패 (${file.path}): $e');

          await _logApiError(
            tag: 'DoubleInputPlateService.uploadCapturedImages',
            message: 'GCS 업로드 예외',
            error: e,
            extra: _ctxBasic(
              plateNumber: plateNumber,
              area: area,
              division: division,
              userName: userName,
              filePath: file.path,
              gcsPath: gcsPath,
              index: i + 1,
              total: images.length,
              attempt: attempt + 1,
            ),
            tags: const <String>[_tPlate, _tPlateDouble, _tPlateUpload, _tGcs],
          );

          await Future.delayed(_uploadRetryDelay);
        }
      }

      if (gcsUrl == null) {
        debugPrint('❌ 업로드 최종 실패: ${file.path}');
        failedFiles.add(file.path);

        await _logApiError(
          tag: 'DoubleInputPlateService.uploadCapturedImages',
          message: 'GCS 업로드 최종 실패(재시도 소진)',
          error: Exception('upload_failed_final'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            userName: userName,
            filePath: file.path,
            gcsPath: gcsPath,
            index: i + 1,
            total: images.length,
          ),
          tags: const <String>[_tPlate, _tPlateDouble, _tPlateUpload, _tGcs],
        );
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

  // ─────────────────────────────────────────
  // ✅ 입차 등록: 예외 로깅 추가
  // ─────────────────────────────────────────
  static Future<bool> doubleRegisterPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
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

    try {
      return await inputState.commonRegisterPlateEntry(
        context: context,
        plateNumber: plateNumber,
        location: location,
        isLocationSelected: true, // ✅ Double 모드: 입차 완료만 허용
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
    } catch (e) {
      await _logApiError(
        tag: 'DoubleInputPlateService.registerPlateEntry',
        message: '입차 등록(registerPlateEntry) 실패',
        error: e,
        extra: <String, dynamic>{
          'plateNumber': plateNumber,
          'locationLen': location.trim().length,
          'imageUrlsCount': imageUrls.length,
          'selectedBillType': selectedBillType,
          'statusCount': selectedStatuses.length,
          'regionLen': region.trim().length,
          'customStatusLen': (customStatus ?? '').trim().length,
          'area': areaState.currentArea,
          'division': areaState.currentDivision,
          'userNameLen': userState.name.trim().length,
        },
        tags: const <String>[_tPlate, _tPlateDouble, _tPlateRegister],
      );
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // GCS 목록 조회 (중앙 세션 사용) + 디버그 로깅
  // ─────────────────────────────────────────
  static Future<gcs.StorageApi> _storage() async {
    try {
      final client = await GoogleAuthSession.instance.safeClient();
      return gcs.StorageApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'DoubleInputPlateService._storage',
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
        tag: 'DoubleInputPlateService.listPlateImages',
        message: 'yearMonth 파라미터 검증 실패',
        error: e,
        extra: _ctxBasic(
          plateNumber: plateNumber,
          area: area,
          division: division,
          yearMonth: yearMonth,
        ),
        tags: const <String>[_tPlate, _tPlateDouble, _tGcsList],
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
        tag: 'DoubleInputPlateService.listPlateImages',
        message: 'GCS objects.list 실패',
        error: e,
        extra: <String, dynamic>{
          'bucket': bucketName,
          'prefix': prefix,
          'plateNumber': plateNumber,
          'found': urls.length,
        },
        tags: const <String>[_tPlate, _tPlateDouble, _tGcs, _tGcsList],
      );
      rethrow;
    }
  }
}
