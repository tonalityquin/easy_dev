import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../../repositories/plate_repo_services/plate_count_service.dart';
import '../../../../../../../repositories/end_work_report_repo_services/end_work_report_firestore_repository.dart';
import '../../../../../../../states/area/area_state.dart';
import '../../../../../../../states/user/user_state.dart';
import '../../../../../../../utils/gcs/gcs_uploader.dart';
import '../../../../../../../utils/google_auth_v7.dart';
import '../../../../../../../utils/api/email_config.dart';
import '../../../../../../../utils/snackbar_helper.dart';
import '../../../../../../../utils/block_dialogs/blocking_dialog.dart';
import '../../../../../../../utils/block_dialogs/duration_blocking_dialog.dart';
import '../../../common_package/document_package/backup/backup_signature_dialog.dart';

// ✅ API 디버그(통합 에러 로그) 로거 + (옵션) 디버그 UI
// 프로젝트 패키지명이 easydev인 경우(기존 코드에 package:easydev 사용 사례가 있어 package import 권장)
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_bottom_sheet.dart';

/// end-report 전용 컬러 팔레트
class EndReportColors {
  EndReportColors._();

  static const Color primary = Color(0xFFEF6C53);
  static const Color primaryDark = Color(0xFFE15233);
  static const Color primaryLight = Color(0xFFFFD2BC);
  static const Color primarySoft = Color(0xFFFFF3EC);
  static const Color pageBackground = Color(0xFFF6F2EF);
}

/// end-report 전용 버튼 스타일
class EndReportButtonStyles {
  EndReportButtonStyles._();

