
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/auth/gcs_uploader.dart';
import '../../../app/config/email_config.dart';
import '../../utils/gmail_pdf_mailer.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dashboard/data/repositories/end_work_report_firestore_repository.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/dev/debug/debug_api_logger.dart';
import '../../../shared/plate/domain/services/plate_count_service.dart';

class EndReportButtonStyles {
  EndReportButtonStyles._();

  static ButtonStyle primary(
      BuildContext context, {
        bool compact = false,
      }) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      disabledBackgroundColor: cs.primary.withOpacity(0.45),
      disabledForegroundColor: cs.onPrimary.withOpacity(0.55),
      elevation: 0,
      padding: compact
          ? const EdgeInsets.symmetric(vertical: 6, horizontal: 10)
          : const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      minimumSize: compact ? const Size(0, 32) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
      ),
      textStyle: compact
          ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)
          : const TextStyle(fontWeight: FontWeight.w700),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
            ? cs.onPrimary.withOpacity(0.10)
            : null,
      ),
    );
  }

  static ButtonStyle outlined(
      BuildContext context, {
        bool compact = false,
      }) {
    final cs = Theme.of(context).colorScheme;

    return OutlinedButton.styleFrom(
      foregroundColor: cs.onSurface,
      disabledForegroundColor: cs.onSurface.withOpacity(0.35),
      backgroundColor: cs.surface,
      side: BorderSide(
        color: cs.outlineVariant.withOpacity(0.9),
        width: 1,
      ),
      padding: compact
          ? const EdgeInsets.symmetric(vertical: 6, horizontal: 10)
          : const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      minimumSize: compact ? const Size(0, 32) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
      ),
      textStyle: compact
          ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)
          : const TextStyle(fontWeight: FontWeight.w700),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
            ? cs.outlineVariant.withOpacity(0.18)
            : null,
      ),
    );
  }

  static ButtonStyle smallPrimary(BuildContext context) =>
      primary(context, compact: true);

  static ButtonStyle smallOutlined(BuildContext context) =>
      outlined(context, compact: true);
}

class SimpleEndWorkReportResult {
  final String division;
  final String area;
  final int vehicleOutputManual;
  final int snapshotLockedVehicleCount;
  final num snapshotTotalLockedFee;

  final bool cleanupOk;
  final bool firestoreSaveOk;
  final bool plateOutLogOk;

  final bool gcsLogsUploadOk;

  final String? logsUrl;

  const SimpleEndWorkReportResult({
    required this.division,
    required this.area,
    required this.vehicleOutputManual,
    required this.snapshotLockedVehicleCount,
    required this.snapshotTotalLockedFee,
    required this.cleanupOk,
    required this.firestoreSaveOk,
    required this.plateOutLogOk,
    required this.gcsLogsUploadOk,
    required this.logsUrl,
  });
}

class SimpleEndWorkReportService {
  final EndWorkReportFirestoreRepository _repo;

  SimpleEndWorkReportService({EndWorkReportFirestoreRepository? repo})
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

  Future<SimpleEndWorkReportResult> submitEndReport({
    required String division,
    required String area,
    required String userName,
    required int vehicleOutputManual,
  }) async {
    dev.log(
      '[END] submitEndReport start: division=$division, area=$area, user=$userName',
      name: 'SimpleEndWorkReportService',
    );

    List<LockedPlateRecord> plates;
    try {
      dev.log('[END] query plates...', name: 'SimpleEndWorkReportService');
      plates = await _repo.fetchLockedDepartureCompletedPlates(area: area);
    } catch (e, st) {
      dev.log(
        '[END] plates query failed',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SimpleEndWorkReportService.submitEndReport',
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

    num snapshotTotalLockedFee = 0;
    try {
      for (final p in plates) {
        final data = p.data;
        num? fee = (data['lockedFeeAmount'] is num)
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

        snapshotTotalLockedFee += (fee ?? 0);
      }
    } catch (e, st) {
      dev.log(
        '[END] fee sum failed',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SimpleEndWorkReportService.submitEndReport',
        message: '요금 합계 계산 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'platesCount': plates.length,
        },
        tags: const <String>[_tEndService, _tEnd],
      );

      throw Exception('요금 합계 계산 실패: $e');
    }

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
      },
      'createdAt': now.toIso8601String(),
      'uploadedBy': userName,
    };

