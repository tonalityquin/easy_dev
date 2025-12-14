import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../../repositories/plate_repo_services/plate_count_service.dart';
import '../../../../../../../states/area/area_state.dart';
import '../../../../../../../states/user/user_state.dart';
import '../../../../../../../utils/gcs/gcs_uploader.dart';
import '../../../../../../../utils/google_auth_v7.dart';
import '../../../../../../../utils/api/email_config.dart';
import '../../../../../../../utils/snackbar_helper.dart';
import '../../../../../../../utils/block_dialogs/blocking_dialog.dart';
import '../../../../../../../utils/block_dialogs/duration_blocking_dialog.dart';
import 'lite_dashboard_start_report_signature_dialog.dart';

/// end-report 전용 컬러 팔레트
/// DocumentType.handoverForm 의 기본 색상(0xFFEF6C53)을 기준으로
/// 명암/채도를 추론하여 구성
class EndReportColors {
  EndReportColors._();

  /// 기본 오렌지/레드 (handoverForm 기준 색)
  static const Color primary = Color(0xFFEF6C53);

  /// primary 보다 약간 어두운 톤 (아이콘/텍스트 강조)
  static const Color primaryDark = Color(0xFFE15233);

  /// primary 를 옅게 사용한 톤 (보더/칩/강조 배경)
  static const Color primaryLight = Color(0xFFFFD2BC);

  /// 아주 옅은 톤 (정보/알림 박스 배경)
  static const Color primarySoft = Color(0xFFFFF3EC);

  /// 페이지 전체 배경 톤
  static const Color pageBackground = Color(0xFFF6F2EF);
}

/// end-report 전용 버튼 스타일
class EndReportButtonStyles {
  EndReportButtonStyles._();

  /// 기본 메인 버튼 (Elevated)
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

  /// 아웃라인 톤 버튼 (Elevated/Outlined 공용)
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

  /// 상단 AppBar, 작은 주요 버튼
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

  /// 작은 아웃라인 버튼 (서명 삭제 등)
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

/// ─────────────────────────────────────────────────────────────
/// EndWorkReportService / EndWorkReportController / Sheet 에 있던
/// "업무 종료 서버 보고" 로직을 이 파일 안(SimpleEndWorkReportService)으로
/// 옮긴 버전입니다.
///
/// 이제:
///  - 2단계 "일일 차량 입고 대수"의 [1차 제출] 버튼 → 서버 보고(plates/GCS/Firestore/cleanup)
///  - 5단계 "제출" 버튼 → 메일(PDF) 전송만 수행
///
/// 별도의 EndWorkReportService / Controller / Sheet 파일을 삭제해도
/// 동일한 서버 로직을 그대로 활용할 수 있습니다.
/// ─────────────────────────────────────────────────────────────

dynamic _endReportJsonSafe(dynamic v) {
  if (v == null) return null;

  if (v is Timestamp) return v.toDate().toIso8601String();
  if (v is DateTime) return v.toIso8601String();

  if (v is GeoPoint) {
    return <String, dynamic>{
      '_type': 'GeoPoint',
      'lat': v.latitude,
      'lng': v.longitude,
    };
  }

  if (v is DocumentReference) {
    return <String, dynamic>{
      '_type': 'DocumentReference',
      'path': v.path,
    };
  }

  if (v is num || v is String || v is bool) return v;

  if (v is List) return v.map(_endReportJsonSafe).toList();
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), _endReportJsonSafe(value)));
  }

  return v.toString();
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
  final bool gcsReportUploadOk;
  final bool gcsLogsUploadOk;

  final String? reportUrl;
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
    required this.gcsReportUploadOk,
    required this.gcsLogsUploadOk,
    required this.reportUrl,
    required this.logsUrl,
  });
}

class SimpleEndWorkReportService {
  final FirebaseFirestore _firestore;

  SimpleEndWorkReportService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

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

