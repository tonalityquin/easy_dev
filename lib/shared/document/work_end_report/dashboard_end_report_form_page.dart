import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/auth/gcs_uploader.dart';
import '../../../app/config/email_config.dart';
import '../../../app/models/capability.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dashboard/data/repositories/end_work_report_firestore_repository.dart';
import '../../../features/dashboard/domain/models/end_work_report_history_type.dart';
import '../../../features/dashboard/domain/models/end_work_sector_metrics.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/dev/debug/debug_api_logger.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../plate/domain/models/plate_model.dart';
import '../../plate/domain/services/plate_count_service.dart';
import '../../secondary/widgets/ops_console_widgets.dart';
import '../../utils/gmail_pdf_mailer.dart';

class SingleEndWorkReportResult {
  final String division;
  final String area;
  final int vehicleOutputManual;
  final int snapshotLockedVehicleCount;
  final num snapshotTotalLockedFee;
  final bool sectorEnabled;
  final EndWorkSectorMetrics? sectorMetrics;

  final bool cleanupOk;
  final bool firestoreSaveOk;
  final bool plateOutLogOk;

  final bool gcsLogsUploadOk;
  final bool gcsObjectVerified;
  final bool cleanupSkipped;

  final String? logsUrl;
  final String submissionId;
  final bool duplicateSubmissionPrevented;

  const SingleEndWorkReportResult({
    required this.division,
    required this.area,
    required this.vehicleOutputManual,
    required this.snapshotLockedVehicleCount,
    required this.snapshotTotalLockedFee,
    required this.sectorEnabled,
    required this.sectorMetrics,
    required this.cleanupOk,
    required this.firestoreSaveOk,
    required this.plateOutLogOk,
    required this.gcsLogsUploadOk,
    required this.gcsObjectVerified,
    required this.cleanupSkipped,
    required this.logsUrl,
    required this.submissionId,
    required this.duplicateSubmissionPrevented,
  });
}

class SingleEndWorkReportService {
  final EndWorkReportFirestoreRepository _repo;

  SingleEndWorkReportService({EndWorkReportFirestoreRepository? repo})
      : _repo = repo ?? EndWorkReportFirestoreRepository();

  static const String _tEnd = 'end_report';
  static const String _tEndService = 'end_report/service';
  static const String _tEndFirestore = 'end_report/firestore';
  static const String _tEndGcsLogs = 'end_report/gcs/logs';
  static const String _tEndCleanup = 'end_report/cleanup';
  static const String _tEndPlates = 'end_report/plates';
  static const String _tEndPlateOutLog = 'end_report/plate_out_log';

  Future<void> _logApiError({
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

  Map<String, dynamic> _csvPlateData(
    Map<String, dynamic> source, {
    required bool sectorEnabled,
  }) {
    final data = Map<String, dynamic>.from(source);
    if (sectorEnabled) {
      data.putIfAbsent(PlateFields.sectorId, () => '');
      data.putIfAbsent(PlateFields.sectorName, () => '');
    } else {
      data.remove(PlateFields.sectorId);
      data.remove(PlateFields.sectorName);
    }
    return EndWorkReportFirestoreRepository.jsonSafe(data);
  }

  Future<SingleEndWorkReportResult> submitEndReport({
    required String division,
    required String area,
    required String userName,
    required int vehicleOutputManual,
    required bool sectorEnabled,
    required String submissionId,
    DeveloperOperationTrace? trace,
  }) async {
    dev.log(
      '[END] submitEndReport start: division=$division, area=$area, user=$userName, sectorEnabled=$sectorEnabled, submissionId=$submissionId',
      name: 'SingleEndWorkReportService',
    );
    trace?.log(
      'service=start division=$division area=$area user=$userName '
      'sectorEnabled=$sectorEnabled submissionId=$submissionId',
      progress: .16,
    );

    List<LockedPlateRecord> plates;
    try {
      dev.log('[END] query plates...', name: 'SingleEndWorkReportService');
      plates = await _repo.fetchLockedDepartureCompletedPlates(area: area);
    } catch (e, st) {
      dev.log(
        '[END] plates query failed',
        name: 'SingleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SingleEndWorkReportService.submitEndReport',
        message: '출차 스냅샷(locked departure completed) 조회 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'user': userName,
        },
        tags: const <String>[_tEndService, _tEndPlates, _tEnd],
      );

      throw Exception('출차 스냅샷 조회 실패: $e');
    }

    final int snapshotLockedVehicleCount = plates.length;
    trace?.log(
      'plates=fetched count=$snapshotLockedVehicleCount',
      progress: .28,
    );

    num snapshotTotalLockedFee = 0;
    EndWorkSectorMetrics? sectorMetrics;
    try {
      final grouped = <String, _MutableEndWorkSectorMetric>{};
      var assignedVehicleCount = 0;
      num assignedLockedFee = 0;
      var unassignedVehicleCount = 0;
      num unassignedLockedFee = 0;
      var invalidSectorVehicleCount = 0;
      num invalidSectorLockedFee = 0;

      for (final p in plates) {
        final data = p.data;
        num? fee = data['lockedFeeAmount'] is num
            ? data['lockedFeeAmount'] as num
            : null;

        if (fee == null) {
          final logs = data['logs'];
          if (logs is List) {
            for (final log in logs) {
              if (log is Map && log['lockedFee'] is num) {
                fee = log['lockedFee'] as num;
              }
            }
          }
        }

        final resolvedFee = fee ?? 0;
        snapshotTotalLockedFee += resolvedFee;

        if (!sectorEnabled) continue;

        final sectorId = data[PlateFields.sectorId]?.toString().trim() ?? '';
        final sectorName = data[PlateFields.sectorName]?.toString().trim() ?? '';
        final hasId = sectorId.isNotEmpty;
        final hasName = sectorName.isNotEmpty;
        if (!hasId && !hasName) {
          unassignedVehicleCount++;
          unassignedLockedFee += resolvedFee;
          continue;
        }

        if (hasId != hasName) {
          invalidSectorVehicleCount++;
          invalidSectorLockedFee += resolvedFee;
          trace?.log(
            'sector=invalid plateDocId=${p.docId} sectorId=$sectorId '
            'sectorName=$sectorName fee=$resolvedFee',
            progress: .34,
          );
          continue;
        }

        assignedVehicleCount++;
        assignedLockedFee += resolvedFee;
        final key = '$sectorId\u0000$sectorName';
        final target = grouped.putIfAbsent(
          key,
          () => _MutableEndWorkSectorMetric(
            sectorId: sectorId,
            sectorName: sectorName,
          ),
        );
        target.vehicleCount++;
        target.totalLockedFee += resolvedFee;
      }

      if (sectorEnabled) {
        final items = grouped.values
            .map(
              (item) => EndWorkSectorMetricItem(
                sectorId: item.sectorId,
                sectorName: item.sectorName,
                vehicleCount: item.vehicleCount,
                totalLockedFee: item.totalLockedFee,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byCount = b.vehicleCount.compareTo(a.vehicleCount);
            if (byCount != 0) return byCount;
            final byName = a.sectorName.compareTo(b.sectorName);
            if (byName != 0) return byName;
            return a.sectorId.compareTo(b.sectorId);
          });

        sectorMetrics = EndWorkSectorMetrics(
          enabled: true,
          sectorCount: items.length,
          assignedVehicleCount: assignedVehicleCount,
          assignedLockedFee: assignedLockedFee,
          unassignedVehicleCount: unassignedVehicleCount,
          unassignedLockedFee: unassignedLockedFee,
          invalidSectorVehicleCount: invalidSectorVehicleCount,
          invalidSectorLockedFee: invalidSectorLockedFee,
          legacyFeeClassification: false,
          items: List<EndWorkSectorMetricItem>.unmodifiable(items),
        );
      }
    } catch (e, st) {
      dev.log(
        '[END] fee and sector aggregation failed',
        name: 'SingleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SingleEndWorkReportService.submitEndReport',
        message: '요금 및 방문 구역 집계 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'platesCount': plates.length,
          'sectorEnabled': sectorEnabled,
        },
        tags: const <String>[_tEndService, _tEnd],
      );

      throw Exception('요금 및 방문 구역 집계 실패: $e');
    }

    trace?.log(
      'aggregate lockedVehicles=$snapshotLockedVehicleCount '
      'lockedFee=$snapshotTotalLockedFee '
      'sectorCount=${sectorMetrics?.sectorCount ?? 0} '
      'assigned=${sectorMetrics?.assignedVehicleCount ?? 0} '
      'unassigned=${sectorMetrics?.unassignedVehicleCount ?? 0} '
      'invalid=${sectorMetrics?.invalidSectorVehicleCount ?? 0} '
      'invalidFee=${sectorMetrics?.invalidSectorLockedFee ?? 0}',
      progress: .42,
    );

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = DateFormat('yyyyMM').format(now);

    final reportLog = <String, dynamic>{
      'division': division,
      'area': area,
      'vehicleCount': <String, dynamic>{
        'vehicleOutput': vehicleOutputManual,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
        if (sectorMetrics != null) 'sector': sectorMetrics.toMap(),
      },
      'createdAt': now.toIso8601String(),
      'uploadedBy': userName,
    };

    String? logsUrl;
    GcsCsvUploadReceipt? logsReceipt;
    bool gcsLogsUploadOk = true;
    bool gcsObjectVerified = false;
    try {
      dev.log('[END] upload logs...', name: 'SingleEndWorkReportService');

      final items = <Map<String, dynamic>>[
        for (final p in plates)
          <String, dynamic>{
            'docId': p.docId,
            'data': _csvPlateData(
              p.data,
              sectorEnabled: sectorEnabled,
            ),
          },
      ];
      trace?.log(
        'csv=prepare items=${items.length} sectorColumns=$sectorEnabled',
        progress: .5,
      );

      logsReceipt = await uploadEndLogCsvWithReceipt(
        report: <String, dynamic>{
          'division': division,
          'area': area,
          'sectorEnabled': sectorEnabled,
          'items': items,
        },
        division: division,
        area: area,
        userName: userName,
        submissionId: submissionId,
      );
      logsUrl = logsReceipt.url;
      gcsObjectVerified = logsReceipt.verified;
      gcsLogsUploadOk = logsReceipt.verified &&
          logsReceipt.sourceVehicleCount == plates.length &&
          logsReceipt.uniqueDocumentCount == plates.length;

      trace?.log(
        'csv=uploaded object=${logsReceipt.objectName} '
        'bytes=${logsReceipt.remoteByteSize}/${logsReceipt.byteSize} '
        'vehicles=${logsReceipt.uniqueDocumentCount}/${plates.length} '
        'rows=${logsReceipt.csvDataRowCount} '
        'sectorColumns=${logsReceipt.sectorColumnsVerified}/${logsReceipt.sectorColumnsRequired} '
        'verified=${logsReceipt.verified}',
        progress: .58,
      );

      if (!gcsLogsUploadOk) {
        dev.log(
          '[END] upload logs verification failed',
          name: 'SingleEndWorkReportService',
        );

        await _logApiError(
          tag: 'SingleEndWorkReportService.submitEndReport',
          message: 'GCS(/logs) 업로드 무결성 검증 실패',
          error: Exception('gcs receipt verification failed'),
          extra: <String, dynamic>{
            'division': division,
            'area': area,
            'itemsCount': plates.length,
            'objectName': logsReceipt.objectName,
            'byteSize': logsReceipt.byteSize,
            'remoteByteSize': logsReceipt.remoteByteSize,
            'uniqueDocumentCount': logsReceipt.uniqueDocumentCount,
            'csvDataRowCount': logsReceipt.csvDataRowCount,
            'sectorColumnsRequired': logsReceipt.sectorColumnsRequired,
            'sectorColumnsVerified': logsReceipt.sectorColumnsVerified,
            'verified': logsReceipt.verified,
          },
          tags: const <String>[_tEndService, _tEndGcsLogs, _tEnd],
        );
      }
    } catch (e, st) {
      gcsLogsUploadOk = false;
      gcsObjectVerified = false;
      dev.log(
        '[END] upload logs exception',
        name: 'SingleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SingleEndWorkReportService.submitEndReport',
        message: 'GCS(/logs) 업로드 예외',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'platesCount': plates.length,
        },
        tags: const <String>[_tEndService, _tEndGcsLogs, _tEnd],
      );
    }

