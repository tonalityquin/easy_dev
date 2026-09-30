import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:googleapis/storage/v1.dart' as gcs;
import '../../../../app/auth/gcs_image_uploader.dart';
import '../../../../app/auth/google_auth_session.dart';
import '../../../../app/config/auth_config.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/dev/debug/debug_api_logger.dart';
import '../../../plate/application/common/input_plate.dart';
import '../../../plate/domain/models/plate_status_draft.dart';
import '../../../plate/editor/application/plate_camera_helper.dart';
import '../../../plate/editor/domain/stored_plate_photo.dart';
import '../../../plate/domain/models/plate_status_lookup_result.dart';

class PhotoUploadResult {
  final List<String> uploadedUrls;
  final List<String> uploadedObjectPaths;
  final List<String> failedFiles;

  const PhotoUploadResult({
    required this.uploadedUrls,
    required this.uploadedObjectPaths,
    required this.failedFiles,
  });

  int get failedCount => failedFiles.length;

  bool get hasFailure => failedFiles.isNotEmpty;
}

class InputPlateService {
  static const String _tPlate = 'plate';
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
    } catch (_) {}
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

  static String _twoDigits(int v) => v.toString().padLeft(2, '0');

  static String _buildMonthStrLocal(DateTime capturedAtUtc) {
    final local = capturedAtUtc.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${_twoDigits(local.month)}';
  }

  static String _buildCapturedFileName({
    required DateTime capturedAtUtc,
    required String plateNumber,
    required String userName,
  }) {
    return StoredPlatePhotoFileNameCodec.build(
      capturedAtUtc: capturedAtUtc,
      plateNumber: plateNumber,
      capturedBy: userName,
    );
  }

  static String _buildCapturedGcsPath({
    required String division,
    required String area,
    required DateTime capturedAtUtc,
    required String plateNumber,
    required String fileName,
  }) {
    final monthStr = _buildMonthStrLocal(capturedAtUtc);
    return StoredPlatePhotoCatalog.displayObjectPath(
      division: division,
      area: area,
      yearMonth: monthStr,
      plateNumber: plateNumber,
      fileName: fileName,
    );
  }

  static DateTime _capturedAtUtcFor(
    XFile image,
    File displayFile,
    ValueChanged<String>? onDebug,
  ) {
    final capturedAt = PlateCameraHelper.capturedAtUtcFor(image);
    if (capturedAt != null) {
      _emitDebug(
        onDebug,
        'photo_time=resolved source=camera capturedAtUtc=${capturedAt.toIso8601String()} capturedAtLocal=${capturedAt.toLocal().toIso8601String()} path=${image.path}',
      );
      return capturedAt;
    }
    try {
      final fallback = displayFile.lastModifiedSync().toUtc();
      _emitDebug(
        onDebug,
        'photo_time=resolved source=file_last_modified capturedAtUtc=${fallback.toIso8601String()} capturedAtLocal=${fallback.toLocal().toIso8601String()} path=${image.path}',
      );
      return fallback;
    } catch (error) {
      final fallback = DateTime.now().toUtc();
      _emitDebug(
        onDebug,
        'photo_time=resolved source=upload_fallback capturedAtUtc=${fallback.toIso8601String()} capturedAtLocal=${fallback.toLocal().toIso8601String()} path=${image.path} error=$error',
      );
      return fallback;
    }
  }

  static void _emitDebug(
    ValueChanged<String>? onDebug,
    String message,
  ) {
    final line = '[InputPlateService] ${message.trim()}';
    if (onDebug != null) {
      onDebug(line);
      return;
    }
    debugPrint(line);
  }

  static Future<String?> _uploadImageWithRetry({
    required GcsImageUploader uploader,
    required File file,
    required String gcsPath,
    required bool thumbnail,
    required String plateNumber,
    required String area,
    required String division,
    required String userName,
    required int index,
    required int total,
    ValueChanged<String>? onDebug,
  }) async {
    String? gcsUrl;
    for (int attempt = 0; attempt < _uploadMaxAttempts; attempt++) {
      try {
        _emitDebug(
          onDebug,
          'photo_upload=attempt type=${thumbnail ? 'thumbnail' : 'display'} index=$index total=$total attempt=${attempt + 1} path=$gcsPath bytes=${await file.length()}',
        );
        gcsUrl = await uploader.inputUploadImage(file, gcsPath);
        if (gcsUrl != null) {
          _emitDebug(
            onDebug,
            'photo_upload=success type=${thumbnail ? 'thumbnail' : 'display'} index=$index total=$total path=$gcsPath',
          );
          break;
        }
        await _logApiError(
          tag: 'InputPlateService.uploadCapturedImages',
          message: thumbnail ? 'GCS 썸네일 업로드 결과가 null' : 'GCS 업로드 결과가 null',
          error: Exception('upload_returned_null'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            userName: userName,
            filePath: file.path,
            gcsPath: gcsPath,
            index: index,
            total: total,
            attempt: attempt + 1,
          ),
          tags: const <String>[_tPlate, _tPlateUpload, _tGcs],
        );
      } catch (error) {
        _emitDebug(
          onDebug,
          'photo_upload=attempt_failed type=${thumbnail ? 'thumbnail' : 'display'} index=$index total=$total attempt=${attempt + 1} path=$gcsPath error=$error',
        );
        await _logApiError(
          tag: 'InputPlateService.uploadCapturedImages',
          message: thumbnail ? 'GCS 썸네일 업로드 예외' : 'GCS 업로드 예외',
          error: error,
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            userName: userName,
            filePath: file.path,
            gcsPath: gcsPath,
            index: index,
            total: total,
            attempt: attempt + 1,
          ),
          tags: const <String>[_tPlate, _tPlateUpload, _tGcs],
        );
        if (attempt + 1 < _uploadMaxAttempts) {
          await Future<void>.delayed(_uploadRetryDelay);
        }
      }
    }
    return gcsUrl;
  }

  static Future<PhotoUploadResult> uploadCapturedImages(
    List<XFile> images,
    String plateNumber,
    String area,
    String userName,
    String division, {
    ValueChanged<String>? onDebug,
  }) async {
    final uploader = GcsImageUploader();
    final uploadedUrls = <String>[];
    final uploadedObjectPaths = <String>[];
    final failedFiles = <String>[];
    final capturedBy = StoredPlatePhotoFileNameCodec.resolveCapturedBy(userName);

    _emitDebug(
      onDebug,
      'photo_upload=start plate=$plateNumber count=${images.length} area=$area division=$division capturedBy=$capturedBy',
    );

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final displayFile = File(image.path);
      final thumbnailFile = PlateCameraHelper.thumbnailFileFor(image);
      final itemIndex = i + 1;

      if (!displayFile.existsSync()) {
        failedFiles.add(displayFile.path);
        _emitDebug(
          onDebug,
          'photo_upload=file_missing type=display index=$itemIndex total=${images.length} path=${displayFile.path}',
        );
        await _logApiError(
          tag: 'InputPlateService.uploadCapturedImages',
          message: '업로드 대상 파일이 존재하지 않음',
          error: Exception('file_not_found'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            userName: capturedBy,
            filePath: displayFile.path,
            index: itemIndex,
            total: images.length,
          ),
          tags: const <String>[_tPlate, _tPlateUpload],
        );
        continue;
      }

      final capturedAtUtc = _capturedAtUtcFor(image, displayFile, onDebug);
      final capturedAtLocal = capturedAtUtc.toLocal();
      final storageYearMonth = _buildMonthStrLocal(capturedAtUtc);
      final uploadStartedAtUtc = DateTime.now().toUtc();
      final fileName = _buildCapturedFileName(
        capturedAtUtc: capturedAtUtc,
        plateNumber: plateNumber,
        userName: capturedBy,
      );
      final preparedMetadata = StoredPlatePhotoMetadata.fromFileName(
        fileName,
        fallbackPlateNumber: plateNumber,
      );
      _emitDebug(
        onDebug,
        'photo_metadata=prepared index=$itemIndex total=${images.length} fileName=$fileName capturedDate=${preparedMetadata.capturedDate} capturedTime=${preparedMetadata.capturedTime} plate=${preparedMetadata.plateNumber} capturedBy=${preparedMetadata.capturedBy}',
      );
      final displayPath = _buildCapturedGcsPath(
        division: division,
        area: area,
        capturedAtUtc: capturedAtUtc,
        plateNumber: plateNumber,
        fileName: fileName,
      );
      _emitDebug(
        onDebug,
        'photo_upload=timing index=$itemIndex total=${images.length} capturedAtUtc=${capturedAtUtc.toIso8601String()} capturedAtLocal=${capturedAtLocal.toIso8601String()} storageYearMonth=$storageYearMonth uploadStartedAtUtc=${uploadStartedAtUtc.toIso8601String()} lagMs=${uploadStartedAtUtc.difference(capturedAtUtc).inMilliseconds}',
      );
      final thumbnailPath =
          StoredPlatePhotoCatalog.thumbnailObjectPathForDisplay(displayPath);

      final displayUrl = await _uploadImageWithRetry(
        uploader: uploader,
        file: displayFile,
        gcsPath: displayPath,
        thumbnail: false,
        plateNumber: plateNumber,
        area: area,
        division: division,
        userName: capturedBy,
        index: itemIndex,
        total: images.length,
        onDebug: onDebug,
      );

      if (displayUrl == null) {
        failedFiles.add(displayFile.path);
        _emitDebug(
          onDebug,
          'photo_upload=failed type=display index=$itemIndex total=${images.length} path=$displayPath',
        );
        await _logApiError(
          tag: 'InputPlateService.uploadCapturedImages',
          message: 'GCS 업로드 최종 실패(재시도 소진)',
          error: Exception('upload_failed_final'),
          extra: _ctxBasic(
            plateNumber: plateNumber,
            area: area,
            division: division,
            userName: capturedBy,
            filePath: displayFile.path,
            gcsPath: displayPath,
            index: itemIndex,
            total: images.length,
          ),
          tags: const <String>[_tPlate, _tPlateUpload, _tGcs],
        );
        continue;
      }

      uploadedUrls.add(displayUrl);
      uploadedObjectPaths.add(displayPath);

      if (thumbnailFile.existsSync()) {
        final thumbnailUrl = await _uploadImageWithRetry(
          uploader: uploader,
          file: thumbnailFile,
          gcsPath: thumbnailPath,
          thumbnail: true,
          plateNumber: plateNumber,
          area: area,
          division: division,
          userName: capturedBy,
          index: itemIndex,
          total: images.length,
          onDebug: onDebug,
        );
        if (thumbnailUrl != null) {
          uploadedObjectPaths.add(thumbnailPath);
        } else {
          _emitDebug(
            onDebug,
            'photo_upload=thumbnail_nonfatal_failure index=$itemIndex total=${images.length} displayPath=$displayPath thumbnailPath=$thumbnailPath',
          );
        }
      } else {
        _emitDebug(
          onDebug,
          'photo_upload=thumbnail_missing_nonfatal index=$itemIndex total=${images.length} displayPath=$displayPath localPath=${thumbnailFile.path}',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    _emitDebug(
      onDebug,
      'photo_upload=complete displayUploaded=${uploadedUrls.length} objectUploaded=${uploadedObjectPaths.length} thumbnailUploaded=${uploadedObjectPaths.length - uploadedUrls.length} failed=${failedFiles.length}',
    );

    return PhotoUploadResult(
      uploadedUrls: List<String>.unmodifiable(uploadedUrls),
      uploadedObjectPaths: List<String>.unmodifiable(uploadedObjectPaths),
      failedFiles: List<String>.unmodifiable(failedFiles),
    );
  }

  static Future<List<String>> cleanupUploadedImages(
    List<String> objectPaths, {
    ValueChanged<String>? onDebug,
  }) async {
    if (objectPaths.isEmpty) return const <String>[];
    const bucketName = AuthConfig.gcsBucketName;
    final normalizedPaths = objectPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (normalizedPaths.isEmpty) return const <String>[];

    late final gcs.StorageApi storage;
    try {
      storage = await _storage();
    } catch (error) {
      _emitDebug(onDebug, 'photo_cleanup=prepare_failed error=$error');
      return List<String>.unmodifiable(normalizedPaths);
    }

    final failedPaths = <String>[];

    for (final path in normalizedPaths) {
      try {
        _emitDebug(onDebug, 'photo_cleanup=start path=$path');
        await storage.objects.delete(bucketName, path);
        _emitDebug(onDebug, 'photo_cleanup=success path=$path');
      } catch (error) {
        failedPaths.add(path);
        _emitDebug(onDebug, 'photo_cleanup=failed path=$path error=$error');
        await _logApiError(
          tag: 'InputPlateService.cleanupUploadedImages',
          message: '입차 등록 실패 후 GCS 업로드 롤백 실패',
          error: error,
          extra: <String, dynamic>{
            'bucket': bucketName,
            'gcsPath': path,
          },
          tags: const <String>[_tPlate, _tPlateUpload, _tGcs],
        );
      }
    }

    return List<String>.unmodifiable(failedPaths);
  }

  static Future<bool> registerPlateEntry({
    required BuildContext context,
    required String plateNumber,
    required String location,
    required bool isLocationSelected,
    required List<String> imageUrls,
    required String? selectedBill,
    required bool statusWriteRequested,
    required PlateStatusLookupState statusLookupState,
    required bool statusEditedByUser,
    required PlateStatusDraft expectedOriginalStatus,
    String? expectedStatusSourcePath,
    required int basicStandard,
    required int basicAmount,
    required int addStandard,
    required int addAmount,
    int? regularAmount,
    int? regularDurationHours,
    required String region,
    String? customStatus,
    required String selectedBillType,
    String? manufacturerName,
    String? modelName,
    String? priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
    String? sectorId,
    String? sectorName,
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
        isLocationSelected: isLocationSelected,
        areaState: areaState,
        userState: userState,
        billingType: selectedBill,
        statusWriteRequested: statusWriteRequested,
        statusLookupState: statusLookupState,
        statusEditedByUser: statusEditedByUser,
        expectedOriginalStatus: expectedOriginalStatus,
        expectedStatusSourcePath: expectedStatusSourcePath,
        basicStandard: finalBasicStandard,
        basicAmount: finalBasicAmount,
        addStandard: finalAddStandard,
        addAmount: finalAddAmount,
        regularAmount: selectedBillType == '정기' ? null : regularAmount,
        regularDurationHours:
            selectedBillType == '정기' ? null : regularDurationHours,
        region: region,
        imageUrls: imageUrls,
        customStatus: customStatus ?? '',
        selectedBillType: selectedBillType,
        manufacturerName: manufacturerName,
        modelName: modelName,
        priority1SlotKey: priority1SlotKey,
        priority2SlotKey: priority2SlotKey,
        priority3SlotKey: priority3SlotKey,
        sectorId: sectorId,
        sectorName: sectorName,
      );
    } catch (e) {
      await _logApiError(
        tag: 'InputPlateService.registerPlateEntry',
        message: '입차 등록(registerPlateEntry) 실패',
        error: e,
        extra: <String, dynamic>{
          'plateNumber': plateNumber,
          'locationLen': location.trim().length,
          'isLocationSelected': isLocationSelected,
          'imageUrlsCount': imageUrls.length,
          'selectedBillType': selectedBillType,
          'statusWriteRequested': statusWriteRequested,
          'statusLookupState': statusLookupState.name,
          'statusEditedByUser': statusEditedByUser,
          'regionLen': region.trim().length,
          'customStatusLen': (customStatus ?? '').trim().length,
          'manufacturerNameLen': (manufacturerName ?? '').trim().length,
          'modelNameLen': (modelName ?? '').trim().length,
          'priority1SlotKey': priority1SlotKey,
          'priority2SlotKey': priority2SlotKey,
          'priority3SlotKey': priority3SlotKey,
          'sectorId': sectorId,
          'sectorName': sectorName,
          'area': areaState.currentArea,
          'division': areaState.currentDivision,
          'userNameLen': userState.name.trim().length,
        },
        tags: const <String>[_tPlate, _tPlateRegister],
      );
      rethrow;
    }
  }

  static Future<gcs.StorageApi> _storage() async {
    try {
      final client = await GoogleAuthSession.instance.safeClient();
      return gcs.StorageApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'InputPlateService._storage',
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

  static Future<List<StoredPlatePhoto>> listStoredPlateImages({
    required BuildContext context,
    required String plateNumber,
    required String yearMonth,
    ValueChanged<String>? onDebug,
  }) async {
    const bucketName = AuthConfig.gcsBucketName;
    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;
    final storage = await _storage();

    late final String ym;
    try {
      ym = _sanitizeYearMonth(yearMonth);
    } catch (error) {
      _emitDebug(
        onDebug,
        'photo_list=invalid_year_month plate=$plateNumber yearMonth=$yearMonth error=$error',
      );
      await _logApiError(
        tag: 'InputPlateService.listStoredPlateImages',
        message: 'yearMonth 파라미터 검증 실패',
        error: error,
        extra: _ctxBasic(
          plateNumber: plateNumber,
          area: area,
          division: division,
          yearMonth: yearMonth,
        ),
        tags: const <String>[_tPlate, _tGcsList],
      );
      rethrow;
    }

    final displayPrefix = StoredPlatePhotoCatalog.displayPrefix(
      division: division,
      area: area,
      yearMonth: ym,
      plateNumber: plateNumber,
    );
    final thumbnailPrefix = StoredPlatePhotoCatalog.thumbnailPrefix(
      division: division,
      area: area,
      yearMonth: ym,
      plateNumber: plateNumber,
    );
    final legacyDisplayPrefix = StoredPlatePhotoCatalog.legacyDisplayPrefix(
      division: division,
      area: area,
      yearMonth: ym,
    );
    final legacyThumbnailPrefix = StoredPlatePhotoCatalog.legacyThumbnailPrefix(
      division: division,
      area: area,
      yearMonth: ym,
    );
    final legacyRootPrefix = StoredPlatePhotoCatalog.legacyRootPrefix(
      division: division,
      area: area,
      yearMonth: ym,
    );
    final readMode = StoredPlatePhotoCatalog.readModeForYearMonth(ym);

    final objectPaths = <String>{};
    var pageCount = 0;
    final stopwatch = Stopwatch()..start();

    Future<int> collect({
      required String asset,
      required String prefix,
      required bool legacy,
      bool directChildrenOnly = false,
    }) async {
      var matched = 0;
      var queryPages = 0;
      String? pageToken;
      _emitDebug(
        onDebug,
        'photo_list=query_start asset=$asset plate=$plateNumber yearMonth=$ym readMode=${readMode.name} prefix=$prefix legacy=$legacy',
      );
      do {
        final res = await storage.objects.list(
          bucketName,
          prefix: prefix,
          delimiter: directChildrenOnly ? '/' : null,
          pageToken: pageToken,
        );
        queryPages++;
        pageCount++;
        final items = res.items ?? const <gcs.Object>[];
        for (final obj in items) {
          final name = obj.name?.trim();
          if (name == null ||
              name.isEmpty ||
              !name.toLowerCase().endsWith('.jpg')) {
            continue;
          }
          if (directChildrenOnly &&
              !StoredPlatePhotoCatalog.isDirectChildOfPrefix(name, prefix)) {
            continue;
          }
          if (legacy && !name.contains(plateNumber)) {
            continue;
          }
          if (objectPaths.add(name)) matched++;
        }
        pageToken = res.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
      _emitDebug(
        onDebug,
        'photo_list=query_success asset=$asset plate=$plateNumber yearMonth=$ym readMode=${readMode.name} prefix=$prefix pages=$queryPages matched=$matched legacy=$legacy',
      );
      return matched;
    }

    _emitDebug(
      onDebug,
      'photo_list=start plate=$plateNumber yearMonth=$ym readMode=${readMode.name} displayPrefix=$displayPrefix thumbnailPrefix=$thumbnailPrefix',
    );

    try {
      if (readMode != StoredPlatePhotoReadMode.legacyOnly) {
        await collect(
          asset: 'display',
          prefix: displayPrefix,
          legacy: false,
        );
        await collect(
          asset: 'thumbnail',
          prefix: thumbnailPrefix,
          legacy: false,
        );
      }
      if (readMode != StoredPlatePhotoReadMode.prefixedOnly) {
        final legacyDisplayCount = await collect(
          asset: 'legacy_display',
          prefix: legacyDisplayPrefix,
          legacy: true,
          directChildrenOnly: true,
        );
        final legacyRootDisplayCount = await collect(
          asset: 'legacy_root_display',
          prefix: legacyRootPrefix,
          legacy: true,
          directChildrenOnly: true,
        );
        if (legacyDisplayCount + legacyRootDisplayCount > 0) {
          await collect(
            asset: 'legacy_thumbnail',
            prefix: legacyThumbnailPrefix,
            legacy: true,
            directChildrenOnly: true,
          );
        }
      }

      final photos = StoredPlatePhotoCatalog.pairObjectPaths(
        bucketName: bucketName,
        objectPaths: objectPaths,
        plateNumber: plateNumber,
      );
      final thumbnailCount =
          photos.where((photo) => photo.hasThumbnail).length;
      final missingThumbnailCount = photos.length - thumbnailCount;
      final displayObjectCount = objectPaths
          .where(StoredPlatePhotoCatalog.isDisplayObjectPath)
          .length;
      final thumbnailObjectCount = objectPaths
          .where(StoredPlatePhotoCatalog.isThumbnailObjectPath)
          .length;
      final legacyDisplayObjectCount = objectPaths
          .where(StoredPlatePhotoCatalog.isLegacyDisplayObjectPath)
          .length;
      stopwatch.stop();
      _emitDebug(
        onDebug,
        'photo_list=success plate=$plateNumber yearMonth=$ym readMode=${readMode.name} pages=$pageCount matchedObjects=${objectPaths.length} displayObjects=$displayObjectCount thumbnailObjects=$thumbnailObjectCount legacyDisplayObjects=$legacyDisplayObjectCount photos=${photos.length} thumbnails=$thumbnailCount missingThumbnails=$missingThumbnailCount elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return photos;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _emitDebug(
        onDebug,
        'photo_list=failed plate=$plateNumber yearMonth=$ym readMode=${readMode.name} pages=$pageCount matchedObjects=${objectPaths.length} elapsedMs=${stopwatch.elapsedMilliseconds} error=$error',
      );
      _emitDebug(onDebug, 'photo_list=stack_trace\n$stackTrace');
      await _logApiError(
        tag: 'InputPlateService.listStoredPlateImages',
        message: 'GCS objects.list 실패',
        error: error,
        extra: <String, dynamic>{
          'bucket': bucketName,
          'displayPrefix': displayPrefix,
          'thumbnailPrefix': thumbnailPrefix,
          'legacyDisplayPrefix': legacyDisplayPrefix,
          'legacyThumbnailPrefix': legacyThumbnailPrefix,
          'legacyRootPrefix': legacyRootPrefix,
          'plateNumber': plateNumber,
          'yearMonth': ym,
          'found': objectPaths.length,
        },
        tags: const <String>[_tPlate, _tGcs, _tGcsList],
      );
      rethrow;
    }
  }
}
