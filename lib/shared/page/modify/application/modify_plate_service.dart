import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/models/plate_log_model.dart';
import '../../../plate/domain/models/plate_model.dart';
import '../../../plate/domain/models/plate_status_draft.dart';
import '../../../plate/domain/models/plate_status_scope.dart';
import '../../../plate/domain/repositories/plate_repository.dart';

class ModifyPhotoUploadResult {
  final List<String> mergedUrls;
  final List<String> uploadedObjectPaths;
  final List<String> failedFiles;

  const ModifyPhotoUploadResult({
    required this.mergedUrls,
    required this.uploadedObjectPaths,
    required this.failedFiles,
  });

  bool get hasFailure => failedFiles.isNotEmpty;
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

  final int selectedBasicStandard;
  final int selectedBasicAmount;
  final int selectedAddStandard;
  final int selectedAddAmount;
  final int selectedRegularAmount;
  final int selectedRegularDurationHours;

  final String? selectedBill;
  final String selectedBillType;
  final String dropdownValue;
  final String? manufacturerName;
  final String? modelName;
  final String? priority1SlotKey;
  final String? priority2SlotKey;
  final String? priority3SlotKey;
  final String? selectedSectorId;
  final String? selectedSectorName;
  final bool canUseBill;
  final bool canUseSector;
  final PlateStatusScope? statusScope;
  final bool statusChanged;
  final PlateStatusDraft expectedOriginalStatus;
  final String? expectedStatusSourcePath;
  final String statusActorId;
  final String statusActorName;
  final ValueChanged<String>? onDebug;

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
    required this.selectedBasicStandard,
    required this.selectedBasicAmount,
    required this.selectedAddStandard,
    required this.selectedAddAmount,
    required this.selectedBill,
    required this.selectedBillType,
    required this.dropdownValue,
    required this.selectedRegularAmount,
    required this.selectedRegularDurationHours,
    required this.manufacturerName,
    required this.modelName,
    required this.priority1SlotKey,
    required this.priority2SlotKey,
    required this.priority3SlotKey,
    required this.selectedSectorId,
    required this.selectedSectorName,
    required this.canUseBill,
    required this.canUseSector,
    required this.statusScope,
    required this.statusChanged,
    required this.expectedOriginalStatus,
    required this.expectedStatusSourcePath,
    required this.statusActorId,
    required this.statusActorName,
    this.onDebug,
  });

  static const String _tPlate = 'plate';
  static const String _tPlateDouble = 'plate/double';
  static const String _tPlateModify = 'plate/modify';
  static const String _tPlateUpload = 'plate/upload';
  static const String _tPlateRepo = 'plate/repo';
  static const String _tGcs = 'gcs';
  static const String _tGcsList = 'gcs/list';
  static const String _tAuth = 'google/auth';

  static const Duration _uploadRetryDelay = Duration(milliseconds: 500);
  static const int _uploadMaxAttempts = 3;

  void _debug(String message) {
    final normalized = '[ModifyPlateService] $message';
    final callback = onDebug;
    if (callback != null) {
      callback(normalized);
      return;
    }
    debugPrint(normalized);
  }

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

  static String _twoDigits(int v) => v.toString().padLeft(2, '0');

  static String _buildDateStrUtc(DateTime nowUtc) {
    return '${nowUtc.year.toString().padLeft(4, '0')}-${_twoDigits(nowUtc.month)}-${_twoDigits(nowUtc.day)}';
  }

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

  static String _buildGcsPathUtc({
    required String division,
    required String area,
    required DateTime nowUtc,
    required String fileName,
  }) {
    final monthStr = _buildMonthStrUtc(nowUtc);
    return '$division/$area/images/$monthStr/$fileName';
  }

  static bool _sameStringList(List<String>? left, List<String> right) {
    final a = left ?? const <String>[];
    if (a.length != right.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != right[i]) return false;
    }
    return true;
  }

  String composePlateNumber() {
    return '${controllerFrontdigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  Future<ModifyPhotoUploadResult> uploadAndMergeImages(
    String plateNumber,
  ) async {
    final uploader = GcsImageUploader();
    final uploadedImageUrls = <String>[];
    final uploadedObjectPaths = <String>[];
    final failedFiles = <String>[];

    final area = context.read<AreaState>().currentArea;
    final division = context.read<AreaState>().currentDivision;
    final session = context.read<UserState>().session;
    final performedBy = session?.displayName ?? 'Unknown';

    _debug(
      'photo_upload=start plate=$plateNumber captured=${capturedImages.length} existing=${existingImageUrls.length}',
    );

    for (int i = 0; i < capturedImages.length; i++) {
      final image = capturedImages[i];
      final file = File(image.path);
      if (!file.existsSync()) {
        failedFiles.add(file.path);
        _debug(
          'photo_upload=file_missing index=${i + 1} total=${capturedImages.length} path=${file.path}',
        );
        await _logApiError(
          tag: 'DoubleModifyPlateService.uploadAndMergeImages',
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
          tags: const <String>[
            _tPlate,
            _tPlateDouble,
            _tPlateModify,
            _tPlateUpload,
          ],
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
          _debug(
            'photo_upload=attempt index=${i + 1} total=${capturedImages.length} attempt=${attempt + 1} path=$gcsPath',
          );
          gcsUrl = await uploader.modifyUploadImage(file, gcsPath);
          if (gcsUrl != null) break;
          await _logApiError(
            tag: 'DoubleModifyPlateService.uploadAndMergeImages',
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
            tags: const <String>[
              _tPlate,
              _tPlateDouble,
              _tPlateModify,
              _tPlateUpload,
              _tGcs,
            ],
          );
        } catch (e) {
          _debug(
            'photo_upload=attempt_failed index=${i + 1} attempt=${attempt + 1} error=$e',
          );
          await _logApiError(
            tag: 'DoubleModifyPlateService.uploadAndMergeImages',
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
            tags: const <String>[
              _tPlate,
              _tPlateDouble,
              _tPlateModify,
              _tPlateUpload,
              _tGcs,
            ],
          );
          await Future.delayed(_uploadRetryDelay);
        }
      }

      if (gcsUrl != null) {
        uploadedImageUrls.add(gcsUrl);
        uploadedObjectPaths.add(gcsPath);
        _debug(
          'photo_upload=success index=${i + 1} path=$gcsPath',
        );
      } else {
        failedFiles.add(file.path);
        _debug(
          'photo_upload=failed index=${i + 1} path=$gcsPath',
        );
        await _logApiError(
          tag: 'DoubleModifyPlateService.uploadAndMergeImages',
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
          tags: const <String>[
            _tPlate,
            _tPlateDouble,
            _tPlateModify,
            _tPlateUpload,
            _tGcs,
          ],
        );
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (failedFiles.isNotEmpty) {
      await _logApiError(
        tag: 'DoubleModifyPlateService.uploadAndMergeImages',
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
        tags: const <String>[
          _tPlate,
          _tPlateDouble,
          _tPlateModify,
          _tPlateUpload,
        ],
      );
    }

    final mergedUrls = <String>[
      ...existingImageUrls,
      ...uploadedImageUrls,
    ];
    _debug(
      'photo_upload=complete merged=${mergedUrls.length} uploaded=${uploadedObjectPaths.length} failed=${failedFiles.length}',
    );
    return ModifyPhotoUploadResult(
      mergedUrls: List<String>.unmodifiable(mergedUrls),
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
      final message =
          '[ModifyPlateService] photo_cleanup=prepare_failed error=$error';
      if (onDebug != null) {
        onDebug(message);
      } else {
        debugPrint(message);
      }
      return List<String>.unmodifiable(normalizedPaths);
    }

    final failedPaths = <String>[];
    for (final path in normalizedPaths) {
      try {
        final startMessage =
            '[ModifyPlateService] photo_cleanup=start path=$path';
        if (onDebug != null) {
          onDebug(startMessage);
        } else {
          debugPrint(startMessage);
        }
        await storage.objects.delete(bucketName, path);
        final successMessage =
            '[ModifyPlateService] photo_cleanup=success path=$path';
        if (onDebug != null) {
          onDebug(successMessage);
        } else {
          debugPrint(successMessage);
        }
      } catch (error) {
        failedPaths.add(path);
        final failureMessage =
            '[ModifyPlateService] photo_cleanup=failed path=$path error=$error';
        if (onDebug != null) {
          onDebug(failureMessage);
        } else {
          debugPrint(failureMessage);
        }
        await _logApiError(
          tag: 'DoubleModifyPlateService.cleanupUploadedImages',
          message: '차량 수정 실패 후 GCS 업로드 롤백 실패',
          error: error,
          extra: <String, dynamic>{
            'bucket': bucketName,
            'gcsPath': path,
          },
          tags: const <String>[
            _tPlate,
            _tPlateDouble,
            _tPlateModify,
            _tPlateUpload,
            _tGcs,
          ],
        );
      }
    }
    return List<String>.unmodifiable(failedPaths);
  }

  Future<bool> updatePlateInfo({
    required String plateNumber,
    required List<String> imageUrls,
    required String newLocation,
    required String? newBillingType,
    required String updatedCustomStatus,
  }) async {
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    final repo = context.read<PlateRepository>();
    final normalizedSectorId = selectedSectorId?.trim() ?? '';
    final normalizedSectorName = selectedSectorName?.trim() ?? '';

    if (canUseSector &&
        normalizedSectorId.isEmpty != normalizedSectorName.isEmpty) {
      throw ArgumentError('sectorId와 sectorName은 함께 전달되어야 합니다.');
    }

    final hasSector = canUseSector &&
        normalizedSectorId.isNotEmpty &&
        normalizedSectorName.isNotEmpty;
    final effectiveSectorId = canUseSector
        ? (hasSector ? normalizedSectorId : null)
        : originalPlate.sectorId;
    final effectiveSectorName = canUseSector
        ? (hasSector ? normalizedSectorName : null)
        : originalPlate.sectorName;
    final effectiveBillingType =
        canUseBill ? newBillingType : originalPlate.billingType;
    final effectiveBillingPlanType = canUseBill
        ? (selectedBillType == '정기' ? '정기' : '변동')
        : originalPlate.billingPlanType;
    final effectiveBasicStandard =
        canUseBill ? selectedBasicStandard : originalPlate.basicStandard;
    final effectiveBasicAmount =
        canUseBill ? selectedBasicAmount : originalPlate.basicAmount;
    final effectiveAddStandard =
        canUseBill ? selectedAddStandard : originalPlate.addStandard;
    final effectiveAddAmount =
        canUseBill ? selectedAddAmount : originalPlate.addAmount;
    final effectiveRegularAmount =
        canUseBill ? selectedRegularAmount : originalPlate.regularAmount;
    final effectiveRegularDurationValue = canUseBill
        ? selectedRegularDurationHours
        : originalPlate.regularDurationValue;
    final effectiveCustomStatus =
        statusChanged ? updatedCustomStatus : originalPlate.customStatus;

    _debug(
      'update=prepare plate=$plateNumber area=${originalPlate.area} '
      'bill=$canUseBill sector=$canUseSector statusChanged=$statusChanged',
    );

    final updatedPlate = PlateModel(
      id: originalPlate.id,
      addAmount: effectiveAddAmount,
      addStandard: effectiveAddStandard,
      area: originalPlate.area,
      basicAmount: effectiveBasicAmount,
      basicStandard: effectiveBasicStandard,
      billingType: effectiveBillingType,
      billingPlanType: effectiveBillingPlanType,
      customStatus: effectiveCustomStatus,
      endTime: originalPlate.endTime,
      imageUrls: imageUrls,
      isLockedFee: originalPlate.isLockedFee,
      isSelected: originalPlate.isSelected,
      location: newLocation,
      lockedAtTimeInSeconds: originalPlate.lockedAtTimeInSeconds,
      lockedFeeAmount: originalPlate.lockedFeeAmount,
      logs: originalPlate.logs,
      paymentMethod: originalPlate.paymentMethod,
      manufacturerName: manufacturerName,
      modelName: modelName,
      parkingPriority1SlotKey: priority1SlotKey,
      parkingPriority2SlotKey: priority2SlotKey,
      parkingPriority3SlotKey: priority3SlotKey,
      plateFourDigit: originalPlate.plateFourDigit,
      plateNumber: plateNumber,
      region: dropdownValue,
      regularAmount: effectiveRegularAmount,
      regularDurationValue: effectiveRegularDurationValue,
      requestTime: originalPlate.requestTime,
      selectedBy: originalPlate.selectedBy,
      type: originalPlate.type,
      updatedAt: originalPlate.updatedAt,
      userAdjustment: originalPlate.userAdjustment,
      userName: originalPlate.userName,
      feeMode: originalPlate.feeMode,
      sectorId: effectiveSectorId,
      sectorName: effectiveSectorName,
    );

    final changes = originalPlate.diff(updatedPlate);
    if (!_sameStringList(originalPlate.imageUrls, imageUrls)) {
      changes[PlateFields.imageUrls] = <String, dynamic>{
        'before': originalPlate.imageUrls ?? const <String>[],
        'after': imageUrls,
      };
    }

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

    final updatedFields = <String, dynamic>{};
    if (originalPlate.location != updatedPlate.location) {
      updatedFields[PlateFields.location] = updatedPlate.location;
    }
    if (originalPlate.billingType != updatedPlate.billingType) {
      updatedFields[PlateFields.billingType] = updatedPlate.billingType;
    }
    if (originalPlate.billingPlanType != updatedPlate.billingPlanType) {
      updatedFields[PlateFields.billingPlanType] = updatedPlate.billingPlanType;
    }
    if (originalPlate.plateNumber != updatedPlate.plateNumber) {
      updatedFields[PlateFields.plateNumber] = updatedPlate.plateNumber;
    }
    if (statusChanged) {
      updatedFields[PlateFields.customStatus] = updatedCustomStatus;
    }
    if (!_sameStringList(originalPlate.imageUrls, imageUrls)) {
      updatedFields[PlateFields.imageUrls] = imageUrls;
    }
    if (originalPlate.region != updatedPlate.region) {
      updatedFields[PlateFields.region] = updatedPlate.region;
    }
    if (originalPlate.basicStandard != updatedPlate.basicStandard) {
      updatedFields[PlateFields.basicStandard] = updatedPlate.basicStandard;
    }
    if (originalPlate.basicAmount != updatedPlate.basicAmount) {
      updatedFields[PlateFields.basicAmount] = updatedPlate.basicAmount;
    }
    if (originalPlate.addStandard != updatedPlate.addStandard) {
      updatedFields[PlateFields.addStandard] = updatedPlate.addStandard;
    }
    if (originalPlate.addAmount != updatedPlate.addAmount) {
      updatedFields[PlateFields.addAmount] = updatedPlate.addAmount;
    }
    if (originalPlate.regularAmount != updatedPlate.regularAmount) {
      updatedFields[PlateFields.regularAmount] = updatedPlate.regularAmount;
    }
    if (originalPlate.regularDurationValue != updatedPlate.regularDurationValue) {
      updatedFields[PlateFields.regularDurationValue] =
          updatedPlate.regularDurationValue;
      updatedFields[PlateFields.regularDurationHours] =
          updatedPlate.regularDurationValue;
    }
    if (originalPlate.manufacturerName != updatedPlate.manufacturerName) {
      updatedFields[PlateFields.manufacturerName] = updatedPlate.manufacturerName;
    }
    if (originalPlate.modelName != updatedPlate.modelName) {
      updatedFields[PlateFields.modelName] = updatedPlate.modelName;
    }
    if (originalPlate.parkingPriority1SlotKey !=
        updatedPlate.parkingPriority1SlotKey) {
      updatedFields[PlateFields.parkingPriority1SlotKey] =
          updatedPlate.parkingPriority1SlotKey;
    }
    if (originalPlate.parkingPriority2SlotKey !=
        updatedPlate.parkingPriority2SlotKey) {
      updatedFields[PlateFields.parkingPriority2SlotKey] =
          updatedPlate.parkingPriority2SlotKey;
    }
    if (originalPlate.parkingPriority3SlotKey !=
        updatedPlate.parkingPriority3SlotKey) {
      updatedFields[PlateFields.parkingPriority3SlotKey] =
          updatedPlate.parkingPriority3SlotKey;
    }
    if (canUseSector && originalPlate.sectorId != updatedPlate.sectorId) {
      updatedFields[PlateFields.sectorId] = hasSector
          ? normalizedSectorId
          : FieldValue.delete();
    }
    if (canUseSector && originalPlate.sectorName != updatedPlate.sectorName) {
      updatedFields[PlateFields.sectorName] = hasSector
          ? normalizedSectorName
          : FieldValue.delete();
    }

    _debug(
      'update=fields_ready count=${updatedFields.length} '
      'keys=${updatedFields.keys.join(',')} statusChanged=$statusChanged',
    );

    try {
      final documentId = '${originalPlate.plateNumber}_${originalPlate.area}';
      if (statusChanged) {
        final resolvedScope = statusScope;
        if (resolvedScope == null) {
          throw StateError('status scope is required when status changes');
        }
        await repo.updatePlateWithStatus(
          documentId,
          updatedFields,
          log: log,
          plateNumber: plateNumber,
          area: originalPlate.area,
          statusScope: resolvedScope,
          statusChanged: true,
          expectedOriginalStatus: expectedOriginalStatus,
          expectedStatusSourcePath: expectedStatusSourcePath,
          customStatus: updatedCustomStatus,
          updatedByName: statusActorName,
          updatedById: statusActorId,
        );
      } else {
        await repo.updatePlate(
          documentId,
          updatedFields,
          log: log,
        );
      }
      _debug(
        'update=success statusMode=${statusChanged ? 'transaction' : 'plate_only'} fields=${updatedFields.length}',
      );
      return true;
    } catch (e) {
      await _logApiError(
        tag: 'DoubleModifyPlateService.updatePlateInfo',
        message: statusChanged
            ? 'PlateRepository.updatePlateWithStatus 실패'
            : 'PlateRepository.updatePlate 실패',
        error: e,
        extra: <String, dynamic>{
          'docId': '${originalPlate.plateNumber}_${originalPlate.area}',
          'area': areaState.currentArea,
          'division': areaState.currentDivision,
          'performedByLen': userState.name.trim().length,
          'originalPlateNumber': originalPlate.plateNumber,
          'newPlateNumber': plateNumber,
          'imageUrlsCount': imageUrls.length,
          'statusChanged': statusChanged,
          'statusScope': statusScope?.storageLabel ?? 'skipped',
          'hasLog': log != null,
          'changedFieldsCount': changes.length,
          'writeFieldsCount': updatedFields.length,
          'capabilityBill': canUseBill,
          'capabilitySector': canUseSector,
          'previousSectorId': originalPlate.sectorId,
          'previousSectorName': originalPlate.sectorName,
          'selectedSectorId': canUseSector && hasSector ? normalizedSectorId : null,
          'selectedSectorName':
              canUseSector && hasSector ? normalizedSectorName : null,
        },
        tags: const <String>[
          _tPlate,
          _tPlateDouble,
          _tPlateModify,
          _tPlateRepo,
        ],
      );
      _debug('update=failed error=$e');
      rethrow;
    }
  }

  static Future<gcs.StorageApi> _storage() async {
    try {
      final client = await GoogleAuthSession.instance.safeClient();
      return gcs.StorageApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'DoubleModifyPlateService._storage',
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

  static Future<List<String>> listPlateImages({
    required BuildContext context,
    required String plateNumber,
    String? yearMonth,
  }) async {
    const bucketName = AuthConfig.gcsBucketName;
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
        tag: 'DoubleModifyPlateService.listPlateImages',
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
          if (name != null &&
              name.endsWith('.jpg') &&
              name.contains(plateNumber)) {
            urls.add('https://storage.googleapis.com/$bucketName/$name');
          }
        }
        pageToken = res.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      return urls;
    } catch (e) {
      await _logApiError(
        tag: 'DoubleModifyPlateService.listPlateImages',
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