    bool firestoreSaveOk = true;
    bool duplicateSubmissionPrevented = false;
    try {
      dev.log(
        '[END] save report to Firestore (monthly document + reports map)...',
        name: 'SingleEndWorkReportService',
      );

      trace?.log(
        'firestore=end_work_reports start '
        'reportType=${EndWorkReportHistoryTypes.detailedGcsEndReport} '
        'gcsLogVerified=$gcsLogsUploadOk '
        'logsLinked=${logsUrl?.trim().isNotEmpty == true} '
        'sectorMetrics=${sectorMetrics != null}',
        progress: .62,
      );
      final insertedSubmission = await _repo.saveMonthlyEndWorkReport(
        division: division,
        area: area,
        monthKey: monthKey,
        dateStr: dateStr,
        vehicleCount: (reportLog['vehicleCount'] as Map<String, dynamic>),
        metrics: (reportLog['metrics'] as Map<String, dynamic>),
        createdAtIso: reportLog['createdAt'] as String,
        uploadedBy: userName,
        gcsLogVerified: gcsLogsUploadOk,
        submissionId: submissionId,
        logsUrl: logsUrl,
        gcsObjectName: logsReceipt?.objectName,
        gcsGeneration: logsReceipt?.generation,
        gcsMd5Hash: logsReceipt?.md5Hash,
        gcsByteSize: logsReceipt?.remoteByteSize,
      );
      duplicateSubmissionPrevented = !insertedSubmission;
      trace?.log(
        'firestore=end_work_reports saved submissionId=$submissionId inserted=$insertedSubmission '
        'reportType=${EndWorkReportHistoryTypes.detailedGcsEndReport} '
        'gcsLogVerified=$gcsLogsUploadOk',
        progress: .68,
      );
    } catch (e, st) {
      firestoreSaveOk = false;
      dev.log(
        '[END] Firestore save failed (end_work_reports monthly doc + reports map)',
        name: 'SingleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SingleEndWorkReportService.submitEndReport',
        message: 'Firestore(end_work_reports) 저장 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'monthKey': monthKey,
          'dateStr': dateStr,
          'logsUrl': logsUrl,
        },
        tags: const <String>[_tEndService, _tEndFirestore, _tEnd],
      );
    }

    bool plateOutLogOk = true;
    try {
      dev.log('[END] append plate_out_log...', name: 'SingleEndWorkReportService');

      trace?.log(
        'plate_out_log=start count=${plates.length} sectorEnabled=$sectorEnabled',
        progress: .72,
      );
      await _repo.appendPlateOutLogs(
        area: area,
        plates: plates,
        sectorEnabled: sectorEnabled,
        submissionId: submissionId,
        onLog: (message) {
          trace?.log(message, progress: .8);
        },
      );
      trace?.log(
        'plate_out_log=completed count=${plates.length}',
        progress: .82,
      );
    } catch (e, st) {
      plateOutLogOk = false;
      dev.log(
        '[END] plate_out_log append failed',
        name: 'SingleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SingleEndWorkReportService.submitEndReport',
        message: 'plate_out_log 저장 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'plateDocCount': plates.length,
        },
        tags: const <String>[_tEndService, _tEndPlateOutLog, _tEnd],
      );
    }

    final canCleanup = gcsLogsUploadOk &&
        gcsObjectVerified &&
        firestoreSaveOk &&
        plateOutLogOk;
    bool cleanupOk = true;
    bool cleanupSkipped = false;
    trace?.log(
      'cleanupGate gcs=$gcsLogsUploadOk verified=$gcsObjectVerified '
      'firestore=$firestoreSaveOk plateOutLog=$plateOutLogOk '
      'canCleanup=$canCleanup',
      progress: .84,
    );
    if (canCleanup) {
      try {
        dev.log('[END] cleanup plates & plate_counters...',
            name: 'SingleEndWorkReportService');

        trace?.log(
          'cleanup=start plates=${plates.length} counter=departureCompletedEvents',
          progress: .86,
        );
        await _repo.cleanupLockedDepartureCompletedPlates(
          area: area,
          plateDocIds: plates.map((e) => e.docId).toList(),
        );
        trace?.log(
          'cleanup=completed plates=${plates.length} counterReset=true',
          progress: .94,
        );
      } catch (e, st) {
        cleanupOk = false;
        dev.log(
          '[END] cleanup failed',
          name: 'SingleEndWorkReportService',
          error: e,
          stackTrace: st,
        );

        await _logApiError(
          tag: 'SingleEndWorkReportService.submitEndReport',
          message: 'cleanup(plates/plate_counters) 실패',
          error: e,
          extra: <String, dynamic>{
            'division': division,
            'area': area,
            'plateDocCount': plates.length,
          },
          tags: const <String>[_tEndService, _tEndCleanup, _tEnd],
        );
      }
    } else {
      cleanupOk = false;
      cleanupSkipped = true;
      trace?.log(
        'cleanup=skipped 원본 보호를 위해 필수 저장 단계가 모두 성공하지 않았습니다.',
        progress: .94,
      );
      dev.log(
        '[END] cleanup skipped for source protection',
        name: 'SingleEndWorkReportService',
      );
    }
    dev.log('[END] submitEndReport done', name: 'SingleEndWorkReportService');

    return SingleEndWorkReportResult(
      division: division,
      area: area,
      vehicleOutputManual: vehicleOutputManual,
      snapshotLockedVehicleCount: snapshotLockedVehicleCount,
      snapshotTotalLockedFee: snapshotTotalLockedFee,
      sectorEnabled: sectorEnabled,
      sectorMetrics: sectorMetrics,
      cleanupOk: cleanupOk,
      firestoreSaveOk: firestoreSaveOk,
      plateOutLogOk: plateOutLogOk,
      gcsLogsUploadOk: gcsLogsUploadOk,
      gcsObjectVerified: gcsObjectVerified,
      cleanupSkipped: cleanupSkipped,
      logsUrl: logsUrl,
      submissionId: submissionId,
      duplicateSubmissionPrevented: duplicateSubmissionPrevented,
    );
  }
}