  static ButtonStyle primary() {
    return ElevatedButton.styleFrom(
      backgroundColor: EndReportColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: EndReportColors.primaryLight,
      disabledForegroundColor: Colors.white70,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  static ButtonStyle outlined() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: EndReportColors.primaryDark,
      disabledForegroundColor: Colors.black38,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      side: const BorderSide(
        color: EndReportColors.primaryLight,
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  static ButtonStyle smallPrimary() {
    return ElevatedButton.styleFrom(
      backgroundColor: EndReportColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: EndReportColors.primaryLight,
      disabledForegroundColor: Colors.white70,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      minimumSize: const Size(0, 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      textStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ButtonStyle smallOutlined() {
    return OutlinedButton.styleFrom(
      foregroundColor: EndReportColors.primaryDark,
      disabledForegroundColor: Colors.black38,
      side: const BorderSide(
        color: EndReportColors.primaryLight,
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      minimumSize: const Size(0, 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      textStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class SimpleEndWorkReportResult {
  final String division;
  final String area;
  final int vehicleInputCount;
  final int vehicleOutputManual;
  final int snapshotLockedVehicleCount;
  final num snapshotTotalLockedFee;

  final bool cleanupOk;
  final bool firestoreSaveOk;

  /// ✅ /logs 업로드 결과만 유지
  final bool gcsLogsUploadOk;

  /// ✅ logsUrl만 유지
  final String? logsUrl;

  const SimpleEndWorkReportResult({
    required this.division,
    required this.area,
    required this.vehicleInputCount,
    required this.vehicleOutputManual,
    required this.snapshotLockedVehicleCount,
    required this.snapshotTotalLockedFee,
    required this.cleanupOk,
    required this.firestoreSaveOk,
    required this.gcsLogsUploadOk,
    required this.logsUrl,
  });
}

/// ─────────────────────────────────────────────────────────────
/// ✅ API 디버그 로직 삽입: Service 레벨에서도 DebugApiLogger에 에러 기록
/// ─────────────────────────────────────────────────────────────
class SimpleEndWorkReportService {
  final EndWorkReportFirestoreRepository _repo;

  SimpleEndWorkReportService({EndWorkReportFirestoreRepository? repo})
      : _repo = repo ?? EndWorkReportFirestoreRepository();

  // 표준 태그(네임스페이스)
  static const String _tEnd = 'end_report';
  static const String _tEndService = 'end_report/service';
  static const String _tEndFirestore = 'end_report/firestore';
  static const String _tEndGcsLogs = 'end_report/gcs/logs';
  static const String _tEndCleanup = 'end_report/cleanup';
  static const String _tEndPlates = 'end_report/plates';

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
    required int vehicleInputCount,
    required int vehicleOutputManual,
  }) async {
    dev.log(
      '[END] submitEndReport start: division=$division, area=$area, user=$userName',
      name: 'SimpleEndWorkReportService',
    );

    // 1. plates 스냅샷 조회 (Repository로 위임)
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

    // 2. 잠금 요금 합계 계산
    num snapshotTotalLockedFee = 0;
    try {
      for (final p in plates) {
        final data = p.data;
        num? fee =
        (data['lockedFeeAmount'] is num) ? data['lockedFeeAmount'] as num : null;

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

    // 3. 공통 리포트 로그 구성 (Firestore 저장에 사용)
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = DateFormat('yyyyMM').format(now);

    final reportLog = <String, dynamic>{
      'division': division,
      'area': area,
      'vehicleCount': <String, dynamic>{
        'vehicleInput': vehicleInputCount,
        'vehicleOutput': vehicleOutputManual,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
      },
      'createdAt': now.toIso8601String(),
      'uploadedBy': userName,
    };

    // 4. ❌ GCS - /reports 업로드 로직 제거됨

    // 5. ✅ GCS - /logs 업로드 (유지)
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

      logsUrl = await uploadEndLogJson(
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
        dev.log('[END] upload logs returned null', name: 'SimpleEndWorkReportService');

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

    // 6. Firestore - end_work_reports 저장
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

    // 7. plates / plate_counters cleanup
    bool cleanupOk = true;
    try {
      dev.log('[END] cleanup plates & plate_counters...', name: 'SimpleEndWorkReportService');

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

    dev.log('[END] submitEndReport done', name: 'SimpleEndWorkReportService');

    return SimpleEndWorkReportResult(
      division: division,
      area: area,
      vehicleInputCount: vehicleInputCount,
      vehicleOutputManual: vehicleOutputManual,
      snapshotLockedVehicleCount: snapshotLockedVehicleCount,
      snapshotTotalLockedFee: snapshotTotalLockedFee,
      cleanupOk: cleanupOk,
      firestoreSaveOk: firestoreSaveOk,
      gcsLogsUploadOk: gcsLogsUploadOk,
      logsUrl: logsUrl,
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// 여기부터 DashboardEndReportFormPage (UI)
/// ─────────────────────────────────────────────────────────────

class DashboardEndReportFormPage extends StatefulWidget {
  const DashboardEndReportFormPage({super.key});

  @override
  State<DashboardEndReportFormPage> createState() => _DashboardEndReportFormPageState();
}

class _DashboardEndReportFormPageState extends State<DashboardEndReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 기본 정보 컨트롤러 (현재 UI에서는 사용하지 않지만, 향후 확장 고려해 유지)
  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();

  final _contentCtrl = TextEditingController();
  final _vehicleCountCtrl = TextEditingController(); // 차량 대수 입력

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;

  bool? _hasSpecialNote;
  String? _selectedArea;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false; // 최종 메일 제출 중 여부
  bool _firstSubmitting = false; // 1차 서버 보고 중 여부
  bool _firstSubmittedCompleted = false; // 1차 서버 보고 성공 여부

  bool _isVehicleCountValid = false;

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  final GlobalKey _vehicleFieldKey = GlobalKey();
  final GlobalKey _contentFieldKey = GlobalKey();

  final PlateCountService _plateCountService = PlateCountService();

  int _sysVehicleInput = 0;
  int _sysVehicleOutput = 0;
  int _sysDepartureExtra = 0;

  int get _sysDepartureTotal => _sysVehicleOutput + _sysDepartureExtra;
  int get _sysVehicleFieldTotal => _sysVehicleInput + _sysVehicleOutput + _sysDepartureExtra;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: UI 레벨 로깅 헬퍼 + 태그
  // ─────────────────────────────────────────────────────────────
  static const String _tEnd = 'end_report';
  static const String _tEndUi = 'end_report/ui';
  static const String _tEndCounts = 'end_report/counts';
  static const String _tEndFirst = 'end_report/first_submit';
  static const String _tEndMail = 'end_report/mail';
  static const String _tEndPdf = 'end_report/pdf';
  static const String _tPrefs = 'prefs';
  static const String _tGmailSend = 'gmail/send';

  static const int _mimeB64LineLength = 76;

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

  Future<void> _openDebugBottomSheet() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DebugBottomSheet(),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _vehicleCountCtrl.addListener(_onVehicleCountChanged);
    _updateMailBody();
    _loadSelectedArea();

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
        _selectedArea = area.isEmpty ? null : area;
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
        _plateCountService.getParkingCompletedAggCount(area),
        _plateCountService.getDepartureCompletedAggCount(area),
        _plateCountService.getDepartureCompletedExtraCount(area),
      ]);

      if (!mounted) return;

      setState(() {
        _sysVehicleInput = results[0];
        _sysVehicleOutput = results[1];
        _sysDepartureExtra = results[2];
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
        message: '시스템 집계(입차/출차/중복입차) 로드 실패',
        error: e,
        extra: <String, dynamic>{
          'sysVehicleInput': _sysVehicleInput,
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

  void _reset() {
    HapticFeedback.lightImpact();
    _formKey.currentState?.reset();
    _deptCtrl.clear();
    _nameCtrl.clear();
    _positionCtrl.clear();
    _contentCtrl.clear();
    _vehicleCountCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _hasSpecialNote = null;
      _currentPageIndex = 0;
      _isVehicleCountValid = false;
      _firstSubmittedCompleted = false;
    });
    _updateMailSubject();
    _updateMailBody(force: true);
    _pageController.jumpToPage(0);
  }

  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    String suffixSpecial = '';
    if (_hasSpecialNote != null) {
      suffixSpecial = _hasSpecialNote! ? ' - 특이사항 있음' : ' - 특이사항 없음';
    }

    String vehiclePart = '';
    final vehicleRaw = _vehicleCountCtrl.text.trim();
    if (vehicleRaw.isNotEmpty) {
      final count = int.tryParse(vehicleRaw);
      if (count != null) {
        vehiclePart = ' ${count}대';
      }
    }

    final area = (_selectedArea != null && _selectedArea!.trim().isNotEmpty) ? _selectedArea!.trim() : '업무';
    _mailSubjectCtrl.text = '$area 업무 종료 보고서 – ${month}월 ${day}일자$vehiclePart$suffixSpecial';
  }

  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text = '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 종료 보고서입니다.';
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
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';

    return [
      '— 업무 종료 보고서 —',
      '',
      '특이사항: $specialText',
      '일일 차량 입고 대수: $vehicleText',
      '',
      '[업무 내용]',
      _contentCtrl.text,
      '',
      signInfo,
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showPreview() async {
    HapticFeedback.lightImpact();
    _updateMailBody();
    final text = _buildPreviewText(context);

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';
    final signName = _signerName.isEmpty ? '이름 미입력' : _signerName;
    final signTimeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);
    final createdAtText = _fmtDT(context, DateTime.now());

    Widget _infoPill(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                      color: Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: const BoxDecoration(
                              color: EndReportColors.primaryDark,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.visibility_outlined, color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '업무 종료 보고서 미리보기',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 보고서 내용을 한 번 더 확인해 주세요.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  tooltip: '닫기',
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _infoPill(Icons.calendar_today_outlined, '작성일', createdAtText),
                                        _infoPill(Icons.label_important_outline, '특이사항', specialText),
                                        _infoPill(Icons.directions_car_outlined, '일일 차량 입고 대수', vehicleText),
                                        _infoPill(Icons.person_outline, '서명자', signName),
                                        _infoPill(Icons.access_time, '서명 일시', signTimeText),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.email_outlined, size: 18, color: EndReportColors.primaryDark),
                                              const SizedBox(width: 6),
                                              Text(
                                                '메일 전송 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: EndReportColors.primaryDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Text('제목', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Text(_mailSubjectCtrl.text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                          const SizedBox(height: 10),
                                          Text('본문 (자동 생성)', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                                            ),
                                            child: Text(_mailBodyCtrl.text, style: theme.textTheme.bodyMedium),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.report_problem_outlined, size: 18, color: EndReportColors.primaryDark),
                                              const SizedBox(width: 6),
                                              Text(
                                                '특이 사항 상세 내용',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: EndReportColors.primaryDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFBFBFB),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                                            ),
                                            child: Text(
                                              _contentCtrl.text.trim().isEmpty ? '입력된 특이 사항이 없습니다.' : _contentCtrl.text,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                height: 1.4,
                                                color: _contentCtrl.text.trim().isEmpty ? Colors.grey[600] : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: EndReportColors.primarySoft,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: EndReportColors.primaryLight),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.info_outline, size: 18, color: EndReportColors.primaryDark),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: theme.textTheme.bodySmall?.copyWith(height: 1.4, color: const Color(0xFF1F2937)),
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
                              color: const Color(0xFFFAFAFA),
                              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(ClipboardData(text: text));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('텍스트가 클립보드에 복사되었습니다.')));
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('텍스트 복사'),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('닫기'),
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

    final raw = _vehicleCountCtrl.text.trim();

    if (raw.isEmpty) {
      showFailedSnackbar(context, '일일 차량 입고 대수를 입력해 주세요.');
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(raw)) {
      showFailedSnackbar(context, '일일 차량 입고 대수에는 숫자만 입력해 주세요.');
      return;
    }

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

      showFailedSnackbar(
        context,
        '근무 지역/부문/사용자 정보가 없어 1차 업무 종료 보고를 진행할 수 없습니다.\n설정 화면에서 정보를 확인해 주세요.',
      );
      return;
    }

    HapticFeedback.lightImpact();

    final proceed = await showDurationBlockingDialog(
      context,
      message: '일일 차량 입고 대수를 기준으로 1차 업무 종료 보고를 서버에 전송합니다.\n'
          '약 15초 가량 소요되며, 취소하려면 아래 [취소] 버튼을 눌러 주세요.\n'
          '중간에 화면을 이탈하지 마세요.',
      duration: const Duration(seconds: 15),
    );

    if (!proceed) {
      if (!mounted) return;
      showFailedSnackbar(context, '1차 업무 종료 보고가 취소되었습니다.');
      return;
    }

    setState(() => _firstSubmitting = true);

    try {
      final inputFromText = int.tryParse(raw);
      final vehicleFieldValue = inputFromText ?? _sysVehicleFieldTotal;

      final vehicleInputCount = _sysVehicleInput + _sysDepartureExtra;
      final vehicleOutputManual = _sysDepartureTotal;

      dev.log(
        '[END][Dashboard] first submit counts (area=$area, division=$division, user=$userName) '
            'sysParking=$_sysVehicleInput, sysDeparture=$_sysVehicleOutput, sysExtra=$_sysDepartureExtra, '
            'uiField=$vehicleFieldValue, vehicleInput(parking+extra)=$vehicleInputCount, '
            'vehicleOutput(departure+extra)=$vehicleOutputManual',
        name: 'DashboardEndReportFormPage',
      );

      final service = SimpleEndWorkReportService();
      SimpleEndWorkReportResult? result;

      await runWithBlockingDialog(
        context: context,
        message: '1차 업무 종료 보고를 처리 중입니다. 잠시만 기다려 주세요...',
        task: () async {
          result = await service.submitEndReport(
            division: division,
            area: area,
            userName: userName,
            vehicleInputCount: vehicleInputCount,
            vehicleOutputManual: vehicleOutputManual,
          );
        },
      );

      if (!mounted) return;

      if (result == null) {
        await _logApiError(
          tag: 'DashboardEndReportFormPage._submitFirstEndReport',
          message: '1차 제출 결과(result)가 null',
          error: Exception('result_null'),
          extra: <String, dynamic>{
            'area': area,
            'division': division,
            'user': userName,
            'vehicleFieldValue': vehicleFieldValue,
          },
          tags: const <String>[_tEndFirst, _tEndUi, _tEnd],
        );

        showFailedSnackbar(
          context,
          '1차 업무 종료 보고 처리 결과를 가져오지 못했습니다. 네트워크 상태를 확인 후 다시 시도해 주세요.',
        );
        return;
      }

      final r = result!;
      final lines = <String>[
        '1차 업무 종료 보고 완료',
        '• 화면 일일 차량 입고 대수(사용자 입력): ${vehicleFieldValue}대',
        '• 서버 저장 입고 대수(입차+중복 입차): ${r.vehicleInputCount}대',
        '• 사용자 최종 출차 수(출차+중복 입차): ${r.vehicleOutputManual}대',
        '• 스냅샷(정산 문서 수/합계요금): ${r.snapshotLockedVehicleCount} / ${r.snapshotTotalLockedFee}',
      ];

      if (!r.cleanupOk) lines.add('• 주의: plates/plate_counters 정리가 일부 실패했습니다.');
      if (!r.firestoreSaveOk) lines.add('• Firestore(end_work_reports) 저장에 실패했습니다.');
      if (!r.gcsLogsUploadOk) lines.add('• GCS 로그(/logs) 업로드에 실패했습니다.');
      if (r.logsUrl != null && r.logsUrl!.trim().isNotEmpty) lines.add('• logsUrl: ${r.logsUrl}');

      showSuccessSnackbar(context, lines.join('\n'));

      setState(() {
        _firstSubmittedCompleted = true;
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
          'vehicleRaw': _vehicleCountCtrl.text.trim(),
        },
        tags: const <String>[_tEndFirst, _tEndUi, _tEnd],
      );

      if (!mounted) return;
      showFailedSnackbar(context, '예기치 못한 오류로 1차 업무 종료 보고에 실패했습니다: $e');
    } finally {
      if (mounted) setState(() => _firstSubmitting = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasSpecialNote == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('특이사항 여부를 선택해 주세요.')));
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }

    HapticFeedback.lightImpact();
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

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.')),
        );
        return;
      }

      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메일 제목이 자동 생성되지 않았습니다.')));
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile = _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('업무종료보고서_${nameForFile}_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 완료\n• 제목: $subject\n• 수신자: $toCsv')),
      );
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
          'vehicleRaw': _vehicleCountCtrl.text.trim(),
          'contentLen': _contentCtrl.text.trim().length,
          'hasSignature': _signaturePngBytes != null,
          'subjectLen': _mailSubjectCtrl.text.trim().length,
          'bodyLen': _mailBodyCtrl.text.trim().length,
        },
        tags: const <String>[_tEndMail, _tEndUi, _tEnd, _tGmailSend],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('메일 전송 중 오류: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '업무종료보고서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ PDF 생성: 실패 시 DebugApiLogger 기록
  // ─────────────────────────────────────────────────────────────
  Future<Uint8List> _buildPdfBytes() async {
    try {
      pw.Font? regular;
      pw.Font? bold;

      try {
        final regData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
        regular = pw.Font.ttf(regData);
      } catch (_) {}

      try {
        final boldData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
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

      final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

      final vehicleRaw = _vehicleCountCtrl.text.trim();
      final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';

      final fields = <MapEntry<String, String>>[
        MapEntry('특이사항', specialText),
        MapEntry('일일 차량 입고 대수', vehicleText),
      ];

      pw.Widget buildFieldTable() => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(7)},
        children: [
          for (final kv in fields)
            pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  color: PdfColors.grey200,
                  child: pw.Text(kv.key, style: const pw.TextStyle(fontSize: 11)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(kv.value, style: const pw.TextStyle(fontSize: 11)),
                ),
              ],
            ),
        ],
      );

      pw.Widget buildSection(String title, String body) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(body.isEmpty ? '-' : body, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      );

      pw.Widget buildSignature() {
        final name = _signerName.isEmpty ? '이름 미입력' : _signerName;
        final timeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 8),
            pw.Text('전자서명', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text('서명자: $name', style: const pw.TextStyle(fontSize: 11))),
                pw.SizedBox(width: 8),
                pw.Text('서명 일시: $timeText', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              height: 120,
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: _signaturePngBytes == null
                  ? pw.Center(
                child: pw.Text('서명 이미지 없음', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
              )
                  : pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Image(pw.MemoryImage(_signaturePngBytes!), fit: pw.BoxFit.contain),
              ),
            ),
          ],
        );
      }

      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
          build: (context) => [
            pw.Center(
              child: pw.Text('업무 종료 보고서', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 12),
            buildFieldTable(),
            buildSection('[업무 내용]', _contentCtrl.text),
            buildSignature(),
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
          'vehicleRaw': _vehicleCountCtrl.text.trim(),
          'contentLen': _contentCtrl.text.trim().length,
          'hasSignature': _signaturePngBytes != null,
        },
        tags: const <String>[_tEndPdf, _tEndUi, _tEnd],
      );
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Gmail MIME helpers (CRLF + base64 wrap + RFC2047 Subject)
  // ─────────────────────────────────────────────────────────────
  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _encodeSubjectRfc2047(String subject) {
    final subjectB64 = base64.encode(utf8.encode(subject));
    return '=?utf-8?B?$subjectB64?=';
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    try {
      final api = gmail.GmailApi(client);

      final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
      const crlf = '\r\n';

      final pdfB64Wrapped = _wrapBase64Lines(base64.encode(pdfBytes));

      final mime = StringBuffer()
        ..write('To: $to$crlf')
        ..write('Subject: ${_encodeSubjectRfc2047(subject)}$crlf')
        ..write('MIME-Version: 1.0$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"$crlf')
        ..write('Content-Transfer-Encoding: 7bit$crlf')
        ..write(crlf)
        ..write(body)
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: application/pdf; name="$filename"$crlf')
        ..write('Content-Disposition: attachment; filename="$filename"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(pdfB64Wrapped)
        ..write('--$boundary--$crlf');

      final raw = base64UrlEncode(utf8.encode(mime.toString())).replaceAll('=', '');
      final msg = gmail.Message()..raw = raw;
      await api.users.messages.send(msg, 'me');
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
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  InputDecoration _inputDec({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: EndReportColors.primary,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 12,
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      color: Colors.white,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        Text(
          value,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: isEmphasis ? FontWeight.w700 : FontWeight.w600,
            color: isEmphasis ? EndReportColors.primaryDark : Colors.black87,
          ),
        ),
      ],
    );
  }

  Future<void> _openSignatureDialog() async {
    HapticFeedback.selectionClick();
    try {
      final result = await showGeneralDialog<SignatureResult>(
        context: context,
        barrierLabel: '서명',
        barrierDismissible: false,
        barrierColor: Colors.black54,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return SignatureFullScreenDialog(
            name: _signerName,
            initialDateTime: _signDateTime,
          );
        },
        transitionBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      );

      if (result != null) {
        setState(() {
          _signaturePngBytes = result.pngBytes;
          _signDateTime = result.signDateTime;
        });
      }
    } catch (e) {
      await _logApiError(
        tag: 'DashboardEndReportFormPage._openSignatureDialog',
        message: '전자서명 다이얼로그 처리 실패',
        error: e,
        tags: const <String>[_tEndUi, _tEnd],
      );
      rethrow;
    }
  }

  Widget _buildSpecialNoteBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _hasSpecialNote = false;
                    _updateMailSubject();
                  });
                  _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                },
                style: _hasSpecialNote == false ? EndReportButtonStyles.primary() : EndReportButtonStyles.outlined(),
                child: const Text('특이사항 없음'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _hasSpecialNote = true;
                    _updateMailSubject();
                  });
                  _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                },
                style: _hasSpecialNote == true ? EndReportButtonStyles.primary() : EndReportButtonStyles.outlined(),
                child: const Text('특이사항 있음'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '※ 선택 결과는 메일 제목에 자동으로 반영되며, 다음 항목으로 자동 이동합니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildVehicleBody() {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 하루 동안 해당 업무로 입고된 차량 대수를 입력해 주세요.',
          style: textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: _vehicleFieldKey,
          controller: _vehicleCountCtrl,
          decoration: _inputDec(labelText: '일일 차량 입고 대수', hintText: '예: 12'),
          keyboardType: TextInputType.number,
          onTap: () {
            Future.delayed(const Duration(milliseconds: 150), () {
              final ctx = _vehicleFieldKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
              }
            });
          },
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) return '일일 차량 입고 대수를 입력하세요.';
            if (!RegExp(r'^\d+$').hasMatch(value)) return '숫자만 입력하세요.';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EndReportColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EndReportColors.primaryLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: EndReportColors.primaryDark),
                  const SizedBox(width: 8),
                  Text(
                    '시스템 집계 기준 (참고용)',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: EndReportColors.primaryDark),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '아래 수치는 시스템에서 집계한 값이며, 실제 보고용 "일일 차량 입고 대수"는 반드시 직접 입력해 주세요.',
                style: textTheme.bodySmall?.copyWith(color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMetricRow('시스템 입차', '$_sysVehicleInput대'),
                    const SizedBox(height: 4),
                    _buildMetricRow('출차', '$_sysVehicleOutput대'),
                    const SizedBox(height: 4),
                    _buildMetricRow('중복 입차', '$_sysDepartureExtra대'),
                    const Divider(height: 16),
                    _buildMetricRow('시스템 합산(입차+출차+중복 입차)', '${_sysVehicleFieldTotal}대', isEmphasis: true),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '※ 위 값은 참고용이며, "일일 차량 입고 대수" 입력란에는 자동으로 채워지지 않습니다.',
                style: textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_firstSubmitting || !_isVehicleCountValid) ? null : _submitFirstEndReport,
            style: EndReportButtonStyles.primary(),
            icon: _firstSubmitting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_firstSubmitting ? '1차 제출 중…' : '1차 제출', style: const TextStyle(fontWeight: FontWeight.w600)),
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
        labelText: '특이 사항',
        hintText: '예)\n'
            '- 육하원칙에 맞춰서 작성하세요.\n'
            '- 컴플레인, 사고, 인사 갈등, 고객사와의 소통 발생 여부 및 내용\n'
            '- 업무 프로세스, 업무 환경, 물품 파손 등 문제\n'
            '- 발생 과정 및 조치 사항\n',
      ),
      keyboardType: TextInputType.multiline,
      minLines: 8,
      maxLines: 16,
      onTap: () {
        Future.delayed(const Duration(milliseconds: 150), () {
          final ctx = _contentFieldKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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

  Widget _buildMailBody() {
    return Column(
      children: [
        TextFormField(
          controller: _mailSubjectCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            labelText: '메일 제목(자동 생성)',
            hintText: '예: 콜센터 업무 종료 보고서 – 11월 25일자 12대 - 특이사항 있음',
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(labelText: '메일 본문(자동 생성)', hintText: '작성 시각 정보가 자동으로 입력됩니다.'),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

  Widget _buildSignatureBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _openSignatureDialog,
                icon: const Icon(Icons.border_color),
                label: const Text('서명하기'),
                style: EndReportButtonStyles.smallPrimary(),
              ),
              if (_signaturePngBytes != null)
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _signaturePngBytes = null;
                      _signDateTime = null;
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('서명 삭제'),
                  style: EndReportButtonStyles.smallOutlined(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_signaturePngBytes != null)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Image.memory(_signaturePngBytes!, height: 120, fit: BoxFit.contain),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReportPage({
    required String sectionTitle,
    required Widget sectionBody,
  }) {
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 4),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK COMPLETION REPORT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black54, letterSpacing: 3),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EndReportColors.primaryLight.withOpacity(0.8), width: 1),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note_rounded, size: 22, color: EndReportColors.primaryDark),
                          const SizedBox(width: 8),
                          Text(
                            '업무 종료 보고서 양식',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: EndReportColors.primaryDark),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 24),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: EndReportColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: EndReportColors.primaryLight),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: EndReportColors.primaryDark),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.\n'
                                    '문제 발생 시 상단 “API 디버그”에서 에러 로그를 확인할 수 있습니다.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _gap(20),
                      _sectionCard(title: sectionTitle, margin: const EdgeInsets.only(bottom: 0), child: sectionBody),
                      _gap(12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sending ? null : _reset,
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('초기화'),
                              style: EndReportButtonStyles.outlined(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: EndReportButtonStyles.primary(),
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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: EndReportColors.pageBackground,
      appBar: AppBar(
        title: const Text('업무 종료 보고서 작성'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: Colors.black12, width: 1)),
        actions: [
          IconButton(
            tooltip: 'API 디버그',
            onPressed: _openDebugBottomSheet,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: EndReportButtonStyles.smallPrimary(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _currentPageIndex == 4
          ? SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12, width: 1)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!_sending && _signaturePngBytes != null) ? _submit : null,
              icon: _sending
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(_sending ? '전송 중…' : '제출', style: const TextStyle(fontWeight: FontWeight.bold)),
              style: EndReportButtonStyles.primary(),
            ),
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
            onPageChanged: (index) {
              if (!_firstSubmittedCompleted && index > 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _pageController.animateToPage(1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('다음 단계로 진행하기 전에 먼저 "1차 제출"을 완료해 주세요.')),
                );
                return;
              }

              setState(() {
                _currentPageIndex = index;
                if (index == 0) {
                  _hasSpecialNote = null;
                  _updateMailSubject();
                }
              });
            },
            children: [
              _buildReportPage(sectionTitle: '1. 특이사항 여부 (필수)', sectionBody: _buildSpecialNoteBody()),
              _buildReportPage(sectionTitle: '2. 일일 차량 입고 대수', sectionBody: _buildVehicleBody()),
              _buildReportPage(sectionTitle: '3. 특이 사항 (조건부 필수)', sectionBody: _buildWorkContentBody()),
              _buildReportPage(sectionTitle: '4. 메일 전송 내용', sectionBody: _buildMailBody()),
              _buildReportPage(sectionTitle: '5. 전자서명', sectionBody: _buildSignatureBody()),
            ],
          ),
        ),
      ),
    );
  }
}