    // 1. plates 스냅샷 조회
    QuerySnapshot<Map<String, dynamic>> platesSnap;
    try {
      dev.log('[END] query plates...', name: 'SimpleEndWorkReportService');
      platesSnap = await _firestore
          .collection('plates')
          .where('type', isEqualTo: 'departure_completed')
          .where('area', isEqualTo: area)
          .where('isLockedFee', isEqualTo: true)
          .get();
    } catch (e, st) {
      dev.log(
        '[END] plates query failed',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );
      throw Exception('출차 스냅샷 조회 실패: $e');
    }

    final int snapshotLockedVehicleCount = platesSnap.docs.length;

    // 2. 잠금 요금 합계 계산
    num snapshotTotalLockedFee = 0;
    try {
      for (final d in platesSnap.docs) {
        final data = d.data();
        num? fee = (data['lockedFeeAmount'] is num) ? data['lockedFeeAmount'] as num : null;

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
      throw Exception('요금 합계 계산 실패: $e');
    }

    // 3. 공통 리포트 로그 구성
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

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

    // 4. GCS - report 업로드
    String? reportUrl;
    bool gcsReportUploadOk = true;
    try {
      dev.log('[END] upload report...', name: 'SimpleEndWorkReportService');
      reportUrl = await uploadEndWorkReportJson(
        report: reportLog,
        division: division,
        area: area,
        userName: userName,
      );
      if (reportUrl == null) {
        gcsReportUploadOk = false;
        dev.log(
          '[END] upload report returned null',
          name: 'SimpleEndWorkReportService',
        );
      }
    } catch (e, st) {
      gcsReportUploadOk = false;
      dev.log(
        '[END] upload report exception',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );
    }

    // 5. GCS - logs 업로드
    String? logsUrl;
    bool gcsLogsUploadOk = true;
    try {
      dev.log('[END] upload logs...', name: 'SimpleEndWorkReportService');
      final items = <Map<String, dynamic>>[
        for (final d in platesSnap.docs)
          <String, dynamic>{
            'docId': d.id,
            'data': _endReportJsonSafe(d.data()),
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
        dev.log(
          '[END] upload logs returned null',
          name: 'SimpleEndWorkReportService',
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
    }

    // 6. Firestore - end_work_reports 저장 (+ 날짜별 history 누적)
    bool firestoreSaveOk = true;
    try {
      dev.log(
        '[END] save report to Firestore (per-area doc)...',
        name: 'SimpleEndWorkReportService',
      );

      final docRef = _firestore.collection('end_work_reports').doc('area_$area');

      final reportBasePath = 'reports.$dateStr';

      final Map<String, dynamic> payload = {
        'division': division,
        'area': area,
        '$reportBasePath.date': dateStr,
        '$reportBasePath.vehicleCount': reportLog['vehicleCount'],
        '$reportBasePath.metrics': reportLog['metrics'],
        '$reportBasePath.createdAt': reportLog['createdAt'],
        '$reportBasePath.uploadedBy': reportLog['uploadedBy'],
        if (reportUrl != null) '$reportBasePath.reportUrl': reportUrl,
        if (logsUrl != null) '$reportBasePath.logsUrl': logsUrl,
      };

      final historyEntry = <String, dynamic>{
        'date': dateStr,
        'createdAt': reportLog['createdAt'],
        'uploadedBy': userName,
        'vehicleCount': reportLog['vehicleCount'],
        'metrics': reportLog['metrics'],
        if (reportUrl != null) 'reportUrl': reportUrl,
        if (logsUrl != null) 'logsUrl': logsUrl,
      };

      payload['$reportBasePath.history'] = FieldValue.arrayUnion(<Map<String, dynamic>>[historyEntry]);

      await docRef.set(
        payload,
        SetOptions(merge: true),
      );
    } catch (e, st) {
      firestoreSaveOk = false;
      dev.log(
        '[END] Firestore save failed (end_work_reports area doc)',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
      );
    }

    // 7. plates / plate_counters cleanup
    bool cleanupOk = true;
    try {
      dev.log(
        '[END] cleanup plates & plate_counters...',
        name: 'SimpleEndWorkReportService',
      );

      final batch = _firestore.batch();

      for (final d in platesSnap.docs) {
        batch.delete(d.reference);
      }

      final countersRef = _firestore.collection('plate_counters').doc('area_$area');
      batch.set(
        countersRef,
        <String, dynamic>{
          'departureCompletedEvents': 0,
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e, st) {
      cleanupOk = false;
      dev.log(
        '[END] cleanup failed',
        name: 'SimpleEndWorkReportService',
        error: e,
        stackTrace: st,
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
      gcsReportUploadOk: gcsReportUploadOk,
      gcsLogsUploadOk: gcsLogsUploadOk,
      reportUrl: reportUrl,
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

  // 특이사항 여부: null = 미선택, true = 있음, false = 없음
  bool? _hasSpecialNote;

  // SharedPreferences에서 불러오는 선택 영역(업무명)
  String? _selectedArea;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false; // 최종 메일 제출 중 여부
  bool _firstSubmitting = false; // 1차 서버 보고 중 여부
  bool _firstSubmittedCompleted = false; // 1차 서버 보고 성공 여부

  // "일일 차량 입고 대수" 필드 입력/유효 여부
  bool _isVehicleCountValid = false;

  // 페이지 컨트롤러 (섹션별 좌우 스와이프)
  final PageController _pageController = PageController();

  // 현재 페이지 인덱스 (0~4)
  int _currentPageIndex = 0;

  // 키보드가 필드를 가리지 않도록 하기 위한 키
  final GlobalKey _vehicleFieldKey = GlobalKey();
  final GlobalKey _contentFieldKey = GlobalKey();

  // 오늘 집계값 로드를 위한 PlateCountService
  final PlateCountService _plateCountService = PlateCountService();

  // 시스템 집계값(오늘 기준)
  int _sysVehicleInput = 0; // 입차 집계
  int _sysVehicleOutput = 0; // 출차 집계
  int _sysDepartureExtra = 0; // 중복 입차 집계

  int get _sysDepartureTotal => _sysVehicleOutput + _sysDepartureExtra;

  /// "일일 차량 입고 대수" 참고용 시스템 기본 값
  /// = 입차 + 출차 + 중복 입차
  int get _sysVehicleFieldTotal => _sysVehicleInput + _sysVehicleOutput + _sysDepartureExtra;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _vehicleCountCtrl.addListener(_onVehicleCountChanged);
    _updateMailBody(); // 메일 본문 자동 생성
    _loadSelectedArea();

    // context 를 안전하게 쓰기 위해 frame 이후에 시스템 집계값 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSystemVehicleCount();
    });
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? '';
    if (!mounted) return;
    setState(() {
      _selectedArea = area.isEmpty ? null : area;
    });

    // 사용자가 아직 제목을 입력하지 않은 경우에만 자동 채움
    if (_mailSubjectCtrl.text.trim().isEmpty) {
      _updateMailSubject();
    }
  }

  /// EndWorkReportController.loadInitialCounts 의
  /// "입차/출차/중복 입차 집계값" 부분을 이 페이지로 옮긴 메서드.
  ///
  /// - AreaState.currentArea 기준으로
  ///   PlateCountService.getParkingCompletedAggCount(area),
  ///   PlateCountService.getDepartureCompletedAggCount(area),
  ///   PlateCountService.getDepartureCompletedExtraCount(area)
  ///   를 모두 호출해서 상태에 보관한다.
  /// - "일일 차량 입고 대수" 필드는 항상 비어 있는 상태에서 시작하며
  ///   시스템 집계값은 UI 카드로만 안내한다.
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
    });
    _updateMailSubject();
    _updateMailBody(force: true);
    _pageController.jumpToPage(0);
  }

  /// 특이사항 선택 값 + SharedPreferences 선택 영역 + 차량 대수에 따라 메일 제목 자동 생성
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

  /// 메일 본문 자동 생성 (작성 일시 포함)
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

  /// 일일 차량 입고 대수 필드 변경 시:
  ///  - 숫자만 입력되었는지 검증
  ///  - 비어 있지 않고 숫자만이면 1차 제출 버튼 활성화
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
                                const Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.white,
                                ),
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
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
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
                                        _infoPill(
                                          Icons.calendar_today_outlined,
                                          '작성일',
                                          createdAtText,
                                        ),
                                        _infoPill(
                                          Icons.label_important_outline,
                                          '특이사항',
                                          specialText,
                                        ),
                                        _infoPill(
                                          Icons.directions_car_outlined,
                                          '일일 차량 입고 대수',
                                          vehicleText,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.email_outlined,
                                                size: 18,
                                                color: EndReportColors.primaryDark,
                                              ),
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
                                          Text(
                                            '제목',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문 (자동 생성)',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text,
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.report_problem_outlined,
                                                size: 18,
                                                color: EndReportColors.primaryDark,
                                              ),
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
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              _contentCtrl.text.trim().isEmpty ? '입력된 특이 사항이 없습니다.' : _contentCtrl.text,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                height: 1.4,
                                                color:
                                                    _contentCtrl.text.trim().isEmpty ? Colors.grey[600] : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: EndReportColors.primaryDark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '전자서명 정보',
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
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명자',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.grey[700],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signName,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명 일시',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.grey[700],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signTimeText,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Container(
                                            height: 140,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.4),
                                              ),
                                              color: const Color(0xFFFAFAFA),
                                            ),
                                            child: _signaturePngBytes == null
                                                ? Center(
                                                    child: Text(
                                                      '서명 이미지가 없습니다. (전자서명 완료 후 제출할 수 있습니다.)',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.grey[600],
                                                      ),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  )
                                                : Padding(
                                                    padding: const EdgeInsets.all(8),
                                                    child: Image.memory(
                                                      _signaturePngBytes!,
                                                      fit: BoxFit.contain,
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
                                        border: Border.all(
                                          color: EndReportColors.primaryLight,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                            color: EndReportColors.primaryDark,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 '
                                              '텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                height: 1.4,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
                              border: Border(
                                top: BorderSide(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(ClipboardData(text: text));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('텍스트가 클립보드에 복사되었습니다.'),
                                      ),
                                    );
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

  /// 2단계 "일일 차량 입고 대수"에서 사용하는 1차 제출 버튼 핸들러.
  Future<void> _submitFirstEndReport() async {
    if (_firstSubmitting) return;

    final raw = _vehicleCountCtrl.text.trim();

    // 필수 입력 + 숫자 검증
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
      showFailedSnackbar(
        context,
        '근무 지역/부문/사용자 정보가 없어 1차 업무 종료 보고를 진행할 수 없습니다.\n'
        '설정 화면에서 정보를 확인해 주세요.',
      );
      return;
    }

    HapticFeedback.lightImpact();

    // 1단계: 15초간 취소 가능 다이얼로그
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
      // 화면에 표시된 "일일 차량 입고 대수" 값은 사용자가 직접 입력한 값이며,
      // 서버에 저장되는 vehicleInputCount 는 "입차 + 중복 입차"만 사용한다.
      final inputFromText = int.tryParse(raw);
      final vehicleFieldValue = inputFromText ?? _sysVehicleFieldTotal;

      // 백엔드용: 입차(plates: parking_completed) + 중복 입차(plate_counters.departureCompletedEvents)
      final vehicleInputCount = _sysVehicleInput + _sysDepartureExtra;

      // 백엔드용: 최종 출차 수 = 출차(plates: departure_completed & isLockedFee=true) + 중복 입차
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
        '• 스냅샷(plates: 정산 문서 수/합계요금): '
            '${r.snapshotLockedVehicleCount} / ${r.snapshotTotalLockedFee}',
      ];

      if (!r.cleanupOk) {
        lines.add('• 주의: plates/plate_counters 정리가 일부 실패했습니다. 관리자에게 문의하세요.');
      }
      if (!r.firestoreSaveOk) {
        lines.add('• Firestore(end_work_reports) 저장에 실패했습니다.');
      }
      if (!r.gcsReportUploadOk || !r.gcsLogsUploadOk) {
        lines.add('• GCS 보고/로그 파일 업로드에 일부 실패했습니다. 관리자에게 문의하세요.');
      }

      showSuccessSnackbar(context, lines.join('\n'));

      // 1차 제출을 성공적으로 마친 경우 이후 페이지로 스와이프 가능
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
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '예기치 못한 오류로 1차 업무 종료 보고에 실패했습니다: $e',
      );
    } finally {
      if (mounted) setState(() => _firstSubmitting = false);
    }
  }

  /// 최종 "제출" 버튼:
  ///  - 메일(PDF) 전송만 수행
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasSpecialNote == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('특이사항 여부를 선택해 주세요.')),
      );
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.',
            ),
          ),
        );
        return;
      }
      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();
      if (subject.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일 제목이 자동 생성되지 않았습니다.')),
        );
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile = _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('업무종료보고서_${nameForFile}_${_dateTag(now)}');

      // 메일 전송
      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;

      final lines = <String>[
        '메일 전송 완료',
        '• 제목: $subject',
        '• 수신자: $toCsv',
      ];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lines.join('\n'))),
      );
    } catch (e, st) {
      dev.log(
        '[END][Dashboard] submit error',
        name: 'DashboardEndReportFormPage',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 중 오류: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '업무종료보고서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
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
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(7),
          },
          children: [
            for (final kv in fields)
              pw.TableRow(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    color: PdfColors.grey200,
                    child: pw.Text(
                      kv.key,
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      kv.value,
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
          ],
        );

    pw.Widget buildSection(String title, String body) => pw.Column(
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
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                body.isEmpty ? '-' : body,
                style: const pw.TextStyle(fontSize: 11),
              ),
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
          pw.Text(
            '전자서명',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '서명자: $name',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '서명 일시: $timeText',
                style: const pw.TextStyle(fontSize: 11),
              ),
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
                    child: pw.Text(
                      '서명 이미지 없음',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey,
                      ),
                    ),
                  )
                : pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Image(
                      pw.MemoryImage(_signaturePngBytes!),
                      fit: pw.BoxFit.contain,
                    ),
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
            child: pw.Text(
              '업무 종료 보고서',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
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
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ),
      ),
    );

    return doc.save();
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    final api = gmail.GmailApi(client);

    final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
    final subjectB64 = base64.encode(utf8.encode(subject));
    final sb = StringBuffer()
      ..writeln('To: $to')
      ..writeln('Subject: =?utf-8?B?$subjectB64?=')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: text/plain; charset="utf-8"')
      ..writeln('Content-Transfer-Encoding: 7bit')
      ..writeln()
      ..writeln(body)
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: application/pdf; name="$filename"')
      ..writeln('Content-Disposition: attachment; filename="$filename"')
      ..writeln('Content-Transfer-Encoding: base64')
      ..writeln()
      ..writeln(base64.encode(pdfBytes))
      ..writeln('--$boundary--');

    final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

  /// 시스템 집계 수치를 한 줄로 표시하는 small row 위젯
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
            style: textTheme.bodySmall?.copyWith(
              color: Colors.black54,
            ),
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
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
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
  }

  Widget _buildSpecialNoteBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n'
          '(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
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
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
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
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ],
    );
  }

  /// "일일 차량 입고 대수" 섹션
  Widget _buildVehicleBody() {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 하루 동안 해당 업무로 입고된 차량 대수를 입력해 주세요.',
          style: textTheme.bodyMedium?.copyWith(
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: _vehicleFieldKey,
          controller: _vehicleCountCtrl,
          decoration: _inputDec(
            labelText: '일일 차량 입고 대수',
            hintText: '예: 12',
          ),
          keyboardType: TextInputType.number,
          onTap: () {
            Future.delayed(const Duration(milliseconds: 150), () {
              final ctx = _vehicleFieldKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(
                  ctx,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          },
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) {
              return '일일 차량 입고 대수를 입력하세요.';
            }
            if (!RegExp(r'^\d+$').hasMatch(value)) {
              return '숫자만 입력하세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        // 시스템 집계 안내 카드
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EndReportColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: EndReportColors.primaryLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: EndReportColors.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '시스템 집계 기준 (참고용)',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: EndReportColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '아래 수치는 시스템에서 집계한 값이며, 실제 보고용 "일일 차량 입고 대수"는 반드시 직접 입력해 주세요.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0),
                  ),
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
                    _buildMetricRow(
                      '시스템 합산(입차+출차+중복 입차)',
                      '${_sysVehicleFieldTotal}대',
                      isEmphasis: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '※ 위 값은 참고용이며, "일일 차량 입고 대수" 입력란에는 자동으로 채워지지 않습니다.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                  height: 1.3,
                ),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _firstSubmitting ? '1차 제출 중…' : '1차 제출',
              style: const TextStyle(fontWeight: FontWeight.w600),
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
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      },
      validator: (v) {
        if (_hasSpecialNote == true) {
          if (v == null || v.trim().isEmpty) {
            return '업무 내용을 입력하세요.';
          }
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
          decoration: _inputDec(
            labelText: '메일 본문(자동 생성)',
            hintText: '작성 시각 정보가 자동으로 입력됩니다.',
          ),
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
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 12,
          ),
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
                  Expanded(
                    child: Text(
                      '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
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
                  child: Image.memory(
                    _signaturePngBytes!,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
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
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + bottomInset,
        ),
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK COMPLETION REPORT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.black54,
                        letterSpacing: 3,
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: EndReportColors.primaryLight.withOpacity(0.8),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 22,
                            color: EndReportColors.primaryDark,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '업무 종료 보고서 양식',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: EndReportColors.primaryDark,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.black54,
                                ),
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
                          border: Border.all(
                            color: EndReportColors.primaryLight,
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: EndReportColors.primaryDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      height: 1.4,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _gap(20),
                      _sectionCard(
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
        shape: const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
        actions: [
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
                  border: Border(
                    top: BorderSide(color: Colors.black12, width: 1),
                  ),
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
                    label: Text(
                      _sending ? '전송 중…' : '제출',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
              // 1차 제출이 완료되기 전에는 2번 페이지(인덱스 1)를 넘어갈 수 없음
              if (!_firstSubmittedCompleted && index > 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('다음 단계로 진행하기 전에 먼저 "1차 제출"을 완료해 주세요.'),
                  ),
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
              _buildReportPage(
                sectionTitle: '1. 특이사항 여부 (필수)',
                sectionBody: _buildSpecialNoteBody(),
              ),
              _buildReportPage(
                sectionTitle: '2. 일일 차량 입고 대수',
                sectionBody: _buildVehicleBody(),
              ),
              _buildReportPage(
                sectionTitle: '3. 특이 사항 (조건부 필수)',
                sectionBody: _buildWorkContentBody(),
              ),
              _buildReportPage(
                sectionTitle: '4. 메일 전송 내용',
                sectionBody: _buildMailBody(),
              ),
              _buildReportPage(
                sectionTitle: '5. 전자서명',
                sectionBody: _buildSignatureBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