class _MutableEndWorkSectorMetric {
  final String sectorId;
  final String sectorName;
  int vehicleCount = 0;
  num totalLockedFee = 0;

  _MutableEndWorkSectorMetric({
    required this.sectorId,
    required this.sectorName,
  });
}

Future<void> showDashboardEndReportSideDock({
  required BuildContext context,
}) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[DashboardEndReportDock] route_push reduceMotion=$reduceMotion motion=operations_210_190',
  );
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: true,
    barrierLabel: '업무 종료 보고',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: false,
    builder: (_) => const DashboardEndReportSideDock(),
  );
  debugPrint('[DashboardEndReportDock] route_closed');
}

class DashboardEndReportSideDock extends StatefulWidget {
  const DashboardEndReportSideDock({super.key});

  @override
  State<DashboardEndReportSideDock> createState() =>
      _DashboardEndReportSideDockState();
}

class _DashboardEndReportSideDockState
    extends State<DashboardEndReportSideDock> {
  static const String _tEnd = 'end_report';
  static const String _tEndUi = 'end_report/ui';
  static const String _tEndCounts = 'end_report/counts';
  static const String _tEndFirst = 'end_report/first_submit';
  static const String _tEndMail = 'end_report/mail';
  static const String _tEndPdf = 'end_report/pdf';
  static const String _tPrefs = 'prefs';
  static const String _tGmailSend = 'gmail/send';
  static const String _prefEndDraftVehicleCount =
      'end_report_draft_vehicle_count';
  static const String _prefEndDraftHasSpecialNote =
      'end_report_draft_has_special_note';
  static const String _prefEndDraftContent = 'end_report_draft_content';
  static const String _prefEndSubmissionId = 'end_report_active_submission_id';
  static const String _prefEndSubmissionArea =
      'end_report_active_submission_area';
  static const String _prefEndSubmissionDate =
      'end_report_active_submission_date';
  static const String _prefEndSubmissionUser =
      'end_report_active_submission_user';
  static const int _maxDebugLines = 220;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _specialNoteKey = GlobalKey();
  final GlobalKey _contentFieldKey = GlobalKey();
  final TextEditingController _contentCtrl = TextEditingController();
  final FocusNode _contentNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final PlateCountService _plateCountService = PlateCountService();
  final List<String> _debugLines = <String>[];

  bool? _hasSpecialNote;
  String? _selectedArea;
  String _recipient = '';
  bool _recipientValid = false;
  String _mailSubject = '';
  String _mailBody = '';
  DateTime _createdAt = DateTime.now();

  bool _initializing = true;
  bool _draftLoaded = false;
  bool _firstSubmitting = false;
  bool _firstSubmittedCompleted = false;
  bool _sending = false;
  bool _developerMode = false;
  bool _specialNoteInvalid = false;
  bool _contentInvalid = false;

  SingleEndWorkReportResult? _firstSubmitResult;
  String? _activeEndSubmissionId;
  String? _activeEndSubmissionArea;
  String? _activeEndSubmissionDate;
  String? _activeEndSubmissionUser;

  int _sysVehicleOutput = 0;
  int _sysDepartureExtra = 0;
  String _firstSubmitStage = 'idle';
  String _submitStage = 'idle';
  String _lastFailure = '';

  int get _sysDepartureTotal => _sysVehicleOutput + _sysDepartureExtra;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _firstSubmitPartial {
    final result = _firstSubmitResult;
    if (result == null) return false;
    return !result.cleanupOk ||
        !result.firestoreSaveOk ||
        !result.plateOutLogOk ||
        !result.gcsLogsUploadOk;
  }

  String get _firstSubmitStatusLabel {
    if (_firstSubmitting) return '제출 중';
    if (!_firstSubmittedCompleted) return '미제출';
    return _firstSubmitPartial ? '부분 완료' : '완료';
  }

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_onDeveloperModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_onDeveloperModeChanged);
    _contentCtrl.dispose();
    _contentNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDeveloperModeChanged() {
    if (!mounted) return;
    final next = DevAuth.devModeEnabled.value;
    if (next == _developerMode) return;
    setState(() => _developerMode = next);
    _recordDebug('developer_mode_changed enabled=$next');
  }

  void _recordDebug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
    final line = '[$stamp] [DashboardEndReportDock] $normalized';
    _debugLines.add(line);
    if (_debugLines.length > _maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - _maxDebugLines);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[DashboardEndReportDock] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _logApiError({
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

  Future<void> _initialize() async {
    _recordDebug('initialize_start');
    try {
      final devMode = await DevAuth.isDevModeEnabled();
      await _loadSelectedArea();
      await _loadDraft();
      await _loadRecipient();
      await _loadSystemVehicleCount();
      _createdAt = DateTime.now();
      _updateMailContent(forceBody: true);
      if (!mounted) return;
      setState(() {
        _developerMode = devMode;
        _initializing = false;
        _draftLoaded = true;
      });
      _recordDebug(
        'initialize_complete area=${_resolveReportArea()} departure=$_sysVehicleOutput extra=$_sysDepartureExtra total=$_sysDepartureTotal special=${_hasSpecialNote ?? 'unset'} recipientValid=$_recipientValid',
      );
    } catch (error, stackTrace) {
      _recordDebug('initialize_failure error=$error');
      _recordDebug('initialize_failure_stack\n$stackTrace');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._initialize',
        message: '업무 종료 보고 초기화 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tEndUi, _tEnd],
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _lastFailure = 'initialize';
      });
      await StatusDialog.showFailure(
        context,
        title: '업무 종료 보고 초기화 실패',
        useCommonUi: true,
      );
      if (_developerMode && mounted) {
        await _showDeveloperStatus(failure: true);
      }
    }
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      _selectedArea = area.trim().isEmpty ? null : area.trim();
      _recordDebug(
        'area_loaded fallbackConfigured=${(_selectedArea ?? '').isNotEmpty}',
      );
    } catch (error, stackTrace) {
      _selectedArea = null;
      _recordDebug('area_load_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._loadSelectedArea',
        message: 'SharedPreferences selectedArea 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _loadSystemVehicleCount() async {
    try {
      final areaState = context.read<AreaState>();
      final area = areaState.currentArea.trim();
      if (area.isEmpty) {
        _recordDebug('counts_load_skipped reason=empty_current_area');
        return;
      }
      final results = await Future.wait<int>(<Future<int>>[
        _plateCountService.getDepartureCompletedAggCount(area),
        _plateCountService.getDepartureCompletedExtraCount(area),
      ]);
      _sysVehicleOutput = results[0];
      _sysDepartureExtra = results[1];
      _recordDebug(
        'counts_loaded departure=$_sysVehicleOutput extra=$_sysDepartureExtra total=$_sysDepartureTotal',
      );
    } catch (error, stackTrace) {
      _recordDebug('counts_load_failure error=$error');
      dev.log(
        '[END][Dashboard] loadSystemVehicleCount failed',
        name: 'DashboardEndReportSideDock',
        error: error,
        stackTrace: stackTrace,
      );
      await _logApiError(
        tag: 'DashboardEndReportSideDock._loadSystemVehicleCount',
        message: '시스템 집계 로드 실패',
        error: error,
        extra: <String, dynamic>{
          'sysVehicleOutput': _sysVehicleOutput,
          'sysDepartureExtra': _sysDepartureExtra,
          'stack': stackTrace.toString(),
        },
        tags: const <String>[_tEndCounts, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSpecialNote = prefs.getBool(_prefEndDraftHasSpecialNote);
      final content = prefs.getString(_prefEndDraftContent) ?? '';
      final submissionId = prefs.getString(_prefEndSubmissionId) ?? '';
      final submissionArea = prefs.getString(_prefEndSubmissionArea) ?? '';
      final submissionDate = prefs.getString(_prefEndSubmissionDate) ?? '';
      final submissionUser = prefs.getString(_prefEndSubmissionUser) ?? '';
      _hasSpecialNote = hasSpecialNote;
      _contentCtrl.text = hasSpecialNote == false ? '' : content;
      _activeEndSubmissionId =
          submissionId.trim().isEmpty ? null : submissionId.trim();
      _activeEndSubmissionArea =
          submissionArea.trim().isEmpty ? null : submissionArea.trim();
      _activeEndSubmissionDate =
          submissionDate.trim().isEmpty ? null : submissionDate.trim();
      _activeEndSubmissionUser =
          submissionUser.trim().isEmpty ? null : submissionUser.trim();
      _recordDebug(
        'draft_load_complete special=${_hasSpecialNote ?? 'unset'} contentLen=${_contentCtrl.text.trim().length} activeSubmission=${_activeEndSubmissionId != null}',
      );
    } catch (error, stackTrace) {
      _recordDebug('draft_load_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._loadDraft',
        message: '업무 종료 보고 임시저장 데이터 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefEndDraftVehicleCount);
      if (_hasSpecialNote == null) {
        await prefs.remove(_prefEndDraftHasSpecialNote);
      } else {
        await prefs.setBool(_prefEndDraftHasSpecialNote, _hasSpecialNote!);
      }
      final content = _contentCtrl.text.trim();
      if (content.isEmpty) {
        await prefs.remove(_prefEndDraftContent);
      } else {
        await prefs.setString(_prefEndDraftContent, content);
      }
      if ((_activeEndSubmissionId ?? '').trim().isEmpty) {
        await prefs.remove(_prefEndSubmissionId);
        await prefs.remove(_prefEndSubmissionArea);
        await prefs.remove(_prefEndSubmissionDate);
        await prefs.remove(_prefEndSubmissionUser);
      } else {
        await prefs.setString(
          _prefEndSubmissionId,
          _activeEndSubmissionId!.trim(),
        );
        await prefs.setString(
          _prefEndSubmissionArea,
          (_activeEndSubmissionArea ?? '').trim(),
        );
        await prefs.setString(
          _prefEndSubmissionDate,
          (_activeEndSubmissionDate ?? '').trim(),
        );
        await prefs.setString(
          _prefEndSubmissionUser,
          (_activeEndSubmissionUser ?? '').trim(),
        );
      }
    } catch (error, stackTrace) {
      _recordDebug('draft_persist_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._persistDraft',
        message: '업무 종료 보고 임시저장 실패',
        error: error,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'stack': stackTrace.toString(),
        },
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefEndDraftVehicleCount);
      await prefs.remove(_prefEndDraftHasSpecialNote);
      await prefs.remove(_prefEndDraftContent);
      await prefs.remove(_prefEndSubmissionId);
      await prefs.remove(_prefEndSubmissionArea);
      await prefs.remove(_prefEndSubmissionDate);
      await prefs.remove(_prefEndSubmissionUser);
      _recordDebug('draft_clear_complete');
    } catch (error, stackTrace) {
      _recordDebug('draft_clear_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._clearDraft',
        message: '업무 종료 보고 임시저장 삭제 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _loadRecipient() async {
    try {
      final config = await EmailConfig.load();
      _recipient = config.to.trim();
      _recipientValid = EmailConfig.isValidToList(_recipient);
      _recordDebug(
        'recipient_loaded configured=${_recipient.isNotEmpty} valid=$_recipientValid count=${_recipientCount(_recipient)}',
      );
    } catch (error, stackTrace) {
      _recipient = '';
      _recipientValid = false;
      _recordDebug('recipient_load_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._loadRecipient',
        message: '업무 종료 보고 수신처 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tEndMail, _tEndUi, _tEnd],
      );
    }
  }

  int _recipientCount(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .length;
  }

  String _resolveReportArea() {
    try {
      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea.isNotEmpty) return currentArea;
    } catch (_) {}
    final selectedArea = (_selectedArea ?? '').trim();
    if (selectedArea.isNotEmpty) return selectedArea;
    return '업무';
  }

  String _fmtCompact(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _dateTag(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String _createEndSubmissionId({
    required String area,
    required String userName,
  }) {
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMddHHmmssSSS').format(now);
    final areaHash = area.hashCode.abs();
    final userHash = userName.hashCode.abs();
    return '${stamp}_${areaHash}_$userHash';
  }

  void _updateMailContent({bool forceBody = false}) {
    final now = _createdAt;
    final suffix = _hasSpecialNote == null
        ? ''
        : _hasSpecialNote!
            ? ' - 특이사항 있음'
            : ' - 특이사항 없음';
    final area = _resolveReportArea();
    _mailSubject =
        '$area 업무 종료 보고서 – ${now.month}월 ${now.day}일자 ${_sysDepartureTotal}대$suffix';
    if (forceBody || _mailBody.trim().isEmpty) {
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      _mailBody =
          '본 보고서는 ${now.year}년 ${now.month}월 ${now.day}일 ${hh}시 ${mm}분 기준으로 작성된 업무 종료 보고서입니다.';
    }
  }

  Future<void> _setSpecialNote(bool value) async {
    if (_sending || _firstSubmitting || _initializing) return;
    if (!_firstSubmittedCompleted) return;
    if (_hasSpecialNote == value && !_specialNoteInvalid) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _hasSpecialNote = value;
      _specialNoteInvalid = false;
      _contentInvalid = false;
      if (!value) {
        _contentCtrl.clear();
      }
      _createdAt = DateTime.now();
      _mailBody = '';
      _updateMailContent(forceBody: true);
    });
    _recordDebug(
      'special_note_changed value=$value contentCleared=${!value}',
    );
    await _persistDraft();
  }

  Future<void> _reset() async {
    if (_sending || _firstSubmitting || _initializing) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _contentCtrl.clear();
    await _clearDraft();
    if (!mounted) return;
    setState(() {
      _hasSpecialNote = null;
      _firstSubmittedCompleted = false;
      _firstSubmitResult = null;
      _activeEndSubmissionId = null;
      _activeEndSubmissionArea = null;
      _activeEndSubmissionDate = null;
      _activeEndSubmissionUser = null;
      _specialNoteInvalid = false;
      _contentInvalid = false;
      _firstSubmitStage = 'idle';
      _submitStage = 'idle';
      _lastFailure = '';
      _createdAt = DateTime.now();
      _mailBody = '';
      _updateMailContent(forceBody: true);
    });
    _recordDebug('reset_complete');
    await HapticFeedback.selectionClick();
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
        curve: CommonUiMotion.enter,
      );
    }
  }

  Future<void> _ensureVisible(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: .18,
    );
  }

  Future<bool> _validateFinalSubmit() async {
    if (!_firstSubmittedCompleted) {
      _recordDebug('validation_failure reason=first_submit_required');
      await HapticFeedback.heavyImpact();
      return false;
    }
    if (_hasSpecialNote == null) {
      setState(() => _specialNoteInvalid = true);
      _recordDebug('validation_failure reason=special_note_unselected');
      await HapticFeedback.heavyImpact();
      await _ensureVisible(_specialNoteKey);
      return false;
    }
    if (_hasSpecialNote == true && _contentCtrl.text.trim().isEmpty) {
      setState(() => _contentInvalid = true);
      _recordDebug('validation_failure reason=detail_empty');
      await HapticFeedback.heavyImpact();
      _contentNode.requestFocus();
      await _ensureVisible(_contentFieldKey);
      return false;
    }
    if (!_recipientValid) {
      _recordDebug('validation_failure reason=invalid_recipient');
      await _handleFailure(
        reason: 'invalid_recipient',
        error: StateError('invalid_recipient'),
        stackTrace: StackTrace.current,
        title: '업무 종료 보고 제출 실패',
      );
      return false;
    }
    return true;
  }

  Future<void> _submitFirstEndReport() async {
    if (_firstSubmitting || _sending || _initializing) return;

    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    final area = areaState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    final userName = userState.name.trim();
    final sectorEnabled = areaState.capabilitiesOfCurrentArea.contains(
      Capability.sector,
    );

    if (area.isEmpty || division.isEmpty || userName.isEmpty) {
      final error = StateError('missing_context');
      _recordDebug(
        'first_submit_failure reason=missing_context areaConfigured=${area.isNotEmpty} divisionConfigured=${division.isNotEmpty} userConfigured=${userName.isNotEmpty}',
      );
      await _logApiError(
        tag: 'DashboardEndReportSideDock._submitFirstEndReport',
        message: '근무 지역/부문/사용자 정보 부족으로 1차 제출 불가',
        error: error,
        extra: <String, dynamic>{
          'areaConfigured': area.isNotEmpty,
          'divisionConfigured': division.isNotEmpty,
          'userNameLen': userName.length,
          'sectorEnabled': sectorEnabled,
        },
        tags: const <String>[_tEndFirst, _tEndUi, _tEnd],
      );
      if (!mounted) return;
      await StatusDialog.showFailure(
        context,
        title: '업무 종료 1차 제출 실패',
        useCommonUi: true,
      );
      if (_developerMode && mounted) {
        await _showDeveloperStatus(failure: true);
      }
      return;
    }

    setState(() {
      _firstSubmitting = true;
      _lastFailure = '';
      _firstSubmitStage = 'prepare';
    });
    _recordDebug(
      'first_submit_start area=$area departure=$_sysVehicleOutput extra=$_sysDepartureExtra total=$_sysDepartureTotal sectorEnabled=$sectorEnabled retry=${_firstSubmitResult != null}',
    );
    DeveloperOperationTrace? trace;

    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '업무 종료 보고 1차 제출',
        initialMessage: '출차 마감 데이터와 방문 구역 집계를 준비하고 있습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 단계별 로그를 debugPrint 코드로 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF: 단계별 로그를 콘솔에 기록합니다.',
      );

      final vehicleOutputManual = _sysDepartureTotal;
      trace.log(
        'context area=$area division=$division user=$userName capability.sector=$sectorEnabled',
        progress: .06,
      );
      trace.log(
        'counts departure=$_sysVehicleOutput extra=$_sysDepartureExtra vehicleOutput=$vehicleOutputManual',
        progress: .1,
      );

      final submissionDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_activeEndSubmissionId == null ||
          _activeEndSubmissionArea != area ||
          _activeEndSubmissionDate != submissionDate ||
          _activeEndSubmissionUser != userName) {
        _activeEndSubmissionId = _createEndSubmissionId(
          area: area,
          userName: userName,
        );
        _activeEndSubmissionArea = area;
        _activeEndSubmissionDate = submissionDate;
        _activeEndSubmissionUser = userName;
        await _persistDraft();
      }
      final submissionId = _activeEndSubmissionId!;
      trace.log(
        'submissionId=$submissionId retry=${_firstSubmitResult != null}',
        progress: .12,
      );

      _firstSubmitStage = 'service';
      final service = SingleEndWorkReportService();
      final result = await service.submitEndReport(
        division: division,
        area: area,
        userName: userName,
        vehicleOutputManual: vehicleOutputManual,
        sectorEnabled: sectorEnabled,
        submissionId: submissionId,
        trace: trace,
      );

      final partialFailure = !result.cleanupOk ||
          !result.firestoreSaveOk ||
          !result.plateOutLogOk ||
          !result.gcsLogsUploadOk;

      trace.log(
        'result cleanupOk=${result.cleanupOk} cleanupSkipped=${result.cleanupSkipped} firestoreSaveOk=${result.firestoreSaveOk} plateOutLogOk=${result.plateOutLogOk} gcsLogsUploadOk=${result.gcsLogsUploadOk} gcsObjectVerified=${result.gcsObjectVerified} submissionId=${result.submissionId} duplicatePrevented=${result.duplicateSubmissionPrevented}',
        progress: .97,
      );
      trace.log(
        'sector enabled=${result.sectorEnabled} sectorCount=${result.sectorMetrics?.sectorCount ?? 0} assigned=${result.sectorMetrics?.assignedVehicleCount ?? 0} unassigned=${result.sectorMetrics?.unassignedVehicleCount ?? 0} invalid=${result.sectorMetrics?.invalidSectorVehicleCount ?? 0}',
        progress: .98,
      );

      if (partialFailure) {
        _firstSubmitStage = 'partial';
        await trace.fail(
          '1차 제출이 부분 완료되었습니다. 단계별 성공 여부를 확인해 주세요.',
        );
      } else {
        _activeEndSubmissionId = null;
        _activeEndSubmissionArea = null;
        _activeEndSubmissionDate = null;
        _activeEndSubmissionUser = null;
        await _persistDraft();
        _firstSubmitStage = 'complete';
        await trace.succeed(
          sectorEnabled
              ? '방문 구역 집계를 포함한 1차 제출과 마감 정리가 완료되었습니다.'
              : '방문 구역 기능이 없는 지역의 1차 제출과 마감 정리가 완료되었습니다.',
        );
      }

      if (!mounted) return;
      setState(() {
        _firstSubmittedCompleted = true;
        _firstSubmitResult = result;
        _createdAt = DateTime.now();
        _mailBody = '';
        _updateMailContent(forceBody: true);
      });
      await _persistDraft();
      _recordDebug(
        'first_submit_complete partial=$partialFailure cleanupOk=${result.cleanupOk} firestore=${result.firestoreSaveOk} plateOut=${result.plateOutLogOk} gcsUpload=${result.gcsLogsUploadOk} gcsVerified=${result.gcsObjectVerified}',
      );
      await HapticFeedback.lightImpact();

      if (partialFailure && mounted) {
        await StatusDialog.showFailure(
          context,
          title: '업무 종료 1차 제출 부분 완료',
          useCommonUi: true,
        );
      }
    } catch (error, stackTrace) {
      _firstSubmitStage = 'failure';
      _recordDebug('first_submit_failure error=$error');
      _recordDebug('first_submit_failure_stack\n$stackTrace');
      dev.log(
        '[END][Dashboard] first submit error',
        name: 'DashboardEndReportSideDock',
        error: error,
        stackTrace: stackTrace,
      );
      await _logApiError(
        tag: 'DashboardEndReportSideDock._submitFirstEndReport',
        message: '1차 업무 종료 보고 실패',
        error: error,
        extra: <String, dynamic>{
          'area': area,
          'division': division,
          'sectorEnabled': sectorEnabled,
          'stack': stackTrace.toString(),
        },
        tags: const <String>[_tEndFirst, _tEndUi, _tEnd],
      );
      if (trace != null) {
        await trace.fail(
          '업무 종료 보고 1차 제출에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (!mounted) return;
      await HapticFeedback.heavyImpact();
      await StatusDialog.showFailure(
        context,
        title: '업무 종료 1차 제출 실패',
        useCommonUi: true,
      );
      if (_developerMode && mounted) {
        await _showDeveloperStatus(failure: true);
      }
    } finally {
      if (mounted) {
        setState(() => _firstSubmitting = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_sending || _firstSubmitting || _initializing) return;
    FocusScope.of(context).unfocus();
    await _loadRecipient();
    if (!mounted) return;
    final valid = await _validateFinalSubmit();
    if (!valid || !mounted) return;

    setState(() {
      _sending = true;
      _lastFailure = '';
      _createdAt = DateTime.now();
      _mailBody = '';
      _updateMailContent(forceBody: true);
    });
    _submitStage = 'prepare';
    _recordDebug(
      'final_submit_start area=${_resolveReportArea()} total=$_sysDepartureTotal special=$_hasSpecialNote contentLen=${_contentCtrl.text.trim().length} recipientCount=${_recipientCount(_recipient)}',
    );

    try {
      final toCsv = _recipient
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .join(', ');
      final subject = _mailSubject.trim();
      final body = _mailBody.trim();
      if (subject.isEmpty) {
        throw StateError('empty_subject');
      }

      _submitStage = 'pdf_build';
      _recordDebug('pdf_build_start');
      final pdfBytes = await _buildPdfBytes();
      _recordDebug('pdf_build_complete bytes=${pdfBytes.length}');

      _submitStage = 'gmail_send';
      final filename = _safeFileName('업무종료보고서_무기명_${_dateTag(_createdAt)}');
      _recordDebug(
        'gmail_send_start recipientCount=${_recipientCount(toCsv)} subjectLen=${subject.length}',
      );
      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );
      _recordDebug('gmail_send_complete');

      _submitStage = 'draft_clear';
      await _clearDraft();
      _submitStage = 'complete';
      _recordDebug('final_submit_complete');

      if (!mounted) return;
      setState(() => _sending = false);
      await HapticFeedback.lightImpact();
      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.workEndReportSuccess,
        useCommonUi: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _sending = false);
      }
      await _handleFailure(
        reason: _submitStage,
        error: error,
        stackTrace: stackTrace,
        title: '업무 종료 보고 제출 실패',
      );
    }
  }

  Future<void> _handleFailure({
    required String reason,
    required Object error,
    required StackTrace stackTrace,
    required String title,
  }) async {
    _lastFailure = reason;
    _recordDebug('failure reason=$reason error=$error');
    _recordDebug('failure_stack reason=$reason\n$stackTrace');
    await _logApiError(
      tag: 'DashboardEndReportSideDock.$reason',
      message: title,
      error: error,
      extra: <String, dynamic>{
        'reason': reason,
        'stack': stackTrace.toString(),
        'firstSubmitted': _firstSubmittedCompleted,
        'firstPartial': _firstSubmitPartial,
        'hasSpecialNote': _hasSpecialNote,
        'contentLen': _contentCtrl.text.trim().length,
        'recipientValid': _recipientValid,
      },
      tags: const <String>[_tEndMail, _tEndUi, _tEnd, _tGmailSend],
    );
    if (!mounted) return;
    await HapticFeedback.heavyImpact();
    await StatusDialog.showFailure(
      context,
      title: title,
      useCommonUi: true,
    );
    if (_developerMode && mounted) {
      await _showDeveloperStatus(failure: true);
    }
  }

  Future<void> _showDeveloperStatus({bool failure = false}) async {
    if (!_developerMode || !mounted) return;
    final result = _firstSubmitResult;
    final sector = result?.sectorMetrics;
    _recordDebug(
      'developer_status_open failure=$failure first=$_firstSubmitStatusLabel departure=$_sysVehicleOutput extra=$_sysDepartureExtra total=$_sysDepartureTotal special=${_hasSpecialNote ?? 'unset'} sending=$_sending firstSubmitting=$_firstSubmitting recipientValid=$_recipientValid finalStage=$_submitStage lastFailure=${_lastFailure.isEmpty ? 'none' : _lastFailure}',
    );
    final description = <String>[
      '지역: ${_resolveReportArea()}',
      '출차: $_sysVehicleOutput',
      '중복 입차: $_sysDepartureExtra',
      '저장 출차 대수: $_sysDepartureTotal',
      '1차 제출 상태: $_firstSubmitStatusLabel',
      '1차 제출 단계: $_firstSubmitStage',
      '활성 submission ID: ${(_activeEndSubmissionId ?? '').isNotEmpty}',
      '특이사항: ${_hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음')}',
      '내용 길이: ${_contentCtrl.text.trim().length}',
      '임시저장 로드: $_draftLoaded',
      '초기화 중: $_initializing',
      '1차 제출 중: $_firstSubmitting',
      '최종 전송 중: $_sending',
      '수신처 유효: $_recipientValid',
      '수신처 개수: ${_recipientCount(_recipient)}',
      '최종 제출 단계: $_submitStage',
      '마지막 실패: ${_lastFailure.isEmpty ? '없음' : _lastFailure}',
      'Sector 사용: ${result?.sectorEnabled ?? false}',
      'Sector 수: ${sector?.sectorCount ?? 0}',
      'Firestore 저장: ${result?.firestoreSaveOk ?? false}',
      'Plate 로그: ${result?.plateOutLogOk ?? false}',
      'GCS 업로드: ${result?.gcsLogsUploadOk ?? false}',
      'GCS 검증: ${result?.gcsObjectVerified ?? false}',
      'Cleanup: ${result?.cleanupOk ?? false}',
      'Cleanup 생략: ${result?.cleanupSkipped ?? false}',
      '중복 제출 방지: ${result?.duplicateSubmissionPrevented ?? false}',
      '애니메이션 감소: $_reduceMotion',
    ].join('\n');

    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: '업무 종료 보고 상태',
        description: description,
        copyText: _debugPrintCode,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
      return;
    }

    await StatusDialog.showSuccess(
      context,
      title: '업무 종료 보고 상태',
      description: description,
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  void _closeDock() {
    if (_sending || _firstSubmitting) return;
    _recordDebug(
      'dock_close first=$_firstSubmitStatusLabel special=${_hasSpecialNote ?? 'unset'} contentLen=${_contentCtrl.text.trim().length}',
    );
    Navigator.of(context).pop();
  }

  String _buildPreviewText() {
    final specialText = _hasSpecialNote == null
        ? '미선택'
        : _hasSpecialNote!
            ? '있음'
            : '없음';
    final result = _firstSubmitResult;
    final sector = result?.sectorMetrics;
    return <String>[
      '업무 종료 보고',
      '지역: ${_resolveReportArea()}',
      '작성 시각: ${_fmtCompact(_createdAt)}',
      '출차: $_sysVehicleOutput대',
      '중복 입차: $_sysDepartureExtra대',
      '저장 출차 대수: $_sysDepartureTotal대',
      '1차 제출 상태: $_firstSubmitStatusLabel',
      if (result?.sectorEnabled == true) '방문 구역 수: ${sector?.sectorCount ?? 0}개',
      if (result?.sectorEnabled == true)
        '방문 구역 지정 차량: ${sector?.assignedVehicleCount ?? 0}대',
      if (result?.sectorEnabled == true)
        '방문 구역 미지정 차량: ${sector?.unassignedVehicleCount ?? 0}대',
      '특이사항: $specialText',
      if (_hasSpecialNote == true) '특이사항 내용: ${_contentCtrl.text.trim()}',
      '수신처: ${_recipient.trim().isEmpty ? '미설정' : _recipient.trim()}',
      '메일 제목: $_mailSubject',
      '메일 본문: $_mailBody',
    ].join('\n');
  }

  Future<void> _copyPreviewText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.lightImpact();
    _recordDebug('preview_copy length=${text.length}');
    if (!mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '텍스트 복사 완료',
      useCommonUi: true,
    );
  }

  Future<void> _showPreview() async {
    if (_sending || _firstSubmitting || _initializing) return;
    if (!_firstSubmittedCompleted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _createdAt = DateTime.now();
      _mailBody = '';
      _updateMailContent(forceBody: true);
    });
    _recordDebug('preview_open');
    final previewText = _buildPreviewText();
    final result = _firstSubmitResult;
    final sector = result?.sectorMetrics;

    await showCommonOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        final textTheme = Theme.of(dialogContext).textTheme;
        final maxHeight = MediaQuery.of(dialogContext).size.height * .78;
        return Dialog(
          backgroundColor: tokens.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
              child: Material(
                color: tokens.canvas,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        border: Border(
                          bottom: BorderSide(color: tokens.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: tokens.dangerContainer,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.task_alt_rounded,
                              size: 20,
                              color: tokens.onDangerContainer,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '업무 종료 보고 미리보기',
                              style: textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          CommonIconButton(
                            icon: Icons.close_rounded,
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            haptic: CommonHaptic.selection,
                            size: 38,
                            iconSize: 19,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OpsDockListSurface(
                              child: Column(
                                children: [
                                  _EndReportValueRow(
                                    label: '지역',
                                    value: _resolveReportArea(),
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '작성 시각',
                                    value: _fmtCompact(_createdAt),
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '출차',
                                    value: '$_sysVehicleOutput대',
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '중복 입차',
                                    value: '$_sysDepartureExtra대',
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '저장 출차 대수',
                                    value: '$_sysDepartureTotal대',
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '1차 제출 상태',
                                    value: _firstSubmitStatusLabel,
                                  ),
                                  if (result?.sectorEnabled == true) ...[
                                    _divider(tokens),
                                    _EndReportValueRow(
                                      label: '방문 구역 수',
                                      value: '${sector?.sectorCount ?? 0}개',
                                    ),
                                    _divider(tokens),
                                    _EndReportValueRow(
                                      label: '지정 차량',
                                      value:
                                          '${sector?.assignedVehicleCount ?? 0}대',
                                    ),
                                    _divider(tokens),
                                    _EndReportValueRow(
                                      label: '미지정 차량',
                                      value:
                                          '${sector?.unassignedVehicleCount ?? 0}대',
                                    ),
                                  ],
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '특이사항',
                                    value: _hasSpecialNote == null
                                        ? '미선택'
                                        : _hasSpecialNote!
                                            ? '있음'
                                            : '없음',
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '수신처',
                                    value: _recipient.trim().isEmpty
                                        ? '미설정'
                                        : _recipient.trim(),
                                    maxValueLines: 2,
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '메일 제목',
                                    value: _mailSubject,
                                    maxValueLines: 3,
                                  ),
                                  _divider(tokens),
                                  _EndReportValueRow(
                                    label: '메일 본문',
                                    value: _mailBody,
                                    maxValueLines: 4,
                                  ),
                                ],
                              ),
                            ),
                            if (_hasSpecialNote == true) ...[
                              const SizedBox(height: 10),
                              _EndReportPreviewDetailSurface(
                                title: '특이사항 내용',
                                body: _contentCtrl.text.trim().isEmpty
                                    ? '-'
                                    : _contentCtrl.text.trim(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    OpsDockContextFooter(
                      children: [
                        Expanded(
                          child: CommonButton(
                            label: '텍스트 복사',
                            icon: Icons.copy_all_rounded,
                            variant: CommonButtonVariant.secondary,
                            minHeight: 46,
                            expand: true,
                            haptic: CommonHaptic.selection,
                            onPressed: () => _copyPreviewText(previewText),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CommonButton(
                            label: '닫기',
                            variant: CommonButtonVariant.tertiary,
                            minHeight: 46,
                            expand: true,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _recordDebug('preview_close');
  }

  String _safeFileName(String raw) {
    final value = raw.trim().isEmpty ? '업무종료보고서' : raw.trim();
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    try {
      pw.Font? regular;
      pw.Font? bold;

      try {
        final regData = await rootBundle
            .load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
        regular = pw.Font.ttf(regData);
      } catch (_) {}

      try {
        final boldData = await rootBundle
            .load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
        bold = pw.Font.ttf(boldData);
      } catch (_) {
        bold = regular;
      }

      final theme = regular != null
          ? pw.ThemeData.withFont(
              base: regular,
              bold: bold ?? regular,
              italic: regular,
              boldItalic: bold ?? regular,
            )
          : pw.ThemeData.base();
      final document = pw.Document();
      final specialText = _hasSpecialNote == null
          ? '미선택'
          : _hasSpecialNote!
              ? '있음'
              : '없음';
      final sectorMetrics = _firstSubmitResult?.sectorMetrics;
      final fields = <MapEntry<String, String>>[
        MapEntry<String, String>('특이사항', specialText),
        MapEntry<String, String>('출차 대수', '$_sysDepartureTotal대'),
        if (_firstSubmitResult?.sectorEnabled == true && sectorMetrics != null)
          MapEntry<String, String>(
            '방문 구역 수',
            '${sectorMetrics.sectorCount}개',
          ),
        if (_firstSubmitResult?.sectorEnabled == true && sectorMetrics != null)
          MapEntry<String, String>(
            '방문 구역 지정 차량',
            '${sectorMetrics.assignedVehicleCount}대',
          ),
        if (_firstSubmitResult?.sectorEnabled == true && sectorMetrics != null)
          MapEntry<String, String>(
            '방문 구역 미지정 차량',
            '${sectorMetrics.unassignedVehicleCount}대',
          ),
      ];

      document.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
          build: (_) => [
            pw.Center(
              child: pw.Text(
                '업무 종료 보고서',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            _pdfFieldTable(fields),
            if (_firstSubmitResult?.sectorEnabled == true &&
                sectorMetrics != null) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                '방문 구역별 집계',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                headers: const <String>['방문 구역', '차량 수', '잠금 금액'],
                data: <List<String>>[
                  for (final item in sectorMetrics.items)
                    <String>[
                      item.sectorName,
                      '${item.vehicleCount}대',
                      '₩${NumberFormat('#,###').format(item.totalLockedFee)}',
                    ],
                  if (sectorMetrics.unassignedVehicleCount > 0)
                    <String>[
                      '미지정',
                      '${sectorMetrics.unassignedVehicleCount}대',
                      '₩${NumberFormat('#,###').format(sectorMetrics.unassignedLockedFee)}',
                    ],
                  if (sectorMetrics.invalidSectorVehicleCount > 0)
                    <String>[
                      '데이터 확인 필요',
                      '${sectorMetrics.invalidSectorVehicleCount}대',
                      '₩${NumberFormat('#,###').format(sectorMetrics.invalidSectorLockedFee)}',
                    ],
                ],
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: .5,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                headerStyle: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellPadding: const pw.EdgeInsets.all(6),
              ),
            ],
            if (_hasSpecialNote == true)
              _pdfSection('특이사항 내용', _contentCtrl.text.trim()),
          ],
          footer: (_) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '생성 시각: ${_fmtCompact(_createdAt)}',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ),
      );

      return document.save();
    } catch (error, stackTrace) {
      _recordDebug('pdf_build_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._buildPdfBytes',
        message: 'PDF 생성 실패',
        error: error,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'stack': stackTrace.toString(),
        },
        tags: const <String>[_tEndPdf, _tEndUi, _tEnd],
      );
      rethrow;
    }
  }

  pw.Widget _pdfFieldTable(List<MapEntry<String, String>> fields) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(7),
      },
      children: [
        for (final field in fields)
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.grey200,
                child: pw.Text(
                  field.key,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  field.value,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _pdfSection(String title, String body) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: .5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            body.isEmpty ? '-' : body,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      await GmailPdfMailer.sendPdf(
        pdfBytes: pdfBytes,
        filename: filename,
        to: to,
        subject: subject,
        body: body,
      );
    } catch (error, stackTrace) {
      _recordDebug('gmail_send_failure error=$error');
      await _logApiError(
        tag: 'DashboardEndReportSideDock._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: error,
        extra: <String, dynamic>{
          'toLen': to.length,
          'subjectLen': subject.length,
          'bodyLen': body.length,
          'pdfBytes': pdfBytes.length,
          'filename': filename,
          'stack': stackTrace.toString(),
        },
        tags: const <String>[_tEndMail, _tGmailSend, _tEnd],
      );
      rethrow;
    }
  }

  Widget _divider(CommonUiTokens tokens) {
    return Divider(
      height: 1,
      thickness: 1,
      color: tokens.borderSubtle,
    );
  }

  Color _firstSubmitStatusColor(CommonUiTokens tokens) {
    if (_firstSubmitting) return tokens.info;
    if (!_firstSubmittedCompleted) return tokens.textSecondary;
    return _firstSubmitPartial ? tokens.warning : tokens.success;
  }

  Widget _buildContextStrip(CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    final ready = _firstSubmittedCompleted && _recipientValid;
    return CommonSideDockReveal(
      order: 1,
      offsetY: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 18,
              color: tokens.iconSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: Text(
                  _fmtCompact(_createdAt),
                  key: ValueKey<String>(_fmtCompact(_createdAt)),
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: ready
                    ? tokens.successContainer
                    : _firstSubmittedCompleted
                        ? tokens.warningContainer
                        : tokens.infoContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
              ),
              child: AnimatedSwitcher(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                child: Text(
                  ready
                      ? '최종 제출 준비'
                      : _firstSubmittedCompleted
                          ? '수신처 확인'
                          : _firstSubmitting
                              ? '1차 제출 중'
                              : '1차 제출 필요',
                  key: ValueKey<String>(
                    '$ready-$_firstSubmittedCompleted-$_firstSubmitting-$_recipientValid',
                  ),
                  style: textTheme.labelSmall?.copyWith(
                    color: ready
                        ? tokens.onSuccessContainer
                        : _firstSubmittedCompleted
                            ? tokens.onWarningContainer
                            : tokens.onInfoContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialNoteRow(CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = _firstSubmittedCompleted &&
        !_sending &&
        !_firstSubmitting &&
        !_initializing;
    return AnimatedContainer(
      key: _specialNoteKey,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: _specialNoteInvalid
            ? tokens.dangerContainer.withOpacity(.46)
            : tokens.transparent,
        border: _specialNoteInvalid
            ? Border.all(color: tokens.danger.withOpacity(.72))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.report_problem_outlined,
                size: 18,
                color: enabled ? tokens.iconSecondary : tokens.iconDisabled,
              ),
              const SizedBox(width: 8),
              Text(
                '특이사항',
                style: textTheme.bodyMedium?.copyWith(
                  color: enabled ? tokens.textPrimary : tokens.textDisabled,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                child: Text(
                  _hasSpecialNote == null
                      ? '미선택'
                      : _hasSpecialNote!
                          ? '있음'
                          : '없음',
                  key: ValueKey<String>('special-${_hasSpecialNote ?? 'unset'}'),
                  style: textTheme.bodySmall?.copyWith(
                    color: _specialNoteInvalid
                        ? tokens.danger
                        : enabled
                            ? tokens.textSecondary
                            : tokens.textDisabled,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CommonButton(
                  label: '없음',
                  variant: _hasSpecialNote == false
                      ? CommonButtonVariant.primary
                      : CommonButtonVariant.secondary,
                  selected: _hasSpecialNote == false,
                  onPressed: enabled ? () => _setSpecialNote(false) : null,
                  minHeight: 44,
                  expand: true,
                  haptic: CommonHaptic.selection,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CommonButton(
                  label: '있음',
                  variant: _hasSpecialNote == true
                      ? CommonButtonVariant.primary
                      : CommonButtonVariant.secondary,
                  selected: _hasSpecialNote == true,
                  onPressed: enabled ? () => _setSpecialNote(true) : null,
                  minHeight: 44,
                  expand: true,
                  haptic: CommonHaptic.selection,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListSurface(CommonUiTokens tokens) {
    final result = _firstSubmitResult;
    final sector = result?.sectorMetrics;
    return CommonSideDockReveal(
      order: 2,
      offsetY: 7,
      child: OpsDockListSurface(
        child: Column(
          children: [
            _EndReportValueRow(
              label: '출차',
              value: '$_sysVehicleOutput대',
              icon: Icons.logout_rounded,
            ),
            _divider(tokens),
            _EndReportValueRow(
              label: '중복 입차',
              value: '$_sysDepartureExtra대',
              icon: Icons.repeat_rounded,
            ),
            _divider(tokens),
            _EndReportValueRow(
              label: '저장 출차 대수',
              value: '$_sysDepartureTotal대',
              icon: Icons.summarize_outlined,
            ),
            _divider(tokens),
            _EndReportValueRow(
              label: '1차 제출 상태',
              value: _firstSubmitStatusLabel,
              icon: Icons.cloud_done_outlined,
              valueColor: _firstSubmitStatusColor(tokens),
            ),
            if (result?.sectorEnabled == true) ...[
              _divider(tokens),
              _EndReportValueRow(
                label: '방문 구역',
                value:
                    '${sector?.sectorCount ?? 0}개 · 지정 ${sector?.assignedVehicleCount ?? 0}대',
                icon: Icons.grid_view_rounded,
                maxValueLines: 2,
              ),
            ],
            _divider(tokens),
            _buildSpecialNoteRow(tokens),
            _divider(tokens),
            _EndReportValueRow(
              label: '작성 시각',
              value: _fmtCompact(_createdAt),
              icon: Icons.schedule_rounded,
            ),
            _divider(tokens),
            _EndReportValueRow(
              label: '메일 제목',
              value: _mailSubject,
              icon: Icons.subject_rounded,
              maxValueLines: 2,
            ),
            _divider(tokens),
            _EndReportValueRow(
              label: '수신처',
              value: _recipient.trim().isEmpty ? '미설정' : _recipient.trim(),
              icon: Icons.alternate_email_rounded,
              maxValueLines: 2,
              valueColor: _recipientValid ? null : tokens.warning,
            ),
            _divider(tokens),
            _EndReportValueRow(
              label: '메일 내용',
              value: '자동 생성됨',
              icon: Icons.mail_outline_rounded,
              trailingIcon: Icons.chevron_right_rounded,
              onTap: _firstSubmittedCompleted &&
                      !_sending &&
                      !_firstSubmitting &&
                      !_initializing
                  ? _showPreview
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSurface(CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    final duration = _reduceMotion ? Duration.zero : CommonUiMotion.component;
    return AnimatedSize(
      duration: duration,
      curve: CommonUiMotion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) {
          if (_reduceMotion) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: CommonUiMotion.enter,
            reverseCurve: CommonUiMotion.exit,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .045),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: .985, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
        child: _firstSubmittedCompleted && _hasSpecialNote == true
            ? Container(
                key: const ValueKey<String>('dashboard-end-detail-visible'),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        _contentInvalid ? tokens.danger : tokens.borderSubtle,
                    width: _contentInvalid ? 1.3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  key: _contentFieldKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 18,
                          color: tokens.iconSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '특이사항 내용',
                          style: textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _contentCtrl,
                        focusNode: _contentNode,
                        enabled: !_sending && !_firstSubmitting,
                        keyboardType: TextInputType.multiline,
                        minLines: 7,
                        maxLines: 12,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          if (_hasSpecialNote == true &&
                              (value == null || value.trim().isEmpty)) {
                            return '업무 내용을 입력하세요.';
                          }
                          return null;
                        },
                        onChanged: (_) {
                          if (_contentInvalid) {
                            setState(() => _contentInvalid = false);
                          }
                          unawaited(_persistDraft());
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: tokens.surfaceOverlay,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(color: tokens.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(color: tokens.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(
                              color: tokens.focusRing,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(color: tokens.danger),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(
                              color: tokens.danger,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('dashboard-end-detail-hidden'),
              ),
      ),
    );
  }

  Widget _buildFooter() {
    if (!_firstSubmittedCompleted) {
      return OpsDockContextFooter(
        children: [
          Expanded(
            child: CommonButton(
              label: '초기화',
              variant: CommonButtonVariant.tertiary,
              minHeight: 46,
              expand: true,
              onPressed: _firstSubmitting || _sending || _initializing
                  ? null
                  : _reset,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: CommonButton(
              label: _firstSubmitting ? '1차 제출 중' : '1차 제출',
              variant: CommonButtonVariant.primary,
              minHeight: 46,
              expand: true,
              loading: _firstSubmitting,
              preserveVariantWhenDisabled: true,
              onPressed: _firstSubmitting || _sending || _initializing
                  ? null
                  : _submitFirstEndReport,
              haptic: CommonHaptic.light,
            ),
          ),
        ],
      );
    }

    return OpsDockContextFooter(
      children: [
        Expanded(
          child: CommonButton(
            label: _firstSubmitPartial ? '재시도' : '초기화',
            variant: CommonButtonVariant.tertiary,
            minHeight: 46,
            expand: true,
            onPressed: _sending || _firstSubmitting || _initializing
                ? null
                : _firstSubmitPartial
                    ? _submitFirstEndReport
                    : _reset,
            haptic: CommonHaptic.selection,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: '미리보기',
            variant: CommonButtonVariant.secondary,
            minHeight: 46,
            expand: true,
            onPressed: _sending || _firstSubmitting || _initializing
                ? null
                : _showPreview,
            haptic: CommonHaptic.selection,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: _sending ? '전송 중' : '최종 제출',
            variant: CommonButtonVariant.primary,
            minHeight: 46,
            expand: true,
            loading: _sending,
            preserveVariantWhenDisabled: true,
            onPressed: _sending || _firstSubmitting || _initializing
                ? null
                : _submit,
            haptic: CommonHaptic.light,
          ),
        ),
      ],
    );
  }

  Widget _buildContentCanvas(CommonUiTokens tokens) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CommonUiShapes.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.canvas,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildContextStrip(tokens),
                  const SizedBox(height: 10),
                  _buildListSurface(tokens),
                  _buildDetailSurface(tokens),
                ],
              ),
            ),
            OpsDockLoadingOverlay(
              loading: _initializing || _firstSubmitting || _sending,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final area = _resolveReportArea();
    return CommonSideDockFrame(
      title: '업무 종료 보고',
      subtitle: '$area · 업무 종료',
      icon: Icons.task_alt_rounded,
      closeEnabled: !_sending && !_firstSubmitting,
      onClose: _closeDock,
      onLongPress: _developerMode ? _showDeveloperStatus : null,
      headerAction: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .88, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _developerMode
            ? CommonIconButton(
                key: const ValueKey<String>('dashboard-end-debug-visible'),
                icon: Icons.bug_report_rounded,
                tooltip: '디버그 상태',
                onPressed: _showDeveloperStatus,
                haptic: CommonHaptic.selection,
                size: 38,
                iconSize: 19,
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('dashboard-end-debug-hidden'),
              ),
      ),
      footer: OpsDockContextFooterTransition(child: _buildFooter()),
      child: _buildContentCanvas(tokens),
    );
  }
}

class _EndReportValueRow extends StatefulWidget {
  const _EndReportValueRow({
    required this.label,
    required this.value,
    this.icon,
    this.trailingIcon,
    this.onTap,
    this.maxValueLines = 1,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final int maxValueLines;
  final Color? valueColor;

  @override
  State<_EndReportValueRow> createState() => _EndReportValueRowState();
}

class _EndReportValueRowState extends State<_EndReportValueRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final interactive = widget.onTap != null;

    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed && interactive ? .985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: interactive
              ? (value) {
                  if (!mounted) return;
                  setState(() => _pressed = value);
                }
              : null,
          child: AnimatedContainer(
            duration:
                reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            color: _pressed && interactive
                ? tokens.surfaceSelected.withOpacity(.5)
                : tokens.transparent,
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.icon != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: tokens.iconSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 4,
                  child: Text(
                    widget.label,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 7,
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      widget.value,
                      key: ValueKey<String>(widget.value),
                      maxLines: widget.maxValueLines,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: textTheme.bodySmall?.copyWith(
                        color: widget.valueColor ?? tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 5),
                  Icon(
                    widget.trailingIcon,
                    size: 18,
                    color: interactive
                        ? tokens.iconSecondary
                        : tokens.iconDisabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndReportPreviewDetailSurface extends StatelessWidget {
  const _EndReportPreviewDetailSurface({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