    String? logsUrl;
    bool gcsLogsUploadOk = true;
    try {
      dev.log('[END] upload logs...', name: 'SimpleEndWorkReportService');

      final items = <Map<String, dynamic>>[
        for (final p in plates)
          <String, dynamic>{
            'docId': p.docId,
            'data': EndWorkReportFirestoreRepository.jsonSafe(p.data),
          },
      ];

      logsUrl = await uploadEndLogCsv(
        report: <String, dynamic>{
          'division': division,
          'area': area,
          'items': items,
        },
        division: division,
        area: area,
        userName: userName,
      );

      if (logsUrl == null) {
        gcsLogsUploadOk = false;
        dev.log('[END] upload logs returned null',
            name: 'SimpleEndWorkReportService');

        await _logApiError(
          tag: 'SimpleEndWorkReportService.submitEndReport',
          message: 'GCS(/logs) 업로드 결과가 null',
          error: Exception('logsUrl is null'),
          extra: <String, dynamic>{
            'division': division,
            'area': area,
            'itemsCount': plates.length,
          },
          tags: const <String>[_tEndService, _tEndGcsLogs, _tEnd],
        );
      }
    } catch (e, st) {
      gcsLogsUploadOk = false;
      dev.log(
        '[END] upload logs exception',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SimpleEndWorkReportService.submitEndReport',
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
    try {
      dev.log(
        '[END] save report to Firestore (monthly document + reports map)...',
        name: 'SimpleEndWorkReportService',
      );

      await _repo.saveMonthlyEndWorkReport(
        division: division,
        area: area,
        monthKey: monthKey,
        dateStr: dateStr,
        vehicleCount: (reportLog['vehicleCount'] as Map<String, dynamic>),
        metrics: (reportLog['metrics'] as Map<String, dynamic>),
        createdAtIso: reportLog['createdAt'] as String,
        uploadedBy: userName,
        logsUrl: logsUrl,
      );
    } catch (e, st) {
      firestoreSaveOk = false;
      dev.log(
        '[END] Firestore save failed (end_work_reports monthly doc + reports map)',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SimpleEndWorkReportService.submitEndReport',
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
      dev.log('[END] append plate_out_log...', name: 'SimpleEndWorkReportService');

      await _repo.appendPlateOutLogs(
        area: area,
        plates: plates,
      );
    } catch (e, st) {
      plateOutLogOk = false;
      dev.log(
        '[END] plate_out_log append failed',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'SimpleEndWorkReportService.submitEndReport',
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

    bool cleanupOk = true;
    if (plateOutLogOk) {
      try {
        dev.log('[END] cleanup plates & plate_counters...',
            name: 'SimpleEndWorkReportService');

        await _repo.cleanupLockedDepartureCompletedPlates(
          area: area,
          plateDocIds: plates.map((e) => e.docId).toList(),
        );
      } catch (e, st) {
        cleanupOk = false;
        dev.log(
          '[END] cleanup failed',
          name: 'SimpleEndWorkReportService',
          error: e,
          stackTrace: st,
        );

        await _logApiError(
          tag: 'SimpleEndWorkReportService.submitEndReport',
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
    }
    dev.log('[END] submitEndReport done', name: 'SimpleEndWorkReportService');

    return SimpleEndWorkReportResult(
      division: division,
      area: area,
      vehicleOutputManual: vehicleOutputManual,
      snapshotLockedVehicleCount: snapshotLockedVehicleCount,
      snapshotTotalLockedFee: snapshotTotalLockedFee,
      cleanupOk: cleanupOk,
      firestoreSaveOk: firestoreSaveOk,
      plateOutLogOk: plateOutLogOk,
      gcsLogsUploadOk: gcsLogsUploadOk,
      logsUrl: logsUrl,
    );
  }
}

class DashboardEndReportFormPage extends StatefulWidget {
  const DashboardEndReportFormPage({super.key});

  @override
  State<DashboardEndReportFormPage> createState() =>
      _DashboardEndReportFormPageState();
}

class _DashboardEndReportFormPageState
    extends State<DashboardEndReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();

  final _contentCtrl = TextEditingController();
  final _vehicleCountCtrl = TextEditingController();

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  bool? _hasSpecialNote;
  String? _selectedArea;

  bool _sending = false;
  bool _firstSubmitting = false;
  bool _firstSubmittedCompleted = false;

  bool _isVehicleCountValid = false;

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  final GlobalKey _contentFieldKey = GlobalKey();

  final PlateCountService _plateCountService = PlateCountService();

  int _sysVehicleOutput = 0;
  int _sysDepartureExtra = 0;

  int get _sysDepartureTotal => _sysVehicleOutput + _sysDepartureExtra;

  static const String _tEnd = 'end_report';
  static const String _tEndUi = 'end_report/ui';
  static const String _tEndCounts = 'end_report/counts';
  static const String _tEndFirst = 'end_report/first_submit';
  static const String _tEndMail = 'end_report/mail';
  static const String _tEndPdf = 'end_report/pdf';
  static const String _tPrefs = 'prefs';
  static const String _tGmailSend = 'gmail/send';

  static const String _prefEndDraftVehicleCount = 'end_report_draft_vehicle_count';
  static const String _prefEndDraftHasSpecialNote = 'end_report_draft_has_special_note';
  static const String _prefEndDraftContent = 'end_report_draft_content';

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

  @override
  void initState() {
    super.initState();
    _vehicleCountCtrl.addListener(_onVehicleCountChanged);
    _updateMailBody();
    _loadSelectedArea();
    _loadDraft();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSystemVehicleCount();
    });
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      if (!mounted) return;
      setState(() {
        _selectedArea = area.trim().isEmpty ? null : area.trim();
      });

      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._loadSelectedArea',
        message: 'SharedPreferences selectedArea 로드 실패',
        error: e,
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _loadSystemVehicleCount() async {
    try {
      final areaState = context.read<AreaState>();
      final area = areaState.currentArea.trim();
      if (area.isEmpty) return;

      final results = await Future.wait<int>([
        _plateCountService.getDepartureCompletedAggCount(area),
        _plateCountService.getDepartureCompletedExtraCount(area),
      ]);

      if (!mounted) return;

      setState(() {
        _sysVehicleOutput = results[0];
        _sysDepartureExtra = results[1];
      });

      _updateMailSubject();
    } catch (e, st) {
      dev.log(
        '[END][Dashboard] loadSystemVehicleCount failed',
        name: 'DashboardEndReportFormPage',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'DashboardEndReportFormPage._loadSystemVehicleCount',
        message: '시스템 집계(출차/중복입차) 로드 실패',
        error: e,
        extra: <String, dynamic>{
          'sysVehicleOutput': _sysVehicleOutput,
          'sysDepartureExtra': _sysDepartureExtra,
        },
        tags: const <String>[_tEndCounts, _tEndUi, _tEnd],
      );
    }
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _contentCtrl.dispose();
    _vehicleCountCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _deptNode.dispose();
    _nameNode.dispose();
    _positionNode.dispose();
    _contentNode.dispose();

    _pageController.dispose();

    super.dispose();
  }

  String _fmtDT(BuildContext context, DateTime? dt) {
    if (dt == null) return '미선택';
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatFullDate(dt);
    final timeStr = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: true,
    );
    return '$dateStr $timeStr';
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _dateTag(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final vehicleCount = prefs.getString(_prefEndDraftVehicleCount) ?? '';
      final hasSpecialNote = prefs.getBool(_prefEndDraftHasSpecialNote);
      final content = prefs.getString(_prefEndDraftContent) ?? '';
      _vehicleCountCtrl.text = vehicleCount;
      _contentCtrl.text = content;
      if (!mounted) return;
      setState(() {
        _hasSpecialNote = hasSpecialNote;
      });
      _updateMailSubject();
      _updateMailBody(force: true);
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._loadDraft',
        message: '업무 종료 보고서 임시저장 데이터 로드 실패',
        error: e,
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefEndDraftVehicleCount,
        _vehicleCountCtrl.text.trim(),
      );
      if (_hasSpecialNote == null) {
        await prefs.remove(_prefEndDraftHasSpecialNote);
      } else {
        await prefs.setBool(
          _prefEndDraftHasSpecialNote,
          _hasSpecialNote!,
        );
      }
      await prefs.setString(_prefEndDraftContent, _contentCtrl.text.trim());
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._persistDraft',
        message: '업무 종료 보고서 임시저장 실패',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
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
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._clearDraft',
        message: '업무 종료 보고서 임시저장 데이터 삭제 실패',
        error: e,
        tags: const <String>[_tPrefs, _tEndUi, _tEnd],
      );
    }
  }

  Future<void> _animateToPage(int page) async {
    if (!_pageController.hasClients) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageController.jumpToPage(page);
      return;
    }
    await _pageController.animateToPage(
      page,
      duration: PromptUiMotion.component,
      curve: PromptUiMotion.enter,
    );
  }

  Future<void> _handleSpecialNoteSelection(bool value) async {
    if (!mounted) return;
    setState(() {
      _hasSpecialNote = value;
      if (!value) {
        _contentCtrl.clear();
      }
      _updateMailSubject();
    });
    await _persistDraft();
    if (!mounted) return;
    if (value) {
      await _animateToPage(2);
      return;
    }
    await _animateToPage(3);
  }

  Future<void> _goBackFromCurrentPage() async {
    if (_currentPageIndex == 3) {
      await _animateToPage(_hasSpecialNote == true ? 2 : 1);
      return;
    }
    if (_currentPageIndex == 2) {
      await _animateToPage(1);
    }
  }

  Future<void> _exitPage() async {
    if (_sending) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    _formKey.currentState?.reset();
    _deptCtrl.clear();
    _nameCtrl.clear();
    _positionCtrl.clear();
    _contentCtrl.clear();
    _vehicleCountCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    await _clearDraft();
    if (!mounted) return;
    setState(() {
      _hasSpecialNote = null;
      _currentPageIndex = 0;
      _isVehicleCountValid = false;
      _firstSubmittedCompleted = false;
    });
    _updateMailSubject();
    _updateMailBody(force: true);
    _pageController.jumpToPage(0);
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

  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    String suffixSpecial = '';
    if (_hasSpecialNote != null) {
      suffixSpecial = _hasSpecialNote! ? ' - 특이사항 있음' : ' - 특이사항 없음';
    }

    final vehiclePart = ' ${_sysDepartureTotal}대';

    final area = _resolveReportArea();
    _mailSubjectCtrl.text =
    '$area 업무 종료 보고서 – ${month}월 ${day}일자$vehiclePart$suffixSpecial';
  }

  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text =
    '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 종료 보고서입니다.';
  }

  void _onVehicleCountChanged() {
    final raw = _vehicleCountCtrl.text.trim();
    final isValid = raw.isNotEmpty && RegExp(r'^\d+$').hasMatch(raw);
    if (_isVehicleCountValid != isValid) {
      setState(() {
        _isVehicleCountValid = isValid;
      });
    }
    _updateMailSubject();
    _persistDraft();
  }

  String _buildPreviewText(BuildContext context) {
    final specialText =
    _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    return [
      '— 업무 종료 보고서 —',
      '',
      '특이사항: $specialText',
      '출차 대수: $_sysDepartureTotal대',
      '',
      '[업무 내용]',
      _contentCtrl.text,
      '',
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showPreview() async {
    _updateMailBody();
    final text = _buildPreviewText(context);

    final specialText =
    _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final createdAtText = _fmtDT(context, DateTime.now());

    Widget infoPill(ColorScheme cs, TextTheme t, IconData icon, String label,
        String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: t.bodySmall?.copyWith(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: t.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final t = Theme.of(ctx).textTheme;

        final borderColor = cs.outlineVariant.withOpacity(0.85);

        Widget section({
          required IconData icon,
          required String title,
          required Widget child,
          Color? background,
        }) {
          return Container(
            decoration: BoxDecoration(
              color: background ?? cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 20, color: borderColor),
                const SizedBox(height: 2),
                child,
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: PromptUiTheme.of(context).transparent,
          insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final maxHeight = MediaQuery.of(ctx).size.height * 0.8;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 720,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Material(
                      color: cs.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: BoxDecoration(color: cs.primary),
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined,
                                    color: cs.onPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '업무 종료 보고서 미리보기',
                                        style: t.titleMedium?.copyWith(
                                          color: cs.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 보고서 내용을 한 번 더 확인해 주세요.',
                                        style: t.bodySmall?.copyWith(
                                          color: cs.onPrimary.withOpacity(0.85),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: Icon(Icons.close, color: cs.onPrimary),
                                  tooltip: '닫기',
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding:
                                const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        infoPill(
                                            cs,
                                            t,
                                            Icons.calendar_today_outlined,
                                            '작성일',
                                            createdAtText),
                                        infoPill(
                                            cs,
                                            t,
                                            Icons.label_important_outline,
                                            '특이사항',
                                            specialText),
                                        infoPill(
                                            cs,
                                            t,
                                            Icons.directions_car_outlined,
                                            '출차 대수',
                                            '${_sysDepartureTotal}대'),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    section(
                                      icon: Icons.email_outlined,
                                      title: '메일 전송 정보',
                                      background: cs.surfaceContainerLow,
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '제목',
                                            style: t.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: t.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문 (자동 생성)',
                                            style: t.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: cs.surface,
                                              borderRadius:
                                              BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: borderColor),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text,
                                              style: t.bodyMedium?.copyWith(
                                                  color: cs.onSurface),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    section(
                                      icon: Icons.report_problem_outlined,
                                      title: '특이 사항 상세 내용',
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerLow,
                                          borderRadius:
                                          BorderRadius.circular(10),
                                          border:
                                          Border.all(color: borderColor),
                                        ),
                                        child: Text(
                                          _contentCtrl.text.trim().isEmpty
                                              ? '입력된 특이 사항이 없습니다.'
                                              : _contentCtrl.text,
                                          style: t.bodyMedium?.copyWith(
                                            height: 1.4,
                                            color:
                                            _contentCtrl.text.trim().isEmpty
                                                ? cs.onSurfaceVariant
                                                : cs.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.info_outline,
                                              size: 18,
                                              color: cs.onPrimaryContainer),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: t.bodySmall?.copyWith(
                                                height: 1.4,
                                                color: cs.onPrimaryContainer,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              border:
                              Border(top: BorderSide(color: borderColor)),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: text));
                                  },
                                  icon:
                                  const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('텍스트 복사'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: cs.primary),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('닫기'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: cs.onSurface),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _submitFirstEndReport() async {
    if (_firstSubmitting) return;

    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();

    final area = areaState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    final userName = userState.name.trim();

    if (area.isEmpty || division.isEmpty || userName.isEmpty) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._submitFirstEndReport',
        message: '근무 지역/부문/사용자 정보 부족으로 1차 제출 불가',
        error: Exception('missing_context'),
        extra: <String, dynamic>{
          'area': area,
          'division': division,
          'userNameLen': userName.length,
        },
        tags: const <String>[_tEndFirst, _tEndUi, _tEnd],
      );
      return;
    }

    setState(() => _firstSubmitting = true);

    try {
      final vehicleOutputManual = _sysDepartureTotal;

      dev.log(
        '[END][Dashboard] first submit counts (area=$area, division=$division, user=$userName) '
            'sysDeparture=$_sysVehicleOutput, sysExtra=$_sysDepartureExtra, '
            'vehicleOutput(departure+extra)=$vehicleOutputManual',
        name: 'DashboardEndReportFormPage',
      );

      final service = SimpleEndWorkReportService();
      final result = await service.submitEndReport(
        division: division,
        area: area,
        userName: userName,
        vehicleOutputManual: vehicleOutputManual,
      );

      if (!mounted) return;

      final r = result;
      if (!r.cleanupOk || !r.firestoreSaveOk || !r.plateOutLogOk || !r.gcsLogsUploadOk) {
        dev.log(
          '[END][Dashboard] first submit partial failure '
              '(cleanupOk=${r.cleanupOk}, firestoreSaveOk=${r.firestoreSaveOk}, plateOutLogOk=${r.plateOutLogOk}, gcsLogsUploadOk=${r.gcsLogsUploadOk}, logsUrl=${r.logsUrl})',
          name: 'DashboardEndReportFormPage',
        );
      }

      setState(() {
        _firstSubmittedCompleted = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    } catch (e, st) {
      dev.log(
        '[END][Dashboard] first submit error',
        name: 'DashboardEndReportFormPage',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'DashboardEndReportFormPage._submitFirstEndReport',
        message: '1차 업무 종료 보고 실패(예외)',
        error: e,
        extra: <String, dynamic>{
          'area': context.read<AreaState>().currentArea.trim(),
          'division': context.read<AreaState>().currentDivision.trim(),
        },
        tags: const <String>[_tEndFirst, _tEndUi, _tEnd],
      );
    } finally {
      if (mounted) setState(() => _firstSubmitting = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasSpecialNote == null) {
      _pageController.animateToPage(1,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }

    setState(() => _sending = true);

    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        await _logApiError(
          tag: 'DashboardEndReportFormPage._submit',
          message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
          error: Exception('invalid_to'),
          extra: <String, dynamic>{'toRaw': cfg.to},
          tags: const <String>[_tEndMail, _tEndUi, _tEnd],
        );
        return;
      }

      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile =
      _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('업무종료보고서_${nameForFile}_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      await _clearDraft();

      if (!mounted) return;

      await _showSubmitSuccessDialogAndClose();
    } catch (e, st) {
      dev.log(
        '[END][Dashboard] submit error',
        name: 'DashboardEndReportFormPage',
        error: e,
        stackTrace: st,
      );

      await _logApiError(
        tag: 'DashboardEndReportFormPage._submit',
        message: '최종 제출(메일 전송) 실패',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'subjectLen': _mailSubjectCtrl.text.trim().length,
          'bodyLen': _mailBodyCtrl.text.trim().length,
        },
        tags: const <String>[_tEndMail, _tEndUi, _tEnd, _tGmailSend],
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showSubmitSuccessDialogAndClose() async {
    if (!mounted) return;

    await StatusDialog.showSuccess(
      context,
      title: StatusDialog.workEndReportSuccess,
      closeCurrentPageAfter: true,
      usePromptUi: true,
    );
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '업무종료보고서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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

      final theme = (regular != null)
          ? pw.ThemeData.withFont(
        base: regular,
        bold: bold ?? regular,
        italic: regular,
        boldItalic: bold ?? regular,
      )
          : pw.ThemeData.base();

      final doc = pw.Document();

      final specialText =
      _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

      final fields = <MapEntry<String, String>>[
        MapEntry('특이사항', specialText),
        MapEntry('출차 대수', '${_sysDepartureTotal}대'),
      ];

      pw.Widget buildFieldTable() => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(7)
        },
        children: [
          for (final kv in fields)
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  color: PdfColors.grey200,
                  child: pw.Text(kv.key,
                      style: const pw.TextStyle(fontSize: 11)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(kv.value,
                      style: const pw.TextStyle(fontSize: 11)),
                ),
              ],
            ),
        ],
      );

      pw.Widget buildSection(String title, String body) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(body.isEmpty ? '-' : body,
                style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      );

      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
          build: (context) => [
            pw.Center(
              child: pw.Text('업무 종료 보고서',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 12),
            buildFieldTable(),
            buildSection('[업무 내용]', _contentCtrl.text),
          ],
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '생성 시각: ${_fmtCompact(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        ),
      );

      return doc.save();
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._buildPdfBytes',
        message: 'PDF 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
        },
        tags: const <String>[_tEndPdf, _tEndUi, _tEnd],
      );
      rethrow;
    }
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
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.length,
          'subjectLen': subject.length,
          'bodyLen': body.length,
          'pdfBytes': pdfBytes.length,
          'filename': filename,
        },
        tags: const <String>[_tEndMail, _tGmailSend, _tEnd],
      );
      rethrow;
    }
  }


  InputDecoration _inputDec(
    BuildContext context, {
    required String labelText,
  }) {
    final tokens = PromptUiTheme.of(context);
    return InputDecoration(
      labelText: labelText,
      filled: true,
      fillColor: tokens.surfaceOverlay,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        borderSide: BorderSide(color: tokens.focusRing, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 12,
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    EdgeInsetsGeometry? margin,
  }) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PromptAnimatedReveal(
      delay: const Duration(milliseconds: 40),
      offset: const Offset(0, .025),
      child: AnimatedContainer(
        duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        margin: margin ?? const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  Widget _buildMetricRow(
      String label,
      String value, {
        bool isEmphasis = false,
      }) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: t.bodySmall?.copyWith(
            fontWeight: isEmphasis ? FontWeight.w800 : FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialNoteBody() {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget choice({required bool value, required String label}) {
      final selected = _hasSpecialNote == value;
      return Expanded(
        child: PromptButton(
          label: label,
          selected: selected,
          variant: selected
              ? PromptButtonVariant.primary
              : PromptButtonVariant.secondary,
          expand: true,
          haptic: PromptHaptic.selection,
          onPressed: () => _handleSpecialNoteSelection(value),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: t.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            choice(value: false, label: '특이사항 없음'),
            const SizedBox(width: 12),
            choice(value: true, label: '특이사항 있음'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '※ 선택 결과는 메일 제목에 자동으로 반영되며, 다음 항목으로 자동 이동합니다.',
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildVehicleBody() {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '대시보드 업무 종료 보고는 시스템 입차를 사용하지 않고 출차와 중복 입차 합계만 저장합니다.',
          style: t.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    '출차 집계 기준',
                    style: t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '저장되는 차량 대수는 출차와 중복 입차를 합산한 값입니다.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMetricRow('출차', '$_sysVehicleOutput대'),
                    const SizedBox(height: 4),
                    _buildMetricRow('중복 입차', '$_sysDepartureExtra대'),
                    Divider(height: 16, color: cs.outlineVariant.withOpacity(0.8)),
                    _buildMetricRow('저장 출차 대수', '${_sysDepartureTotal}대', isEmphasis: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _firstSubmitting ? null : _submitFirstEndReport,
            style: EndReportButtonStyles.primary(context),
            icon: _firstSubmitting
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
              ),
            )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _firstSubmitting
                  ? '1차 제출 중…'
                  : (_firstSubmittedCompleted ? '1차 제출 완료(재제출 가능)' : '1차 제출'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildWorkContentBody() {
    return TextFormField(
      key: _contentFieldKey,
      controller: _contentCtrl,
      focusNode: _contentNode,
      decoration: _inputDec(
        context,
        labelText: '특이 사항',

      ),
      keyboardType: TextInputType.multiline,
      minLines: 8,
      maxLines: 16,
      onChanged: (_) {
        if (_hasSpecialNote == true) {
          _persistDraft();
        }
      },
      onTap: () {
        Future.delayed(const Duration(milliseconds: 150), () {
          final ctx = _contentFieldKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut);
          }
        });
      },
      validator: (v) {
        if (_hasSpecialNote == true) {
          if (v == null || v.trim().isEmpty) return '업무 내용을 입력하세요.';
        }
        return null;
      },
    );
  }

  Future<void> _saveSpecialContentAndGoToMail() async {
    FocusScope.of(context).unfocus();

    if (_hasSpecialNote == null) {
      await _animateToPage(1);
      return;
    }

    if (_hasSpecialNote == true) {
      final isValid = _formKey.currentState?.validate() ?? false;
      if (!isValid) {
        _contentNode.requestFocus();
        final ctx = _contentFieldKey.currentContext;
        if (ctx != null) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        return;
      }
    }

    _updateMailBody(force: true);
    await _persistDraft();
    if (!mounted) return;
    await _animateToPage(3);
  }

  Widget _buildMailBody() {
    return Column(
      children: [
        TextFormField(
          controller: _mailSubjectCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            context,
            labelText: '메일 제목(자동 생성)',

          ),
          validator: (v) =>
          (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(context,
              labelText: '메일 본문(자동 생성)', ),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

  Widget _buildReportPage({
    required String sectionTitle,
    required Widget sectionBody,
  }) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scrollbar(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '업무 종료 보고서',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK COMPLETION REPORT',
                  textAlign: TextAlign.center,
                  style: t.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.85), width: 1),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded,
                              size: 22, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            '업무 종료 보고서 양식',
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: t.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                          height: 24,
                          color: cs.outlineVariant.withOpacity(0.75)),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.85)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.\n'
                                    '문제 발생 시 담당자에게 상황을 전달해 주세요.',
                                style: t.bodySmall?.copyWith(
                                    height: 1.4, color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _gap(20),
                      _sectionCard(
                        context,
                        title: sectionTitle,
                        margin: const EdgeInsets.only(bottom: 0),
                        child: sectionBody,
                      ),
                      _gap(12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sending ? null : _reset,
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('초기화'),
                              style: EndReportButtonStyles.outlined(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: EndReportButtonStyles.primary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: tokens.canvas,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '닫기',
            onPressed: _sending ? null : _exitPage,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: const Text('업무 종료 보고서 작성'),
          centerTitle: true,
          backgroundColor: tokens.surface,
          foregroundColor: tokens.textPrimary,
          elevation: 0,
          surfaceTintColor: tokens.transparent,
          shape: Border(
              bottom: BorderSide(
                  color: tokens.borderSubtle, width: 1)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                onPressed: _showPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('미리보기'),
                style: EndReportButtonStyles.smallPrimary(context),
              ),
            ),
          ],
        ),
        bottomNavigationBar: (_currentPageIndex == 2 || _currentPageIndex == 3)
            ? SafeArea(
          top: false,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(
                top: BorderSide(
                  color: tokens.borderSubtle,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : _goBackFromCurrentPage,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    label: const Text('이전'),
                    style: EndReportButtonStyles.outlined(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sending
                        ? null
                        : _currentPageIndex == 2
                        ? _saveSpecialContentAndGoToMail
                        : _submit,
                    icon: _sending
                        ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          cs.onPrimary,
                        ),
                      ),
                    )
                        : Icon(
                      _currentPageIndex == 2
                          ? Icons.save_outlined
                          : Icons.send_outlined,
                    ),
                    label: Text(
                      _sending
                          ? '전송 중…'
                          : _currentPageIndex == 2
                          ? '저장'
                          : '제출',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: EndReportButtonStyles.primary(context),
                  ),
                ),
              ],
            ),
          ),
        )
            : null,
        body: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentPageIndex = index;
                });
              },
              children: [
                _buildReportPage(
                    sectionTitle: '1. 출차 집계 확인',
                    sectionBody: _buildVehicleBody()),
                _buildReportPage(
                    sectionTitle: '2. 특이사항 여부 (필수)',
                    sectionBody: _buildSpecialNoteBody()),
                _buildReportPage(
                    sectionTitle: '3. 특이 사항 (조건부 필수)',
                    sectionBody: _buildWorkContentBody()),
                _buildReportPage(
                    sectionTitle: '4. 메일 전송 내용', sectionBody: _buildMailBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
