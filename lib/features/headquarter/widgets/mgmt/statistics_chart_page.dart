import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../app/auth/gmail_sender_auth.dart';
import '../../../../app/config/email_config.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../dashboard/domain/models/end_work_sector_metrics.dart';
import '../../../selector/application/dev_auth.dart';
import 'statistics_sector_area_comparison_page.dart';
import 'statistics_deep_log_service.dart';
import 'statistics_deep_model.dart';
import 'statistics_expandable_chart.dart';
import 'statistics_report_design.dart';
import 'statistics_sector_pdf_builder.dart';
import 'statistics_vehicle_log_csv.dart';

class StatisticsChartPage extends StatefulWidget {
  const StatisticsChartPage({
    super.key,
    required this.reportDataMap,
    this.division = '',
    this.area = '',
    this.useCommonUi = false,
    this.availableAreas = const <String>[],
    this.areaSectorEnabled = const <String, bool>{},
  });

  final Map<DateTime, Map<String, dynamic>> reportDataMap;
  final String division;
  final String area;
  final bool useCommonUi;
  final List<String> availableAreas;
  final Map<String, bool> areaSectorEnabled;

  @override
  State<StatisticsChartPage> createState() => _StatisticsChartPageState();
}

enum _AnalyticsSection {
  overview,
  trend,
  sector,
  detail,
  areaComparison,
  hourly,
  payment,
  weekday,
}

enum _AnalyticsMetric { departure, fee }

enum _AnalyticsHourlyMetric { input, output }

enum _AnalyticsPaymentMetric { vehicles, fee }

class _AnalyticsScope {
  final String sectorId;
  final String sectorName;

  const _AnalyticsScope.all()
      : sectorId = '',
        sectorName = '';

  const _AnalyticsScope.sector({
    required this.sectorId,
    required this.sectorName,
  });

  bool get isAll => sectorId.isEmpty && sectorName.isEmpty;

  String get key => isAll ? 'all' : '$sectorId\u0000$sectorName';

  String get label {
    if (isAll) return '전체';
    if (sectorName.trim().isNotEmpty) return sectorName.trim();
    return sectorId.trim();
  }
}

class _StatisticsChartPageState extends State<StatisticsChartPage> {
  final TextEditingController _mailSubjectCtrl = TextEditingController();
  final TextEditingController _mailBodyCtrl = TextEditingController();
  final StatisticsDeepLogService _deepLogService = StatisticsDeepLogService();
  final GlobalKey _areaComparisonKey = GlobalKey();
  final List<String> _debugLines = <String>[];
  bool _sending = false;
  bool _deepLoading = false;
  bool _developerMode = false;
  int _deepProgressCurrent = 0;
  int _deepProgressTotal = 0;
  _AnalyticsSection _selectedSection = _AnalyticsSection.overview;
  _AnalyticsMetric _selectedMetric = _AnalyticsMetric.departure;
  _AnalyticsHourlyMetric _hourlyMetric = _AnalyticsHourlyMetric.output;
  _AnalyticsPaymentMetric _paymentMetric = _AnalyticsPaymentMetric.vehicles;
  _AnalyticsScope _selectedScope = const _AnalyticsScope.all();
  DateTime? _selectedObservation;
  String? _selectedWeekdaySectionId;
  StatisticsDeepReport? _deepReport;
  String? _deepLabel;

  Future<T?> _showChartDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    if (widget.useCommonUi) {
      return showCommonOverlayDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    }
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }


  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDeveloperModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recordDebug(
        'analytics_initialized area=${widget.area} division=${widget.division} developerMode=$_developerMode',
      );
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();
    super.dispose();
  }

  void _handleDeveloperModeChanged() {
    final enabled = DevAuth.devModeEnabled.value;
    if (!mounted || enabled == _developerMode) return;
    setState(() => _developerMode = enabled);
    _recordDebug('developer_mode=$enabled');
  }

  void _recordDebug(String message) {
    final line = '[StatisticsAnalytics] $message';
    _debugLines.add(line);
    if (_debugLines.length > 180) {
      _debugLines.removeRange(0, _debugLines.length - 180);
    }
    debugPrint(line);
  }

  Set<String> _reportDateKeys(_ChartAReport report) {
    return report.rows.map((row) => row.dateStr).toSet();
  }

  bool _rowHasRawSource(_ChartARow row) {
    return row.historyLogsUrls.any((value) => value.trim().isNotEmpty);
  }

  List<_ChartARow> _rowsMissingRawSources(Iterable<_ChartARow> rows) {
    return rows.where((row) => !_rowHasRawSource(row)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  bool _deepReportMatchesChartReport(
    StatisticsDeepReport deep,
    _ChartAReport report,
  ) {
    final expected = _reportDateKeys(report);
    final actual = deep.dateStrs.toSet();
    return expected.length == actual.length && expected.containsAll(actual);
  }

  Set<String> _requestDateKeys(_DeepLoadRequest request) {
    if (!request.isRange) {
      return request.dates.map(_dateOnly).toSet();
    }
    final start = DateTime(
      request.start!.year,
      request.start!.month,
      request.start!.day,
    );
    final end = DateTime(
      request.end!.year,
      request.end!.month,
      request.end!.day,
    );
    return <String>{
      for (var cursor = start; !cursor.isAfter(end); cursor = cursor.add(const Duration(days: 1)))
        _dateOnly(cursor),
    };
  }

  List<_ChartARow> _rowsForRequest(
    _ChartAReport report,
    _DeepLoadRequest request,
  ) {
    final requestedKeys = _requestDateKeys(request);
    final rows = report.rows
        .where((row) => requestedKeys.contains(row.dateStr))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  List<String> _historyLogUrlsForRequest(
    _ChartAReport report,
    _DeepLoadRequest request,
  ) {
    final urls = _rowsForRequest(report, request)
        .expand((row) => row.historyLogsUrls)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return urls;
  }

  EndWorkSectorMetrics? _sectorMetricsForRequest(
    _ChartAReport report,
    _DeepLoadRequest request,
  ) {
    final selected = _rowsForRequest(report, request);
    if (selected.isEmpty) {
      debugPrint('[STAT_SECTOR_CROSS] skipped selectedRows=0');
      return null;
    }
    final merged = EndWorkSectorMetrics.merge(
      selected
          .map((row) => row.sectorMetrics)
          .whereType<EndWorkSectorMetrics>(),
    );
    return merged.enabled ? merged : null;
  }

  _SectorCrossIntegrity _crossValidateSectorMetrics({
    required EndWorkSectorMetrics expected,
    required StatisticsSectorReport actual,
  }) {
    return _SectorCrossIntegrity.compare(expected: expected, actual: actual);
  }

  Future<bool> _confirmExportRawDataIfNeeded(_ChartAReport report) async {
    final deep = _deepReport;
    if (deep != null && _deepReportMatchesChartReport(deep, report)) return true;
    final missingRawRows = _rowsMissingRawSources(report.rows);
    if (missingRawRows.isNotEmpty) {
      final missingDates = missingRawRows.map((row) => row.dateStr).join(', ');
      _recordDebug(
        'export_raw_blocked available=${report.rows.length - missingRawRows.length}/${report.rows.length} missing=$missingDates',
      );
      await _showChartDialog<void>(
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('보고서 발신 불가'),
          content: Text(
            'PDF와 전체 차량 로그 CSV를 함께 발신하려면 비교 날짜 전체에 원본 차량 로그가 필요합니다. 원본이 없는 날짜: $missingDates',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return false;
    }
    final linkedUrls = report.rows
        .expand((row) => row.historyLogsUrls)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (linkedUrls.isEmpty) {
      _recordDebug('export_raw_blocked reason=noLinkedGcsUrls');
      await _showChartDialog<void>(
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('보고서 발신 불가'),
          content: const Text(
            '전체 차량 로그 CSV를 만들 수 있는 원본 차량 로그가 연결되어 있지 않습니다.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return false;
    }
    final confirmed = await _showChartDialog<bool>(
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('보고서 원본 데이터 준비'),
        content: Text(
          'PDF와 전체 차량 로그 CSV를 함께 발신합니다. CSV 생성을 위해 비교 날짜 ${report.rows.length}일의 원본 차량 로그를 불러옵니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('원본 준비 후 발신'),
          ),
        ],
      ),
    );
    _recordDebug(
      'export_raw_confirmed=${confirmed == true} urls=${linkedUrls.length} dates=${report.rows.length}',
    );
    return confirmed == true;
  }

  Future<void> _openMailDialogAndSend(_ChartAReport report) async {
    HapticFeedback.selectionClick();
    if (report.rows.isEmpty) return;
    final rawValidationAccepted = await _confirmExportRawDataIfNeeded(report);
    if (!rawValidationAccepted) return;

    final draft = await _showChartDialog<_MailDraft>(
      barrierDismissible: true,
      builder: (ctx) => _MailComposeDialog(
        initialSubject: _mailSubjectCtrl.text.trim().isEmpty
            ? '출차·정산 비교 리포트 (${report.rangeLabel})'
            : _mailSubjectCtrl.text.trim(),
        initialBody: _mailBodyCtrl.text,
      ),
    );

    if (draft == null) return;
    _mailSubjectCtrl.text = draft.subject;
    _mailBodyCtrl.text = draft.body;
    await _sendStatsReport(report);
  }

  Future<void> _sendStatsReport(_ChartAReport report) async {
    final subject = _mailSubjectCtrl.text.trim();
    final body = _mailBodyCtrl.text.trim();
    if (subject.isEmpty) return;

    setState(() => _sending = true);
    DeveloperOperationTrace? trace;
    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '통계 보고서 및 차량 CSV 발신',
        initialMessage: '분석 PDF와 전체 차량 로그 CSV를 함께 준비하고 있습니다.',
        useCommonUi: widget.useCommonUi,
        developerModeMessage:
            '개발자 모드 ON: PDF·CSV 생성 및 발신 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: PDF·CSV 생성 및 발신 로그를 콘솔에 기록합니다.',
      );
      trace.log(
        'range=${report.rangeLabel} days=${report.metrics.dayCount} '
        'sectorEnabled=${report.sectorMetrics != null} '
        'sectorCount=${report.sectorMetrics?.sectorCount ?? 0}',
        progress: .08,
      );
      final missingRawRows = _rowsMissingRawSources(report.rows);
      if (missingRawRows.isNotEmpty) {
        await trace.fail(
          '전체 차량 로그 CSV에 필요한 원본 날짜가 누락되었습니다: ${missingRawRows.map((row) => row.dateStr).join(', ')}',
        );
        return;
      }
      final expectedGcsLogUrls = report.rows
          .expand((row) => row.historyLogsUrls)
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      trace.log(
        'history linkedGcsUrls=${expectedGcsLogUrls.length}',
        progress: .1,
      );
      if (expectedGcsLogUrls.isEmpty) {
        await trace.fail('전체 차량 로그 CSV에 사용할 연결 GCS 로그가 없습니다.');
        return;
      }
      for (final row in report.rows) {
        if (!row.historyAggregated && row.historyEntryCount <= 1) continue;
        trace.log(
          'history date=${row.dateStr} entries=${row.historyEntryCount} '
          'detailedGcs=${row.historyDetailedEntryCount} '
          'excluded=${row.historyExcludedEntryCount} '
          'first=${row.historyFirstEntryCount} '
          'unverifiedDetailed=${row.historyUnverifiedDetailedEntryCount} '
          'legacyDetailed=${row.historyLegacyDetailedEntryCount} '
          'linkedLogs=${row.historyLogsUrls.length} '
          'sectorEntries=${row.historySectorEntryCount} '
          'mode=${row.historyAggregationMode} '
          'aggregated=${row.historyAggregated}',
          progress: .12,
        );
      }
      StatisticsDeepReport? deepReportForExport = _deepReport;
      if (deepReportForExport != null &&
          !_deepReportMatchesChartReport(deepReportForExport, report)) {
        trace.log('raw=reload reason=dateScopeMismatch');
        deepReportForExport = null;
      } else if (deepReportForExport != null) {
        trace.log(
          'raw=reuse reason=fullScopeReady vehicles=${deepReportForExport.rows.length}',
          progress: .14,
        );
      }
      final area = widget.area.trim();
      final sectorEnabled = widget.areaSectorEnabled[area] == true;
      if (deepReportForExport == null) {
        final dates = report.rows
            .map((row) => DateTime.tryParse(row.dateStr))
            .whereType<DateTime>()
            .map((date) => DateTime(date.year, date.month, date.day))
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
        if (dates.length != report.rows.length) {
          await trace.fail('전체 차량 로그 CSV에 필요한 조회 날짜를 구성하지 못했습니다.');
          return;
        }
        trace.log(
          'raw=autoLoad area=$area dates=${dates.length} sectorEnabled=$sectorEnabled',
          progress: .16,
        );
        final loadedReport = await _deepLogService.loadByDates(
          division: widget.division.trim(),
          area: area,
          dates: dates,
          scopeLabel: report.rangeLabel,
          sectorEnabled: sectorEnabled,
          gcsLogUrls: expectedGcsLogUrls,
          onLog: (message) {
            trace?.log(message, progress: .18);
          },
        );
        if (!_deepReportMatchesChartReport(loadedReport, report)) {
          await trace.fail(
            '원본 차량 로그의 실제 날짜 범위가 비교 날짜 전체와 일치하지 않습니다.',
          );
          return;
        }
        deepReportForExport = loadedReport;
        if (mounted) {
          setState(() {
            _deepReport = loadedReport;
            _deepLabel = loadedReport.scopeLabel;
          });
        }
      }
      final exportReport = deepReportForExport;
      final deepSector = exportReport.sectorReport;
      if (sectorEnabled && report.sectorMetrics != null && deepSector == null) {
        await trace.fail('방문 구역 집계가 존재하지만 연결된 상세 GCS 보고서를 구성하지 못했습니다.');
        return;
      }
      if (deepSector != null) {
        for (final line in deepSector.integrity.debugLines) {
          trace.log(line, progress: .2);
        }
        for (final group in deepSector.groups) {
          trace.log(
            'sector=${group.sectorLabel} key=${group.key} '
            'vehicles=${group.vehicleCount} input=${group.inputCount} '
            'output=${group.outputCount} fee=${group.totalLockedFee}',
            progress: .22,
          );
        }
        if (!deepSector.integrity.isValid) {
          await trace.fail('화면·PDF 방문 구역 합계 무결성 검증에 실패했습니다.');
          return;
        }
        trace.log(
          'sector source total=${deepSector.totalVehicleCount} '
          'analyzable=${deepSector.analyzableVehicleCount} '
          'unavailable=${deepSector.unavailableVehicleCount} '
          'complete=${deepSector.sourceFieldComplete}',
          progress: .23,
        );
        final expectedSector = report.sectorMetrics;
        if (!deepSector.sourceFieldComplete) {
          trace.log(
            'sector cross validation skipped because source fields are unavailable for ${deepSector.unavailableVehicleCount} vehicles',
          );
        }
        if (expectedSector?.legacyFeeClassification == true) {
          trace.log('sector cross validation uses legacy fee classification warning');
        }
        if (expectedSector != null &&
            deepSector.sourceFieldComplete &&
            !expectedSector.legacyFeeClassification) {
          trace.log(
            'cross source expected=firestoreVerifiedDetailedGcsHistoryAggregate actual=gcsVerifiedHistoryLinkedCsvMerge',
            progress: .235,
          );
          final cross = _crossValidateSectorMetrics(
            expected: expectedSector,
            actual: deepSector,
          );
          for (final line in cross.debugLines) {
            trace.log(line, progress: .24);
          }
          if (!cross.isValid) {
            await trace.fail('검증된 상세 업무종료 history와 연결 GCS 로그의 방문 구역 합계가 일치하지 않습니다.');
            return;
          }
        }
      }

      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        await trace.fail('보고서 수신자 설정이 올바르지 않습니다.');
        return;
      }
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      if (!mounted) return;
      final pdfPalette = StatisticsReportDesign.pdfPalette(context);
      const numberingSchema = '01>02>03>04>05>06';
      trace.log(
        'pdf=build sectorGroups=${deepSector?.groups.length ?? 0} '
        'design=list-surface-v1 scope=full_area numbering=$numberingSchema '
        'raw=05.x appendix=06.x vehicleLog=excluded ${pdfPalette.debugLabel}',
        progress: .34,
      );
      _recordDebug(
        'pdf_build style=list-surface-v1 scope=full_area '
        'deep=true sectorGroups=${deepSector?.groups.length ?? 0} '
        'numbering=$numberingSchema raw=05.x appendix=06.x vehicleLog=excluded',
      );
      final pdfBytes = await _buildStatsPdfBytes(
        report: report,
        deepReport: exportReport,
        palette: pdfPalette,
      );
      final csvResult = StatisticsVehicleLogCsv.build(exportReport);
      final rangeTag = _reportRangeTag(report);
      final areaTag = area.isEmpty ? '전체' : area;
      final pdfFilename =
          '${_safeFileName('출차정산분석_${areaTag}_$rangeTag')}.pdf';
      final csvFilename =
          '${_safeFileName('전체차량로그_${areaTag}_$rangeTag')}.csv';
      trace.log(
        'pdf=ready bytes=${pdfBytes.length} filename=$pdfFilename',
        progress: .56,
      );
      trace.log(
        'csv=ready rows=${csvResult.rowCount} bytes=${csvResult.bytes.length} '
        'encoding=utf8_bom reuseDeepReport=true filename=$csvFilename',
        progress: .64,
      );
      _recordDebug(
        'csv_ready rows=${csvResult.rowCount} bytes=${csvResult.bytes.length} '
        'scope=full_area dates=${exportReport.dateStrs.length} '
        'encoding=utf8_bom reuseDeepReport=true duplicatesMerged=${exportReport.diagnostics.duplicateMergedCount}',
      );

      final attachments = <_MailAttachment>[
        _MailAttachment(
          filename: pdfFilename,
          mimeType: 'application/pdf',
          bytes: pdfBytes,
        ),
        _MailAttachment(
          filename: csvFilename,
          mimeType: 'text/csv; charset=utf-8',
          bytes: csvResult.bytes,
        ),
      ];
      trace.log(
        'attachments=${attachments.length} pdf=1 csv=1',
        progress: .72,
      );
      await _sendEmailViaGmail(
        attachments: attachments,
        to: toCsv,
        subject: subject,
        body: body,
      );
      trace.log('gmail=sent recipients=$toCsv attachments=2', progress: .92);
      await trace.succeed(
        deepSector != null
            ? '방문 구역 분석 PDF와 전체 차량 로그 CSV 발신이 완료되었습니다.'
            : '분석 PDF와 전체 차량 로그 CSV 발신이 완료되었습니다.',
      );
    } catch (e, st) {
      debugPrint('메일 전송 실패: $e');
      debugPrint('$st');
      if (trace != null) {
        await trace.fail(
          '통계 PDF·차량 CSV 생성 또는 발신에 실패했습니다.',
          error: e,
          stackTrace: st,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Uint8List> _buildStatsPdfBytes({
    required _ChartAReport report,
    required StatisticsPdfPalette palette,
    StatisticsDeepReport? deepReport,
  }) async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final data = await rootBundle.load(
        'assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf',
      );
      regular = pw.Font.ttf(data);
    } catch (error) {
      debugPrint('[STAT_PDF_DESIGN] regularFontFallback error=$error');
    }

    try {
      final data = await rootBundle.load(
        'assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf',
      );
      bold = pw.Font.ttf(data);
    } catch (error) {
      bold = regular;
      debugPrint('[STAT_PDF_DESIGN] boldFontFallback error=$error');
    }

    final theme = regular == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(
            base: regular,
            bold: bold ?? regular,
            italic: regular,
            boldItalic: bold ?? regular,
          );
    final design = StatisticsReportDesign.pdf(palette);
    final doc = pw.Document();
    final createdAt = DateTime.now();
    final activePdfSections = <String>[
      '01',
      '02',
      if (report.sectorMetrics != null) '03',
      '04',
      if (deepReport != null) '05',
      if (deepReport?.sectorReport != null) '06',
    ].join('>');
    debugPrint(
      '[STAT_PDF_DESIGN] build style=list-surface-v1 ${palette.debugLabel} '
      'days=${report.metrics.dayCount} deep=${deepReport != null} '
      'sector=${deepReport?.sectorReport != null} schema=01>02>03>04>05>06 active=$activePdfSections vehicleLog=excluded',
    );

    pw.Widget footer(pw.Context context) {
      return design.footer(
        context: context,
        createdAt: createdAt,
        labelText: 'PARKINWORKIN · 통계 분석 보고서',
      );
    }

    pw.Widget header(pw.Context context) {
      return design.runningHeader(
        reportTitle: '통계 분석 보고서',
        area: widget.area,
        rangeLabel: report.rangeLabel,
      );
    }

    final coverMetrics = <StatisticsPdfMetricData>[
      StatisticsPdfMetricData(
        label: '대상 날짜',
        value: '${report.metrics.dayCount}일',
        tone: StatisticsPdfTone.primary,
      ),
      StatisticsPdfMetricData(
        label: '출차 합계',
        value: '${_fmt(report.metrics.totalDeparture)}대',
        tone: StatisticsPdfTone.output,
      ),
      StatisticsPdfMetricData(
        label: '정산금 합계',
        value: '₩${_fmt(report.metrics.totalFee)}',
        tone: StatisticsPdfTone.fee,
      ),
      if (report.sectorMetrics != null)
        StatisticsPdfMetricData(
          label: '방문 구역',
          value: '${report.sectorMetrics!.sectorCount}개',
          tone: StatisticsPdfTone.secondary,
        ),
      if (report.sectorMetrics != null)
        StatisticsPdfMetricData(
          label: '구역 지정 차량',
          value: '${report.sectorMetrics!.assignedVehicleCount}대',
          tone: StatisticsPdfTone.success,
        ),
      if (report.sectorMetrics != null)
        StatisticsPdfMetricData(
          label: '미지정·확인 필요',
          value:
              '${report.sectorMetrics!.unassignedVehicleCount + report.sectorMetrics!.invalidSectorVehicleCount}대',
          tone: StatisticsPdfTone.warning,
        ),
      if (deepReport != null)
        StatisticsPdfMetricData(
          label: '원본 차량',
          value: '${_fmt(deepReport.rows.length)}대',
          tone: StatisticsPdfTone.input,
        ),
      if (deepReport != null)
        StatisticsPdfMetricData(
          label: '원본 입차',
          value: '${_fmt(deepReport.overallSection.metrics.inputTotalSum)}대',
          tone: StatisticsPdfTone.input,
        ),
      if (deepReport != null)
        StatisticsPdfMetricData(
          label: '원본 출차',
          value: '${_fmt(deepReport.overallSection.metrics.outputTotalSum)}대',
          tone: StatisticsPdfTone.output,
        ),
    ];

    final coverTags = <StatisticsPdfTagData>[
      if (widget.division.trim().isNotEmpty)
        StatisticsPdfTagData(
          label: widget.division.trim(),
          tone: StatisticsPdfTone.neutral,
        ),
      if (widget.area.trim().isNotEmpty)
        StatisticsPdfTagData(
          label: widget.area.trim(),
          tone: StatisticsPdfTone.primary,
        ),
      StatisticsPdfTagData(
        label: report.rangeLabel,
        tone: StatisticsPdfTone.secondary,
      ),
      const StatisticsPdfTagData(
        label: '운영 분석',
        tone: StatisticsPdfTone.output,
      ),
      if (deepReport != null)
        const StatisticsPdfTagData(
          label: '원본 로그 분석',
          tone: StatisticsPdfTone.input,
        ),
      if (deepReport?.sectorReport != null)
        const StatisticsPdfTagData(
          label: '방문 구역 분석',
          tone: StatisticsPdfTone.success,
        ),
    ];

    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => design.cover(
          reportCode: 'OPERATIONS REPORT',
          titleText: '통계 운영 분석 보고서',
          subtitle: '전체 Area의 운영 결과와 원본 로그 기반 분석을 한 흐름으로 정리했습니다.',
          description:
              '전체 Area 운영 결과를 요약한 공식 보고서입니다. 원본 로그가 준비된 범위는 시간대·결제·방문 구역 분석을 제공하며 차량 단위 로그는 별도 CSV로 첨부합니다.',
          createdAt: createdAt,
          tags: coverTags,
          metrics: coverMetrics,
          division: widget.division,
          area: widget.area,
          rangeLabel: report.rangeLabel,
        ),
      ),
    );

    final overviewSection = report.sections.firstWhere(
      (section) => section.type == _ChartASectionType.overview,
    );
    final dailySection = report.sections.firstWhere(
      (section) => section.type == _ChartASectionType.dailyTable,
    );

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: '운영 요약',
            subtitle: '전체 Area의 출차·정산·방문 구역 핵심 결과를 먼저 확인합니다.',
            eyebrow: 'OPERATIONS SUMMARY',
            sectionNumber: '01',
            tone: StatisticsPdfTone.primary,
          ),
          pw.SizedBox(height: 10),
          _pdfASectionMetrics(overviewSection, design),
          if (report.metrics.maxDeparture != null) ...[
            pw.SizedBox(height: 8),
            design.listRow(
              titleText: '최고 출차',
              subtitle: report.metrics.maxDeparture!.dateStr,
              trailing: '${_fmt(report.metrics.maxDeparture!.departure)}대',
              tone: StatisticsPdfTone.output,
              strong: true,
            ),
          ],
          if (report.metrics.maxFee != null)
            design.listRow(
              titleText: '최고 정산',
              subtitle: report.metrics.maxFee!.dateStr,
              trailing: '₩${_fmt(report.metrics.maxFee!.fee)}',
              tone: StatisticsPdfTone.fee,
              strong: true,
            ),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: '기간 변화',
            subtitle: '출차와 정산을 같은 날짜 조건으로 분리해 비교합니다.',
            eyebrow: 'PERIOD CHANGE',
            sectionNumber: '02',
            tone: StatisticsPdfTone.output,
          ),
          pw.SizedBox(height: 10),
          _pdfLineBars(
            design: design,
            title: '출차 흐름',
            subtitle: '날짜별 완료 차량의 출차 대수와 규모를 비교합니다.',
            rows: report.rows,
            valueOf: (row) => row.departure.toDouble(),
            suffix: '대',
            decimal: false,
            tone: StatisticsPdfTone.output,
          ),
          pw.SizedBox(height: 6),
          _pdfLineBars(
            design: design,
            title: '정산금 흐름',
            subtitle: '날짜별 잠금 정산금의 규모를 비교합니다.',
            rows: report.rows,
            valueOf: (row) => row.fee.toDouble(),
            suffix: '원',
            decimal: false,
            tone: StatisticsPdfTone.fee,
          ),
        ],
      ),
    );

    if (report.sectorMetrics != null) {
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
          header: header,
          footer: footer,
          build: (context) => [
            design.sectionHeader(
              titleText: '방문 구역',
              subtitle: '방문 구역별 차량 수, 잠금 금액과 전체 대비 비중을 확인합니다.',
              eyebrow: 'VISIT AREA',
              sectionNumber: '03',
              tone: StatisticsPdfTone.secondary,
            ),
            pw.SizedBox(height: 10),
            _pdfASectionMetrics(
              report.sections.firstWhere(
                (section) => section.type == _ChartASectionType.sector,
              ),
              design,
            ),
            pw.SizedBox(height: 8),
            _pdfSectorTable(report.sectorMetrics!, design),
            if (report.sectorMetrics!.legacyFeeClassification) ...[
              pw.SizedBox(height: 8),
              design.notice(
                titleText: '구버전 방문 구역 금액 분류',
                message:
                    '미지정과 데이터 확인 필요 잠금 금액이 통합되어 있을 수 있습니다.',
                tone: StatisticsPdfTone.warning,
                details: const <String>[
                  '차량 수는 분리되지만 과거 집계값만으로 금액을 정확히 재분류할 수 없습니다.',
                  '차량 단위 원천 값은 함께 발신되는 전체 차량 로그 CSV에서 확인할 수 있습니다.',
                ],
              ),
            ],
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: '날짜별 내역',
            subtitle: '날짜별 출차·정산·이전 비교일 변화와 기간 내 비중을 연속 목록으로 정리합니다.',
            eyebrow: 'DAILY RECORDS',
            sectionNumber: '04',
            tone: StatisticsPdfTone.neutral,
          ),
          pw.SizedBox(height: 8),
          _pdfARowsTable(dailySection.rows, design),
        ],
      ),
    );

    if (deepReport != null) {
      _addDeepReportSectionsToPdf(
        doc: doc,
        theme: theme,
        footer: footer,
        report: deepReport,
        design: design,
        rawSectionNumber: '05',
      );
      StatisticsSectorPdfBuilder.append(
        doc: doc,
        theme: theme,
        footer: footer,
        report: deepReport,
        design: design,
        sectionNumberPrefix: '06',
      );
    }

    final bytes = await doc.save();
    debugPrint(
      '[STAT_PDF_DESIGN] complete bytes=${bytes.length} style=list-surface-v1 schema=01>02>03>04>05>06 active=$activePdfSections vehicleLog=excluded',
    );
    _recordDebug(
      'pdf_complete style=list-surface-v1 bytes=${bytes.length} '
      'deep=${deepReport != null} sector=${deepReport?.sectorReport != null} numberingSchema=01>02>03>04>05>06 active=$activePdfSections vehicleLog=excluded',
    );
    return bytes;
  }

  pw.Widget _pdfASectionMetrics(
    _ChartASection section,
    StatisticsPdfDesign design,
  ) {
    final sector = section.sectorMetrics;
    if (section.type == _ChartASectionType.sector && sector != null) {
      return design.metricGrid([
        StatisticsPdfMetricData(
          label: '방문 구역',
          value: '${sector.sectorCount}개',
          tone: StatisticsPdfTone.secondary,
        ),
        StatisticsPdfMetricData(
          label: '지정 차량',
          value: '${sector.assignedVehicleCount}대',
          tone: StatisticsPdfTone.success,
        ),
        StatisticsPdfMetricData(
          label: '미지정 차량',
          value: '${sector.unassignedVehicleCount}대',
          tone: StatisticsPdfTone.warning,
        ),
        StatisticsPdfMetricData(
          label: '지정 잠금 금액',
          value: '₩${_fmt(sector.assignedLockedFee.round())}',
          tone: StatisticsPdfTone.fee,
        ),
        StatisticsPdfMetricData(
          label: '미지정 잠금 금액',
          value: '₩${_fmt(sector.unassignedLockedFee.round())}',
          tone: StatisticsPdfTone.warning,
        ),
        StatisticsPdfMetricData(
          label: '확인 필요 차량',
          value: '${sector.invalidSectorVehicleCount}대',
          caption: '₩${_fmt(sector.invalidSectorLockedFee.round())}',
          tone: StatisticsPdfTone.danger,
        ),
      ]);
    }

    return design.metricGrid([
      StatisticsPdfMetricData(
        label: '대상 날짜',
        value: '${section.metrics.dayCount}일',
        tone: StatisticsPdfTone.primary,
      ),
      StatisticsPdfMetricData(
        label: '출차 합계',
        value: '${_fmt(section.metrics.totalDeparture)}대',
        tone: StatisticsPdfTone.output,
      ),
      StatisticsPdfMetricData(
        label: '출차 평균',
        value: '${section.metrics.averageDeparture.toStringAsFixed(1)}대',
        tone: StatisticsPdfTone.output,
      ),
      StatisticsPdfMetricData(
        label: '정산금 합계',
        value: '₩${_fmt(section.metrics.totalFee)}',
        tone: StatisticsPdfTone.fee,
      ),
      StatisticsPdfMetricData(
        label: '정산금 평균',
        value: '₩${_fmt(section.metrics.averageFee.round())}',
        tone: StatisticsPdfTone.fee,
      ),
      StatisticsPdfMetricData(
        label: '최고 출차',
        value: section.metrics.maxDeparture == null
            ? '-'
            : '${section.metrics.maxDeparture!.departure}대',
        caption: section.metrics.maxDeparture?.dateStr,
        tone: StatisticsPdfTone.success,
      ),
    ]);
  }

  pw.Widget _pdfSectorTable(
    EndWorkSectorMetrics metrics,
    StatisticsPdfDesign design,
  ) {
    pw.Widget row({
      required String name,
      required int vehicles,
      required int fee,
      required double share,
      required StatisticsPdfTone tone,
    }) {
      return design.listRow(
        titleText: name,
        subtitle:
            '차량 ${_fmt(vehicles)}대 · 전체 대비 ${(share * 100).toStringAsFixed(1)}%',
        trailing: '₩${_fmt(fee)}',
        tone: tone,
        strong: true,
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final item in metrics.items)
          row(
            name: item.sectorName,
            vehicles: item.vehicleCount,
            fee: item.totalLockedFee.round(),
            share: metrics.assignedVehicleCount == 0
                ? 0
                : item.vehicleCount / metrics.assignedVehicleCount,
            tone: StatisticsPdfTone.secondary,
          ),
        if (metrics.unassignedVehicleCount > 0)
          row(
            name: '미지정',
            vehicles: metrics.unassignedVehicleCount,
            fee: metrics.unassignedLockedFee.round(),
            share: metrics.totalVehicleCount == 0
                ? 0
                : metrics.unassignedVehicleCount / metrics.totalVehicleCount,
            tone: StatisticsPdfTone.warning,
          ),
        if (metrics.invalidSectorVehicleCount > 0)
          row(
            name: '데이터 확인 필요',
            vehicles: metrics.invalidSectorVehicleCount,
            fee: metrics.invalidSectorLockedFee.round(),
            share: metrics.totalVehicleCount == 0
                ? 0
                : metrics.invalidSectorVehicleCount / metrics.totalVehicleCount,
            tone: StatisticsPdfTone.danger,
          ),
      ],
    );
  }

  pw.Widget _pdfLineBars({
    required StatisticsPdfDesign design,
    required String title,
    required String subtitle,
    required List<_ChartARow> rows,
    required double Function(_ChartARow row) valueOf,
    required String suffix,
    required bool decimal,
    required StatisticsPdfTone tone,
  }) {
    final safeRows = rows.isEmpty ? <_ChartARow>[] : rows;
    final maxValue = safeRows.fold<double>(0, (previous, row) {
      final value = valueOf(row);
      return value > previous ? value : previous;
    });
    final displayRows = safeRows.length > 28
        ? safeRows.sublist(0, 28)
        : safeRows;
    final accent = design.toneColor(tone);
    final track = design.toneSoft(tone);
    return design.chartCard(
      titleText: title,
      subtitle: subtitle,
      badge: displayRows.length == safeRows.length
          ? '${displayRows.length}일'
          : '상위 ${displayRows.length}일',
      tone: tone,
      child: displayRows.isEmpty
          ? design.notice(
              titleText: '표시할 데이터 없음',
              message: '선택한 범위에 그래프로 표시할 값이 없습니다.',
            )
          : pw.Column(
              children: [
                for (final row in displayRows)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 52,
                          child: pw.Text(
                            row.dateStr.length >= 5
                                ? row.dateStr.substring(5)
                                : row.dateStr,
                            style: design.body(
                              size: 7.8,
                              color: design.palette.muted,
                            ),
                          ),
                        ),
                        pw.Container(
                          width: 270,
                          height: 8,
                          alignment: pw.Alignment.centerLeft,
                          decoration: pw.BoxDecoration(
                            color: track,
                            borderRadius: pw.BorderRadius.circular(999),
                          ),
                          child: pw.Container(
                            width: maxValue <= 0
                                ? 0
                                : valueOf(row) / maxValue * 270,
                            height: 8,
                            decoration: pw.BoxDecoration(
                              color: accent,
                              borderRadius: pw.BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 7),
                        pw.Expanded(
                          child: pw.Text(
                            '${decimal ? valueOf(row).toStringAsFixed(1) : _fmt(valueOf(row).round())}$suffix',
                            textAlign: pw.TextAlign.right,
                            style: design.body(size: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  pw.Widget _pdfARowsTable(
    List<_ChartARow> rows,
    StatisticsPdfDesign design,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          design.listRow(
            titleText: row.dateStr,
            subtitle:
                '출차 ${_fmt(row.departure)}대 · ${(row.departureShare * 100).toStringAsFixed(1)}%   정산 ₩${_fmt(row.fee)} · ${(row.feeShare * 100).toStringAsFixed(1)}%',
            supporting:
                '이전 비교일  출차 ${_signed(row.departureDelta, suffix: '대')}   정산 ${_signed(row.feeDelta, prefix: '₩')}',
            trailing: row.no.toString().padLeft(2, '0'),
            tone: StatisticsPdfTone.neutral,
            strong: true,
          ),
      ],
    );
  }

  void _addDeepReportSectionsToPdf({
    required pw.Document doc,
    required pw.ThemeData theme,
    required pw.Widget Function(pw.Context context) footer,
    required StatisticsDeepReport report,
    required StatisticsPdfDesign design,
    required String rawSectionNumber,
  }) {
    pw.Widget header(pw.Context context) {
      return design.runningHeader(
        reportTitle: '원본 분석 보고서',
        area: report.area,
        rangeLabel: report.scopeLabel,
      );
    }

    List<StatisticsPdfMetricData> paymentMetrics(Map<String, int> items) {
      return [
        for (final entry in items.entries)
          StatisticsPdfMetricData(
            label: '${entry.key} 정산액',
            value: '₩${_fmt(entry.value)}',
            tone: StatisticsPdfTone.fee,
          ),
      ];
    }

    pw.Widget metricPanel(StatisticsDeepSection section) {
      return design.metricGrid([
        StatisticsPdfMetricData(
          label: '차량',
          value: '${section.rows.length}대',
          tone: StatisticsPdfTone.primary,
        ),
        StatisticsPdfMetricData(
          label: '대상 날짜',
          value: '${section.sourceDateCount}일',
          tone: StatisticsPdfTone.neutral,
        ),
        StatisticsPdfMetricData(
          label: '정산액',
          value: '₩${_fmt(section.totalFee)}',
          tone: StatisticsPdfTone.fee,
        ),
        StatisticsPdfMetricData(
          label: '입차 합계',
          value: '${_fmt(section.metrics.inputTotalSum)}대',
          tone: StatisticsPdfTone.input,
        ),
        StatisticsPdfMetricData(
          label: '출차 합계',
          value: '${_fmt(section.metrics.outputTotalSum)}대',
          tone: StatisticsPdfTone.output,
        ),
        StatisticsPdfMetricData(
          label: '평균 기준',
          value: '${section.sourceDateCount}일',
          tone: StatisticsPdfTone.secondary,
        ),
        ...paymentMetrics(section.feeByPaymentMethod),
      ]);
    }

    pw.Widget hourlyBars({
      required String title,
      required String subtitle,
      required List<num> values,
      required bool decimal,
      required StatisticsPdfTone tone,
    }) {
      final maxValue = values.fold<double>(0, (previous, value) {
        return value.toDouble() > previous ? value.toDouble() : previous;
      });
      final accent = design.toneColor(tone);
      final track = design.toneSoft(tone);
      return design.chartCard(
        titleText: title,
        subtitle: subtitle,
        badge: '24시간',
        tone: tone,
        child: pw.Column(
          children: [
            for (int hour = 0; hour < 24; hour++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3.4),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 31,
                      child: pw.Text(
                        '${hour.toString().padLeft(2, '0')}시',
                        style: design.body(
                          size: 7.2,
                          color: design.palette.muted,
                        ),
                      ),
                    ),
                    pw.Container(
                      width: 225,
                      height: 6.5,
                      alignment: pw.Alignment.centerLeft,
                      decoration: pw.BoxDecoration(
                        color: track,
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                      child: pw.Container(
                        width: maxValue <= 0
                            ? 0
                            : values[hour].toDouble() / maxValue * 225,
                        height: 6.5,
                        decoration: pw.BoxDecoration(
                          color: accent,
                          borderRadius: pw.BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Text(
                        '${decimal ? values[hour].toDouble().toStringAsFixed(1) : values[hour].toInt()}대',
                        textAlign: pw.TextAlign.right,
                        style: design.body(size: 7.2),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    pw.Widget chartSet(StatisticsDeepSection section) {
      final items = <pw.Widget>[
        hourlyBars(
          title: '입차 통산 합계',
          subtitle: '차량 생성 시각 기준 시간대별 완료 업무 분포',
          values: section.metrics.inputTotalCounts,
          decimal: false,
          tone: StatisticsPdfTone.input,
        ),
        pw.SizedBox(height: 9),
        hourlyBars(
          title: '출차 통산 합계',
          subtitle: '출차 완료 시각 기준 시간대별 완료 업무 분포',
          values: section.metrics.outputTotalCounts,
          decimal: false,
          tone: StatisticsPdfTone.output,
        ),
      ];
      if (section.showAverageCharts) {
        items.addAll([
          pw.SizedBox(height: 9),
          hourlyBars(
            title: '입차 1일 평균',
            subtitle: '${section.sourceDateCount}일 기준 시간대별 평균',
            values: section.metrics.inputAverageCounts,
            decimal: true,
            tone: StatisticsPdfTone.input,
          ),
          pw.SizedBox(height: 9),
          hourlyBars(
            title: '출차 1일 평균',
            subtitle: '${section.sourceDateCount}일 기준 시간대별 평균',
            values: section.metrics.outputAverageCounts,
            decimal: true,
            tone: StatisticsPdfTone.output,
          ),
        ]);
      }
      return pw.Column(children: items);
    }


    void addSection(
      StatisticsDeepSection section, {
      required String sectionNumber,
    }) {
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(26, 25, 26, 30),
          header: header,
          footer: footer,
          build: (context) => [
            design.sectionHeader(
              titleText: section.title,
              subtitle: section.subtitle,
              eyebrow: '원본 로그 분석',
              sectionNumber: sectionNumber,
              tone: StatisticsPdfTone.input,
            ),
            pw.SizedBox(height: 12),
            metricPanel(section),
            pw.SizedBox(height: 12),
            chartSet(section),
          ],
        ),
      );
    }

    addSection(
      report.overallSection,
      sectionNumber: rawSectionNumber,
    );
    var rawSubsectionIndex = 1;
    for (final section in report.dailySections) {
      addSection(
        section,
        sectionNumber: '$rawSectionNumber.${rawSubsectionIndex++}',
      );
    }
    for (final section in report.weekdaySections) {
      addSection(
        section,
        sectionNumber: '$rawSectionNumber.${rawSubsectionIndex++}',
      );
    }
  }

  Future<void> _sendEmailViaGmail({
    required List<_MailAttachment> attachments,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GmailSenderAuth.client();
    final api = gmail.GmailApi(client);

    try {
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
        ..writeln(body);

      for (final attachment in attachments) {
        sb
          ..writeln()
          ..writeln('--$boundary')
          ..writeln(
            'Content-Type: ${attachment.mimeType}; name="${attachment.filename}"',
          )
          ..writeln(
            'Content-Disposition: attachment; filename="${attachment.filename}"',
          )
          ..writeln('Content-Transfer-Encoding: base64')
          ..writeln()
          ..writeln(base64.encode(attachment.bytes));
      }
      sb.writeln('--$boundary--');

      final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
      final msg = gmail.Message()..raw = raw;
      await api.users.messages.send(msg, 'me');
    } finally {
      client.close();
    }
  }


  Future<void> _loadRawAnalysis(
    _ChartAReport report,
    _DeepLoadRequest request,
    _AnalyticsSection targetSection,
  ) async {
    if (_deepLoading) return;

    final division = widget.division.trim();
    final area = widget.area.trim();
    if (division.isEmpty || area.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('원본 분석에 필요한 사업부/지역 정보가 없습니다.')),
      );
      return;
    }

    setState(() {
      _deepLoading = true;
      _deepProgressCurrent = 0;
      _deepProgressTotal = 0;
    });
    _recordDebug(
      'raw_load_start target=${targetSection.name} scope=${request.label}',
    );
    DeveloperOperationTrace? trace;
    try {
      final sectorEnabled = widget.areaSectorEnabled[area] == true;
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '통계 원본 분석',
        initialMessage: '완료 업무 원본 로그를 조회하고 분석하고 있습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 원본 집계·Sector·무결성 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 원본 분석 로그를 콘솔에 기록합니다.',
      );
      trace.log(
        'division=$division area=$area scope=${request.label} '
        'dates=${request.isRange ? 'range' : request.dates.length} '
        'sectorEnabled=$sectorEnabled target=${targetSection.name}',
        progress: .08,
      );

      final selectedRows = _rowsForRequest(report, request);
      if (selectedRows.isEmpty) {
        await trace.fail('선택 범위에 저장된 통계 보고서가 없습니다.');
        return;
      }
      final missingRawRows = _rowsMissingRawSources(selectedRows);
      final availableRawDateCount = selectedRows.length - missingRawRows.length;
      final missingRawDates = missingRawRows.map((row) => row.dateStr).join(',');
      trace.log(
        'rawCoverage=$availableRawDateCount/${selectedRows.length} missing=${missingRawDates.isEmpty ? '-' : missingRawDates}',
        progress: .1,
      );
      _recordDebug(
        'raw_scope_coverage target=${targetSection.name} available=$availableRawDateCount/${selectedRows.length} missing=${missingRawDates.isEmpty ? '-' : missingRawDates}',
      );
      if (missingRawRows.isNotEmpty) {
        await trace.fail(
          '선택 범위의 모든 날짜에 검증된 원본 차량 로그가 필요합니다. 원본이 없는 날짜: ${missingRawRows.map((row) => row.dateStr).join(', ')}',
        );
        return;
      }
      final selectedDates = selectedRows.map((row) => row.date).toList();
      final linkedGcsLogUrls = _historyLogUrlsForRequest(report, request);
      for (final row in selectedRows) {
        trace.log(
          'history date=${row.dateStr} entries=${row.historyEntryCount} '
          'detailedGcs=${row.historyDetailedEntryCount} '
          'excluded=${row.historyExcludedEntryCount} '
          'first=${row.historyFirstEntryCount} '
          'unverifiedDetailed=${row.historyUnverifiedDetailedEntryCount} '
          'legacyDetailed=${row.historyLegacyDetailedEntryCount} '
          'linkedLogs=${row.historyLogsUrls.length} '
          'sectorEntries=${row.historySectorEntryCount} '
          'mode=${row.historyAggregationMode}',
          progress: .12,
        );
      }
      trace.log(
        'source=verifiedDetailedGcsHistory selectedDates=${selectedDates.length} linkedLogs=${linkedGcsLogUrls.length}',
        progress: .16,
      );
      if (linkedGcsLogUrls.isEmpty) {
        await trace.fail('선택 범위에 검증된 상세 업무종료 GCS 로그가 없습니다.');
        return;
      }

      final deep = await _deepLogService.loadByDates(
        division: division,
        area: area,
        dates: selectedDates,
        scopeLabel: request.label,
        sectorEnabled: sectorEnabled,
        gcsLogUrls: linkedGcsLogUrls,
        onLog: (message) {
          trace?.log(message, progress: .24);
          _recordDebug(message);
        },
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _deepProgressCurrent = current;
            _deepProgressTotal = total;
          });
        },
      );

      trace.log(
        'objects=${deep.diagnostics.sourceObjectCount} '
        'csvRows=${deep.diagnostics.sourceCsvRowCount} '
        'vehicles=${deep.diagnostics.mergedVehicleCount} '
        'duplicates=${deep.diagnostics.duplicateMergedCount} '
        'sectorConflicts=${deep.diagnostics.sectorConflictCount} '
        'identityConflicts=${deep.diagnostics.sectorIdentityConflictCount} '
        'sectorFields=${deep.diagnostics.sectorFieldPresentCount}/${deep.rows.length}',
        progress: .56,
      );
      final sector = deep.sectorReport;
      if (sector != null) {
        for (final line in sector.integrity.debugLines) {
          trace.log(line, progress: .68);
        }
      }
      if (sectorEnabled && sector == null) {
        await trace.fail('Sector 지원 Area이지만 Sector 보고서가 생성되지 않았습니다.');
        return;
      }
      if (sector != null && !sector.integrity.isValid) {
        await trace.fail('원본 분석 Sector 합계 무결성 검증에 실패했습니다.');
        return;
      }
      final expectedSector = _sectorMetricsForRequest(report, request);
      if (sector != null &&
          expectedSector != null &&
          sector.sourceFieldComplete &&
          !expectedSector.legacyFeeClassification) {
        final cross = _crossValidateSectorMetrics(
          expected: expectedSector,
          actual: sector,
        );
        for (final line in cross.debugLines) {
          trace.log(line, progress: .84);
        }
        if (!cross.isValid) {
          await trace.fail(
            '검증된 상세 업무종료 history와 연결 GCS 로그의 Sector 합계가 일치하지 않습니다.',
          );
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _deepReport = deep;
        _deepLabel = deep.scopeLabel;
        _selectedSection = targetSection;
        if (_selectedObservation == null && deep.dateStrs.isNotEmpty) {
          _selectedObservation = DateTime.tryParse(deep.dateStrs.last);
        }
        if (deep.weekdaySections.isNotEmpty) {
          _selectedWeekdaySectionId ??= deep.weekdaySections.first.id;
        }
      });
      _recordDebug(
        'raw_load_success target=${targetSection.name} scope=${deep.scopeLabel} objects=${deep.objectNames.length} vehicles=${deep.rows.length}',
      );
      await trace.succeed(
        sectorEnabled
            ? '원본 로그와 방문 구역 검증이 완료되었습니다.'
            : '원본 로그 분석이 완료되었습니다.',
      );
    } catch (e, st) {
      _recordDebug('raw_load_failed error=$e');
      debugPrint('[STAT_DEEP] load failed: $e');
      debugPrint('$st');
      if (trace != null) {
        await trace.fail(
          '원본 로그 분석에 실패했습니다.',
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('원본 로그 분석 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _deepLoading = false);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final baseReport = _ChartAReport.from(
      widget.reportDataMap,
      sectorEnabled: widget.areaSectorEnabled[widget.area.trim()] == true,
    );
    final scopeOptions = _analyticsScopeOptions(baseReport);
    final activeScope = _resolveAnalyticsScope(scopeOptions, _selectedScope);
    final report = _scopeChartReport(baseReport, activeScope);
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectedObservation = _effectiveObservation(report);
    final eligibleAreas = widget.availableAreas
        .where((area) => widget.areaSectorEnabled[area] == true)
        .toSet()
        .toList()
      ..sort();

    return PopScope(
      canPop: !_sending && !_deepLoading,
      child: ColoredBox(
        color: cs.surface,
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _AnalyticsHeader(
                      area: widget.area,
                      rangeLabel: report.rangeLabel,
                      dayCount: report.metrics.dayCount,
                      scopeLabel: activeScope.label,
                      deepLabel: _deepLabel,
                      loading: _deepLoading,
                      progressCurrent: _deepProgressCurrent,
                      progressTotal: _deepProgressTotal,
                      onClose: _sending || _deepLoading
                          ? null
                          : () => Navigator.of(context).maybePop(),
                    ),
                    if (scopeOptions.length > 1)
                      _AnalyticsScopeBar(
                        scopes: scopeOptions,
                        selected: activeScope,
                        onSelected: _selectScope,
                      ),
                    Divider(height: 1, color: cs.outlineVariant),
                    Expanded(
                      child: baseReport.rows.isEmpty
                          ? const _AEmptyState()
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: Offstage(
                                    offstage: _selectedSection ==
                                        _AnalyticsSection.areaComparison,
                                    child: AnimatedSwitcher(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : CommonUiMotion.selection,
                                      switchInCurve: CommonUiMotion.enter,
                                      switchOutCurve: CommonUiMotion.exit,
                                      transitionBuilder: (child, animation) {
                                        if (reduceMotion) return child;
                                        final offset = Tween<Offset>(
                                          begin: const Offset(0, 0.018),
                                          end: Offset.zero,
                                        ).animate(animation);
                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: offset,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: KeyedSubtree(
                                        key: ValueKey<String>(
                                          '${_selectedSection.name}|${_selectedMetric.name}|${activeScope.key}|${selectedObservation?.toIso8601String() ?? '-'}|${_deepReport?.scopeLabel ?? '-'}',
                                        ),
                                        child: _buildAnalyticsContent(
                                          report: report,
                                          baseReport: baseReport,
                                          scope: activeScope,
                                          selectedObservation:
                                              selectedObservation,
                                          eligibleAreas: eligibleAreas,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (eligibleAreas.length >= 2)
                                  Positioned.fill(
                                    child: Offstage(
                                      offstage: _selectedSection !=
                                          _AnalyticsSection.areaComparison,
                                      child: StatisticsSectorAreaComparisonPage(
                                        key: _areaComparisonKey,
                                        division: widget.division,
                                        areas: eligibleAreas,
                                        dates: baseReport.rows
                                            .map((row) => row.date)
                                            .toList(),
                                        useCommonUi: true,
                                        embedded: true,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
              _AnalyticsRail(
                selectedSection: _selectedSection,
                sectorAvailable: baseReport.sectorMetrics != null,
                areaComparisonAvailable: eligibleAreas.length >= 2,
                developerMode: _developerMode,
                sending: _sending,
                rawLoading: _deepLoading,
                rawReady: _deepReport != null,
                onSelect: (section) => _selectSection(
                  section,
                  scope: activeScope,
                  selectedObservation: selectedObservation,
                ),
                onPdf: _sending
                    ? null
                    : () => _openMailDialogAndSend(baseReport),
                onDeveloper: !_developerMode
                    ? null
                    : () => _showDeveloperStatus(baseReport),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime? _effectiveObservation(_ChartAReport report) {
    if (report.rows.isEmpty) return null;
    final selected = _selectedObservation;
    if (selected != null && report.rows.any((row) => _sameDate(row.date, selected))) {
      return selected;
    }
    return report.rows.last.date;
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _selectSection(
    _AnalyticsSection section, {
    required _AnalyticsScope scope,
    required DateTime? selectedObservation,
  }) {
    HapticFeedback.selectionClick();
    _recordDebug(
      'rail_select section=${section.name} scope=${scope.label} observation=${selectedObservation == null ? '-' : _dateOnly(selectedObservation)} deepReady=${_deepReport != null}',
    );
    setState(() {
      _selectedSection = section;
      if (section == _AnalyticsSection.areaComparison) {
        _selectedScope = const _AnalyticsScope.all();
      }
    });
  }

  void _selectScope(_AnalyticsScope scope) {
    if (scope.key == _selectedScope.key) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedScope = scope);
    _recordDebug(
      'scope_select key=${scope.key} label=${scope.label} rawReuse=${_deepReport != null}',
    );
  }

  Widget _buildAnalyticsContent({
    required _ChartAReport report,
    required _ChartAReport baseReport,
    required _AnalyticsScope scope,
    required DateTime? selectedObservation,
    required List<String> eligibleAreas,
  }) {
    switch (_selectedSection) {
      case _AnalyticsSection.overview:
        return _AnalyticsOverviewView(
          report: report,
          scopeLabel: scope.label,
          selectedObservation: selectedObservation,
          onSelectObservation: _selectObservation,
        );
      case _AnalyticsSection.trend:
        return _AnalyticsTrendView(
          report: report,
          scopeLabel: scope.label,
          metric: _selectedMetric,
          selectedObservation: selectedObservation,
          onMetricChanged: (metric) {
            HapticFeedback.selectionClick();
            setState(() => _selectedMetric = metric);
            _recordDebug('trend_metric=${metric.name}');
          },
          onSelectObservation: _selectObservation,
        );
      case _AnalyticsSection.sector:
        final metrics = baseReport.sectorMetrics;
        if (metrics == null) {
          return const _AnalyticsEmptyView(
            icon: Icons.grid_off_rounded,
            title: '방문 구역 데이터가 없습니다.',
            description: '이 Area 또는 선택 날짜에는 방문 구역 집계가 없습니다.',
          );
        }
        return _AnalyticsSectorView(
          metrics: metrics,
          selectedScope: scope,
          onScopeSelected: _selectScope,
        );
      case _AnalyticsSection.detail:
        return _AnalyticsDetailView(
          rows: report.rows,
          selectedObservation: selectedObservation,
          onSelectObservation: _selectObservation,
        );
      case _AnalyticsSection.areaComparison:
        if (eligibleAreas.length < 2) {
          return const _AnalyticsEmptyView(
            icon: Icons.compare_arrows_rounded,
            title: '비교 가능한 Area가 부족합니다.',
            description: '방문 구역을 지원하는 Area가 2개 이상 필요합니다.',
          );
        }
        return const SizedBox.shrink();
      case _AnalyticsSection.hourly:
        return _buildRawSectionGate(
          report: baseReport,
          scope: scope,
          selectedObservation: selectedObservation,
          target: _AnalyticsSection.hourly,
          readyBuilder: (deep) => _AnalyticsHourlyView(
            report: deep,
            selectedObservation: selectedObservation,
            metric: _hourlyMetric,
            onMetricChanged: (metric) {
              HapticFeedback.selectionClick();
              setState(() => _hourlyMetric = metric);
              _recordDebug('hourly_metric=${metric.name}');
            },
          ),
        );
      case _AnalyticsSection.payment:
        return _buildRawSectionGate(
          report: baseReport,
          scope: scope,
          selectedObservation: selectedObservation,
          target: _AnalyticsSection.payment,
          readyBuilder: (deep) => _AnalyticsPaymentView(
            report: deep,
            selectedObservation: selectedObservation,
            metric: _paymentMetric,
            onMetricChanged: (metric) {
              HapticFeedback.selectionClick();
              setState(() => _paymentMetric = metric);
              _recordDebug('payment_metric=${metric.name}');
            },
          ),
        );
      case _AnalyticsSection.weekday:
        return _buildRawSectionGate(
          report: baseReport,
          scope: scope,
          selectedObservation: selectedObservation,
          target: _AnalyticsSection.weekday,
          requireWholeComparison: true,
          readyBuilder: (deep) => _AnalyticsWeekdayView(
            report: deep,
            selectedId: _selectedWeekdaySectionId,
            onSelect: (id) {
              HapticFeedback.selectionClick();
              setState(() => _selectedWeekdaySectionId = id);
              _recordDebug('weekday_select=$id');
            },
          ),
        );
    }
  }

  Widget _buildRawSectionGate({
    required _ChartAReport report,
    required _AnalyticsScope scope,
    required DateTime? selectedObservation,
    required _AnalyticsSection target,
    required Widget Function(StatisticsDeepReport deep) readyBuilder,
    bool requireWholeComparison = false,
  }) {
    final deep = _deepReport;
    final selectedKey = selectedObservation == null
        ? null
        : _dateOnly(selectedObservation);
    final selectedReady = deep != null &&
        (selectedKey == null || deep.dateStrs.contains(selectedKey));
    final wholeReady = deep != null && _deepReportMatchesChartReport(deep, report);
    if (deep != null && (requireWholeComparison ? wholeReady : selectedReady)) {
      return readyBuilder(_scopeDeepReport(deep, scope));
    }

    _ChartARow? selectedRow;
    if (selectedObservation != null) {
      for (final row in report.rows) {
        if (_sameDate(row.date, selectedObservation)) {
          selectedRow = row;
          break;
        }
      }
    }
    final selectedAvailable = selectedRow != null && _rowHasRawSource(selectedRow);
    final availableDateCount =
        report.rows.where(_rowHasRawSource).length;
    final allAvailable = report.rows.isNotEmpty &&
        availableDateCount == report.rows.length;
    final title = switch (target) {
      _AnalyticsSection.hourly => '시간대 분석',
      _AnalyticsSection.payment => '결제 분석',
      _AnalyticsSection.weekday => '요일 분석',
      _ => '원본 분석',
    };
    return _RawAnalysisGate(
      title: title,
      loading: _deepLoading,
      progressCurrent: _deepProgressCurrent,
      progressTotal: _deepProgressTotal,
      selectedDate: selectedObservation,
      selectedAvailable: selectedAvailable && !requireWholeComparison,
      allAvailable: allAvailable,
      availableDateCount: availableDateCount,
      totalDateCount: report.rows.length,
      onSelected: selectedAvailable && !requireWholeComparison && selectedObservation != null
          ? () => _loadRawAnalysis(
                report,
                _DeepLoadRequest.dates(
                  dates: <DateTime>[selectedObservation],
                  label: _dateOnly(selectedObservation),
                ),
                target,
              )
          : null,
      onAll: allAvailable
          ? () => _loadRawAnalysis(
                report,
                _DeepLoadRequest.dates(
                  dates: report.rows.map((row) => row.date).toList(),
                  label: report.rangeLabel,
                ),
                target,
              )
          : null,
    );
  }

  void _selectObservation(DateTime value) {
    HapticFeedback.selectionClick();
    setState(() => _selectedObservation = value);
    _recordDebug('observation_select=${_dateOnly(value)}');
  }

  Future<void> _showDeveloperStatus(_ChartAReport report) async {
    if (!_developerMode || !mounted) return;
    final selectedObservation = _effectiveObservation(report);
    final missingRawRows = _rowsMissingRawSources(report.rows);
    final availableRawDateCount = report.rows.length - missingRawRows.length;
    final missingRawDates = missingRawRows.map((row) => row.dateStr).join(',');
    final activeScope = _resolveAnalyticsScope(
      _analyticsScopeOptions(report),
      _selectedScope,
    );
    final scopedReport = _scopeChartReport(report, activeScope);
    final deepForStatus = _deepReport;
    final scopedDeep = deepForStatus == null
        ? null
        : _scopeDeepReport(deepForStatus, activeScope);
    final csvFullScopeReady = deepForStatus != null &&
        _deepReportMatchesChartReport(deepForStatus, report);
    final csvRows = csvFullScopeReady ? deepForStatus.rows.length : 0;
    _recordDebug(
      'developer_status_open section=${_selectedSection.name} scope=${activeScope.label} metric=${_selectedMetric.name} observation=${selectedObservation == null ? '-' : _dateOnly(selectedObservation)} rawCoverage=$availableRawDateCount/${report.rows.length} rawMissing=${missingRawDates.isEmpty ? '-' : missingRawDates} deepReady=${_deepReport != null} deepCache=${StatisticsDeepLogService.memoryCacheSize} deepHits=${StatisticsDeepLogService.cacheHits} deepDownloads=${StatisticsDeepLogService.gcsDownloads} deepBytes=${StatisticsDeepLogService.gcsDownloadedBytes}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '통계 분석 상태',
      initialMessage: 'Analytics Side Dock 상태와 원본 분석 비용 정보를 수집하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    if (!trace.developerMode) return;
    final media = MediaQuery.maybeOf(context);
    trace.log(
      'division=${widget.division}, area=${widget.area}, range=${report.rangeLabel}, days=${report.rows.length}, section=${_selectedSection.name}, scope=${activeScope.label}, scopeKey=${activeScope.key}, metric=${_selectedMetric.name}, observation=${selectedObservation == null ? '-' : _dateOnly(selectedObservation)}',
      progress: .18,
    );
    trace.log(
      'departure=${report.metrics.totalDeparture}, fee=${report.metrics.totalFee}, sectorAvailable=${report.sectorMetrics != null}, availableAreas=${widget.availableAreas.length}',
      progress: .3,
    );
    trace.log(
      'scope=${activeScope.label}, scopeDeparture=${scopedReport.metrics.totalDeparture}, scopeFee=${scopedReport.metrics.totalFee}, scopeRawVehicles=${scopedDeep?.rows.length ?? 0}',
      progress: .4,
    );
    trace.log(
      'rawCoverage=$availableRawDateCount/${report.rows.length}, rawMissing=${missingRawDates.isEmpty ? '-' : missingRawDates}, rawReady=${_deepReport != null}, rawScope=${_deepReport?.scopeLabel ?? '-'}, rawSampleDates=${_deepReport?.dateStrs.length ?? 0}, rawObjects=${_deepReport?.objectNames.length ?? 0}, rawVehicles=${_deepReport?.rows.length ?? 0}, progress=$_deepProgressCurrent/$_deepProgressTotal',
      progress: .52,
    );
    trace.log(
      'deepMemoryCache=${StatisticsDeepLogService.memoryCacheSize}, deepCacheHits=${StatisticsDeepLogService.cacheHits}, deepGcsDownloads=${StatisticsDeepLogService.gcsDownloads}, deepGcsBytes=${StatisticsDeepLogService.gcsDownloadedBytes}, reduceMotion=${media?.disableAnimations ?? false}',
      progress: .62,
    );
    trace.log(
      'pdfDesign=list-surface-v1, pdfScope=full_area, pdfVehicleLog=excluded, pdfNumberingSchema=01>02>03>04>05>06, pdfRawSubsections=05.x, pdfSectorAppendix=06.x, csvVehicleLog=attached_on_send, csvEncoding=utf8_bom, csvRows=$csvRows, csvFullScopeReady=$csvFullScopeReady, csvReuseDeepReport=$csvFullScopeReady, attachments=2',
      progress: .65,
    );
    final chartLogs = StatisticsChartInteractionLog.lines;
    trace.log(
      'chartInteractions=${chartLogs.length}',
      progress: .66,
    );
    for (var i = 0; i < chartLogs.length; i++) {
      trace.log(
        chartLogs[i],
        progress: .66 + ((i + 1) / math.max(chartLogs.length, 1)) * .12,
      );
    }
    final snapshot = List<String>.of(_debugLines);
    for (var i = 0; i < snapshot.length; i++) {
      trace.log(
        snapshot[i],
        progress: .78 + ((i + 1) / math.max(snapshot.length, 1)) * .18,
      );
    }
    await trace.succeed('통계 분석 상태 수집이 완료되었습니다.');
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '출차정산분석' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _dateTag(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
  }

  String _reportRangeTag(_ChartAReport report) {
    if (report.rows.isEmpty) return _dateTag(DateTime.now());
    final dates = report.rows.map((row) => row.date).toList()
      ..sort((a, b) => a.compareTo(b));
    final first = _dateTag(dates.first);
    final last = _dateTag(dates.last);
    return first == last ? first : '$first-$last';
  }

}


class _AnalyticsHeader extends StatelessWidget {
  final String area;
  final String rangeLabel;
  final int dayCount;
  final String scopeLabel;
  final String? deepLabel;
  final bool loading;
  final int progressCurrent;
  final int progressTotal;
  final VoidCallback? onClose;

  const _AnalyticsHeader({
    required this.area,
    required this.rangeLabel,
    required this.dayCount,
    required this.scopeLabel,
    required this.deepLabel,
    required this.loading,
    required this.progressCurrent,
    required this.progressTotal,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '출차·정산 분석',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${area.trim().isEmpty ? 'Area 미지정' : area.trim()} · $rangeLabel · 비교 $dayCount일 · $scopeLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (loading || deepLabel != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    loading
                        ? progressTotal > 0
                            ? '원본 로그 분석 중 · $progressCurrent / $progressTotal'
                            : '원본 로그 분석 준비 중'
                        : '원본 분석 준비됨 · $deepLabel',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: loading ? cs.primary : cs.tertiary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}


class _AnalyticsScopeBar extends StatelessWidget {
  final List<_AnalyticsScope> scopes;
  final _AnalyticsScope selected;
  final ValueChanged<_AnalyticsScope> onSelected;

  const _AnalyticsScopeBar({
    required this.scopes,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 9),
      color: cs.surface,
      child: Row(
        children: [
          Text(
            '분석 범위',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < scopes.length; i++) ...[
                    ChoiceChip(
                      label: Text(scopes[i].label),
                      selected: scopes[i].key == selected.key,
                      onSelected: (_) => onSelected(scopes[i]),
                    ),
                    if (i != scopes.length - 1) const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsRail extends StatelessWidget {
  final _AnalyticsSection selectedSection;
  final bool sectorAvailable;
  final bool areaComparisonAvailable;
  final bool developerMode;
  final bool sending;
  final bool rawLoading;
  final bool rawReady;
  final ValueChanged<_AnalyticsSection> onSelect;
  final VoidCallback? onPdf;
  final VoidCallback? onDeveloper;

  const _AnalyticsRail({
    required this.selectedSection,
    required this.sectorAvailable,
    required this.areaComparisonAvailable,
    required this.developerMode,
    required this.sending,
    required this.rawLoading,
    required this.rawReady,
    required this.onSelect,
    required this.onPdf,
    required this.onDeveloper,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            _AnalyticsRailButton(
              icon: Icons.dashboard_rounded,
              tooltip: '개요',
              selected: selectedSection == _AnalyticsSection.overview,
              onTap: () => onSelect(_AnalyticsSection.overview),
            ),
            _AnalyticsRailButton(
              icon: Icons.show_chart_rounded,
              tooltip: '추이',
              selected: selectedSection == _AnalyticsSection.trend,
              onTap: () => onSelect(_AnalyticsSection.trend),
            ),
            if (sectorAvailable)
              _AnalyticsRailButton(
                icon: Icons.grid_view_rounded,
                tooltip: '방문 구역',
                selected: selectedSection == _AnalyticsSection.sector,
                onTap: () => onSelect(_AnalyticsSection.sector),
              ),
            _AnalyticsRailButton(
              icon: Icons.table_chart_rounded,
              tooltip: '상세',
              selected: selectedSection == _AnalyticsSection.detail,
              onTap: () => onSelect(_AnalyticsSection.detail),
            ),
            const SizedBox(height: 8),
            Divider(indent: 12, endIndent: 12, color: cs.outlineVariant),
            Text(
              '원본',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
            ),
            const SizedBox(height: 4),
            _AnalyticsRailButton(
              icon: Icons.schedule_rounded,
              tooltip: '시간대 · 원본 로그 기반',
              selected: selectedSection == _AnalyticsSection.hourly,
              badge: rawLoading ? '…' : rawReady ? '✓' : null,
              onTap: () => onSelect(_AnalyticsSection.hourly),
            ),
            _AnalyticsRailButton(
              icon: Icons.payments_rounded,
              tooltip: '결제 · 원본 로그 기반',
              selected: selectedSection == _AnalyticsSection.payment,
              badge: rawReady ? '✓' : null,
              onTap: () => onSelect(_AnalyticsSection.payment),
            ),
            _AnalyticsRailButton(
              icon: Icons.calendar_view_week_rounded,
              tooltip: '요일 · 원본 로그 기반',
              selected: selectedSection == _AnalyticsSection.weekday,
              badge: rawReady ? '✓' : null,
              onTap: () => onSelect(_AnalyticsSection.weekday),
            ),
            if (areaComparisonAvailable)
              _AnalyticsRailButton(
                icon: Icons.compare_arrows_rounded,
                tooltip: 'Area 방문 구역 비교',
                selected: selectedSection == _AnalyticsSection.areaComparison,
                onTap: () => onSelect(_AnalyticsSection.areaComparison),
              ),
            const Spacer(),
            Divider(indent: 12, endIndent: 12, color: cs.outlineVariant),
            _AnalyticsRailButton(
              icon: sending ? Icons.hourglass_top_rounded : Icons.attach_file_rounded,
              tooltip: sending ? '보고서 준비 중' : 'PDF + 차량 CSV 발신',
              selected: false,
              onTap: onPdf,
            ),
            if (developerMode)
              _AnalyticsRailButton(
                icon: Icons.terminal_rounded,
                tooltip: '개발자 상태',
                selected: false,
                onTap: onDeveloper,
              ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsRailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  const _AnalyticsRailButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.enter,
            width: 48,
            height: 46,
            decoration: BoxDecoration(
              color: selected ? cs.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    if (reduceMotion) return child;
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: .88, end: 1).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Icon(
                    icon,
                    key: ValueKey<int>(icon.codePoint),
                    color: selected
                        ? cs.onSecondaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
                if (badge != null)
                  Positioned(
                    right: 4,
                    top: 3,
                    child: Text(
                      badge!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsOverviewView extends StatelessWidget {
  final _ChartAReport report;
  final String scopeLabel;
  final DateTime? selectedObservation;
  final ValueChanged<DateTime> onSelectObservation;

  const _AnalyticsOverviewView({
    required this.report,
    required this.scopeLabel,
    required this.selectedObservation,
    required this.onSelectObservation,
  });

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsMetricBand(metrics: m),
          const SizedBox(height: 22),
          _AnalyticsSectionTitle(
            icon: Icons.insights_rounded,
            title: '기간 흐름',
            subtitle: report.rows.length < 3
                ? '선택한 날짜 사이의 직접 변화를 비교합니다.'
                : '출차와 정산을 같은 날짜 축에서 각각 확인합니다.',
          ),
          const SizedBox(height: 12),
          _AnalyticsAdaptiveOverviewTrend(
            rows: report.rows,
            scopeLabel: scopeLabel,
          ),
          const SizedBox(height: 22),
          _AnalyticsSectionTitle(
            icon: Icons.bolt_rounded,
            title: '주요 변화',
            subtitle: '선택한 데이터에서 확인되는 관측값만 정리합니다.',
          ),
          const SizedBox(height: 10),
          _AnalyticsInsightList(report: report),
          const SizedBox(height: 22),
          _ObservationSelector(
            rows: report.rows,
            selectedObservation: selectedObservation,
            onSelected: onSelectObservation,
          ),
        ],
      ),
    );
  }
}

class _AnalyticsMetricBand extends StatelessWidget {
  final _ChartAMetrics metrics;

  const _AnalyticsMetricBand({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final children = [
            _AnalyticsMetricBlock(
              label: '출차',
              value: '${_fmt(metrics.totalDeparture)}대',
              secondary: '선택일 평균 ${metrics.averageDeparture.toStringAsFixed(1)}대',
            ),
            _AnalyticsMetricBlock(
              label: '정산',
              value: '₩${_fmt(metrics.totalFee)}',
              secondary: '선택일 평균 ₩${_fmt(metrics.averageFee.round())}',
            ),
          ];
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                children[0],
                Divider(color: cs.outlineVariant),
                children[1],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: children[0]),
              SizedBox(
                height: 66,
                child: VerticalDivider(color: cs.outlineVariant),
              ),
              Expanded(child: children[1]),
            ],
          );
        },
      ),
    );
  }
}

class _AnalyticsMetricBlock extends StatelessWidget {
  final String label;
  final String value;
  final String secondary;

  const _AnalyticsMetricBlock({
    required this.label,
    required this.value,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            secondary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AnalyticsSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsAdaptiveOverviewTrend extends StatelessWidget {
  final List<_ChartARow> rows;
  final String scopeLabel;

  const _AnalyticsAdaptiveOverviewTrend({
    required this.rows,
    required this.scopeLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.length <= 1) {
      final row = rows.isEmpty ? null : rows.first;
      return _AnalyticsEmptyView(
        icon: Icons.event_rounded,
        title: row == null ? '선택된 날짜가 없습니다.' : row.dateStr,
        description: row == null
            ? '비교할 날짜를 선택해 주세요.'
            : '출차 ${_fmt(row.departure)}대 · 정산 ₩${_fmt(row.fee)}',
      );
    }
    if (rows.length == 2) {
      return _TwoPointComparison(rows: rows);
    }
    return _AChartGrid(
      children: [
        _DateLineChartCard(
          title: '출차 추이',
          subtitle: '선택 날짜 기준 출차 변화',
          rows: rows,
          valueOf: (row) => row.departure.toDouble(),
          valueText: (value) => '${_fmt(value.round())}대',
          icon: Icons.logout_rounded,
          scopeLabel: scopeLabel,
        ),
        _DateLineChartCard(
          title: '정산 추이',
          subtitle: '선택 날짜 기준 정산 변화',
          rows: rows,
          valueOf: (row) => row.fee.toDouble(),
          valueText: (value) => '₩${_fmt(value.round())}',
          icon: Icons.payments_rounded,
          scopeLabel: scopeLabel,
        ),
      ],
    );
  }
}

class _TwoPointComparison extends StatelessWidget {
  final List<_ChartARow> rows;

  const _TwoPointComparison({required this.rows});

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    final second = rows.last;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          _TwoPointRow(
            label: '출차',
            start: '${_fmt(first.departure)}대',
            end: '${_fmt(second.departure)}대',
            delta: _signed(second.departure - first.departure, suffix: '대'),
          ),
          const SizedBox(height: 14),
          _TwoPointRow(
            label: '정산',
            start: '₩${_fmt(first.fee)}',
            end: '₩${_fmt(second.fee)}',
            delta: _signed(second.fee - first.fee, prefix: '₩'),
          ),
        ],
      ),
    );
  }
}

class _TwoPointRow extends StatelessWidget {
  final String label;
  final String start;
  final String end;
  final String delta;

  const _TwoPointRow({
    required this.label,
    required this.start,
    required this.end,
    required this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
        ),
        Expanded(child: Text(start, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        const Icon(Icons.arrow_forward_rounded, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(end, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
        const SizedBox(width: 12),
        Text(delta, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _AnalyticsInsightList extends StatelessWidget {
  final _ChartAReport report;

  const _AnalyticsInsightList({required this.report});

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    final lines = <String>[];
    if (m.maxDeparture != null) {
      lines.add('${m.maxDeparture!.dateStr} · 출차 ${_fmt(m.maxDeparture!.departure)}대로 비교 기간 최고');
    }
    if (m.maxFee != null) {
      lines.add('${m.maxFee!.dateStr} · 정산 ₩${_fmt(m.maxFee!.fee)}로 비교 기간 최고');
    }
    if (report.rows.length >= 2) {
      final last = report.rows.last;
      final previous = report.rows[report.rows.length - 2];
      final feeRate = previous.fee == 0
          ? null
          : (last.fee - previous.fee) / previous.fee * 100;
      if (feeRate != null) {
        lines.add('${last.dateStr} · 정산이 이전 비교일보다 ${feeRate >= 0 ? '+' : ''}${feeRate.toStringAsFixed(1)}% 변화');
      }
    }
    if (lines.isEmpty) {
      lines.add('선택 데이터에서 비교 가능한 주요 변화가 없습니다.');
    }
    return Column(
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.circle, size: 7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ObservationSelector extends StatelessWidget {
  final List<_ChartARow> rows;
  final DateTime? selectedObservation;
  final ValueChanged<DateTime> onSelected;

  const _ObservationSelector({
    required this.rows,
    required this.selectedObservation,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final row in rows)
          ChoiceChip(
            label: Text(row.dateStr.substring(5)),
            selected: selectedObservation != null &&
                selectedObservation!.year == row.date.year &&
                selectedObservation!.month == row.date.month &&
                selectedObservation!.day == row.date.day,
            onSelected: (_) => onSelected(row.date),
          ),
      ],
    );
  }
}

class _AnalyticsTrendView extends StatelessWidget {
  final _ChartAReport report;
  final String scopeLabel;
  final _AnalyticsMetric metric;
  final DateTime? selectedObservation;
  final ValueChanged<_AnalyticsMetric> onMetricChanged;
  final ValueChanged<DateTime> onSelectObservation;

  const _AnalyticsTrendView({
    required this.report,
    required this.scopeLabel,
    required this.metric,
    required this.selectedObservation,
    required this.onMetricChanged,
    required this.onSelectObservation,
  });

  @override
  Widget build(BuildContext context) {
    final row = selectedObservation == null
        ? report.rows.last
        : report.rows.firstWhere(
            (item) =>
                item.date.year == selectedObservation!.year &&
                item.date.month == selectedObservation!.month &&
                item.date.day == selectedObservation!.day,
            orElse: () => report.rows.last,
          );
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsSectionTitle(
            icon: Icons.show_chart_rounded,
            title: '추이',
            subtitle: '같은 날짜 축에서 출차 또는 정산 변화에 집중합니다.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<_AnalyticsMetric>(
            segments: const [
              ButtonSegment(value: _AnalyticsMetric.departure, label: Text('출차'), icon: Icon(Icons.logout_rounded)),
              ButtonSegment(value: _AnalyticsMetric.fee, label: Text('정산'), icon: Icon(Icons.payments_rounded)),
            ],
            selected: <_AnalyticsMetric>{metric},
            onSelectionChanged: (values) => onMetricChanged(values.first),
          ),
          const SizedBox(height: 16),
          if (report.rows.length <= 2)
            _AnalyticsAdaptiveOverviewTrend(
              rows: report.rows,
              scopeLabel: scopeLabel,
            )
          else
            _DateLineChartCard(
              title: metric == _AnalyticsMetric.departure ? '출차 추이' : '정산 추이',
              subtitle: '선택 날짜 전체 흐름',
              rows: report.rows,
              valueOf: metric == _AnalyticsMetric.departure
                  ? (item) => item.departure.toDouble()
                  : (item) => item.fee.toDouble(),
              valueText: metric == _AnalyticsMetric.departure
                  ? (value) => '${_fmt(value.round())}대'
                  : (value) => '₩${_fmt(value.round())}',
              icon: metric == _AnalyticsMetric.departure
                  ? Icons.logout_rounded
                  : Icons.payments_rounded,
              scopeLabel: scopeLabel,
            ),
          const SizedBox(height: 18),
          _ObservationSelector(
            rows: report.rows,
            selectedObservation: selectedObservation,
            onSelected: onSelectObservation,
          ),
          const SizedBox(height: 14),
          _SelectedObservationSummary(row: row, metric: metric),
        ],
      ),
    );
  }
}

class _SelectedObservationSummary extends StatelessWidget {
  final _ChartARow row;
  final _AnalyticsMetric metric;

  const _SelectedObservationSummary({required this.row, required this.metric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = metric == _AnalyticsMetric.departure
        ? '${_fmt(row.departure)}대'
        : '₩${_fmt(row.fee)}';
    final delta = metric == _AnalyticsMetric.departure
        ? _signed(row.departureDelta, suffix: '대')
        : _signed(row.feeDelta, prefix: '₩');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.dateStr, style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('이전 비교일 대비', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(row.no == 1 ? '기준값' : delta, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSectorView extends StatefulWidget {
  final EndWorkSectorMetrics metrics;
  final _AnalyticsScope selectedScope;
  final ValueChanged<_AnalyticsScope> onScopeSelected;

  const _AnalyticsSectorView({
    required this.metrics,
    required this.selectedScope,
    required this.onScopeSelected,
  });

  @override
  State<_AnalyticsSectorView> createState() => _AnalyticsSectorViewState();
}

enum _AnalyticsSectorMetric { vehicles, fee }

class _AnalyticsSectorViewState extends State<_AnalyticsSectorView> {
  _AnalyticsSectorMetric _metric = _AnalyticsSectorMetric.vehicles;

  @override
  Widget build(BuildContext context) {
    final items = widget.metrics.items;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalyticsSectionTitle(
            icon: Icons.grid_view_rounded,
            title: '방문 구역',
            subtitle: '전체 집계와 같은 선택 날짜 조건으로 방문 구역별 차량 수와 정산을 비교합니다.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<_AnalyticsSectorMetric>(
            segments: const [
              ButtonSegment(
                value: _AnalyticsSectorMetric.vehicles,
                label: Text('차량 수'),
              ),
              ButtonSegment(
                value: _AnalyticsSectorMetric.fee,
                label: Text('정산금'),
              ),
            ],
            selected: <_AnalyticsSectorMetric>{_metric},
            onSelectionChanged: (values) {
              HapticFeedback.selectionClick();
              setState(() => _metric = values.first);
              StatisticsChartInteractionLog.log(
                'sector_metric=${values.first.name}',
              );
            },
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const _AnalyticsEmptyView(
              icon: Icons.grid_off_rounded,
              title: '집계된 방문 구역이 없습니다.',
              description: '선택 날짜에 배정된 방문 구역 데이터가 없습니다.',
            )
          else
            _SectorComparisonChart(
              items: items,
              metric: _metric,
            ),
          const SizedBox(height: 18),
          Text(
            '분석 범위 선택',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('전체'),
                selected: widget.selectedScope.isAll,
                onSelected: (_) =>
                    widget.onScopeSelected(const _AnalyticsScope.all()),
              ),
              for (final item in items)
                ChoiceChip(
                  label: Text(
                    item.sectorName.trim().isEmpty
                        ? item.sectorId
                        : item.sectorName,
                  ),
                  selected: widget.selectedScope.key ==
                      _AnalyticsScope.sector(
                        sectorId: item.sectorId.trim(),
                        sectorName: item.sectorName.trim(),
                      ).key,
                  onSelected: (_) => widget.onScopeSelected(
                    _AnalyticsScope.sector(
                      sectorId: item.sectorId.trim(),
                      sectorName: item.sectorName.trim(),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.metrics.unassignedVehicleCount > 0 ||
              widget.metrics.invalidSectorVehicleCount > 0) ...[
            const SizedBox(height: 18),
            _ASectorBreakdownCard(metrics: widget.metrics),
          ],
        ],
      ),
    );
  }
}

class _SectorComparisonChart extends StatelessWidget {
  final List<EndWorkSectorMetricItem> items;
  final _AnalyticsSectorMetric metric;

  const _SectorComparisonChart({
    required this.items,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    final title = metric == _AnalyticsSectorMetric.vehicles
        ? '방문 구역별 차량 수'
        : '방문 구역별 정산금';
    final subtitle = metric == _AnalyticsSectorMetric.vehicles
        ? '같은 비교 날짜 범위에서 방문 구역별 차량 수를 비교합니다.'
        : '같은 비교 날짜 범위에서 방문 구역별 정산금을 비교합니다.';
    return StatisticsExpandableChart(
      title: title,
      subtitle: subtitle,
      debugLabel: 'sector_${metric.name}',
      preview: SizedBox(
        height: 300,
        child: _SectorBarChart(
          items: items,
          metric: metric,
          interactive: false,
          landscape: false,
        ),
      ),
      expandedBuilder: (context, landscape) => _ExpandedSectorBarChart(
        items: items,
        metric: metric,
        landscape: landscape,
      ),
    );
  }
}

class _SectorBarChart extends StatelessWidget {
  final List<EndWorkSectorMetricItem> items;
  final _AnalyticsSectorMetric metric;
  final bool interactive;
  final bool landscape;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  const _SectorBarChart({
    required this.items,
    required this.metric,
    required this.interactive,
    required this.landscape,
    this.selectedIndex,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final values = items
        .map(
          (item) => metric == _AnalyticsSectorMetric.vehicles
              ? item.vehicleCount.toDouble()
              : item.totalLockedFee.toDouble(),
        )
        .toList();
    final maxY = _chartMaxY(values);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = items.length * (landscape ? 104.0 : 86.0) + 72;
        final width = math.max(constraints.maxWidth, minWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: width,
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : landscape
                    ? 430
                    : 310,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: interactive,
                  touchCallback: interactive
                      ? (event, response) {
                          final spot = response?.spot;
                          if (spot == null) return;
                          onSelected?.call(spot.touchedBarGroupIndex);
                        }
                      : null,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: cs.inverseSurface,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final index = group.x.toInt();
                      if (index < 0 || index >= items.length) return null;
                      final item = items[index];
                      final valueText = metric == _AnalyticsSectorMetric.vehicles
                          ? '${item.vehicleCount}대'
                          : '₩${_fmt(item.totalLockedFee.round())}';
                      return BarTooltipItem(
                        '${item.sectorName}\n$valueText',
                        TextStyle(
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: metric == _AnalyticsSectorMetric.fee
                          ? landscape
                              ? 70
                              : 58
                          : 42,
                      getTitlesWidget: (value, meta) => Text(
                        metric == _AnalyticsSectorMetric.fee
                            ? _compactChartValue(value)
                            : value.round().toString(),
                        style: TextStyle(
                          fontSize: landscape ? 10 : 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: landscape ? 54 : 48,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= items.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 7,
                          child: SizedBox(
                            width: landscape ? 96 : 76,
                            child: Text(
                              items[index].sectorName,
                              textAlign: TextAlign.center,
                              maxLines: landscape ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: landscape ? 11 : 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < items.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i],
                          width: landscape ? 28 : 20,
                          color: selectedIndex == null || selectedIndex == i
                              ? cs.primary
                              : cs.primary.withOpacity(.42),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpandedSectorBarChart extends StatefulWidget {
  final List<EndWorkSectorMetricItem> items;
  final _AnalyticsSectorMetric metric;
  final bool landscape;

  const _ExpandedSectorBarChart({
    required this.items,
    required this.metric,
    required this.landscape,
  });

  @override
  State<_ExpandedSectorBarChart> createState() =>
      _ExpandedSectorBarChartState();
}

class _ExpandedSectorBarChartState extends State<_ExpandedSectorBarChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex == null ||
            _selectedIndex! < 0 ||
            _selectedIndex! >= widget.items.length
        ? null
        : widget.items[_selectedIndex!];
    final totalVehicles = widget.items.fold<int>(
      0,
      (sum, item) => sum + item.vehicleCount,
    );
    final totalFee = widget.items.fold<num>(
      0,
      (sum, item) => sum + item.totalLockedFee,
    );
    return Column(
      children: [
        Expanded(
          child: _SectorBarChart(
            items: widget.items,
            metric: widget.metric,
            interactive: true,
            landscape: widget.landscape,
            selectedIndex: _selectedIndex,
            onSelected: (index) {
              if (index < 0 || index >= widget.items.length) return;
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = index);
              StatisticsChartInteractionLog.log(
                'select chart=sector_${widget.metric.name} index=$index sector=${widget.items[index].sectorName}',
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        StatisticsChartSelectionPanel(
          title: selected == null
              ? '막대를 눌러 방문 구역 상세값을 확인하세요.'
              : selected.sectorName,
          values: selected == null
              ? const <String>[]
              : <String>[
                  '${selected.vehicleCount}대',
                  '₩${_fmt(selected.totalLockedFee.round())}',
                  totalVehicles == 0
                      ? '차량 비중 0.0%'
                      : '차량 비중 ${(selected.vehicleCount / totalVehicles * 100).toStringAsFixed(1)}%',
                  totalFee == 0
                      ? '정산 비중 0.0%'
                      : '정산 비중 ${(selected.totalLockedFee / totalFee * 100).toStringAsFixed(1)}%',
                ],
          icon: Icons.grid_view_rounded,
        ),
      ],
    );
  }
}

class _AnalyticsDetailView extends StatelessWidget {
  final List<_ChartARow> rows;
  final DateTime? selectedObservation;
  final ValueChanged<DateTime> onSelectObservation;

  const _AnalyticsDetailView({
    required this.rows,
    required this.selectedObservation,
    required this.onSelectObservation,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalyticsSectionTitle(
            icon: Icons.table_chart_rounded,
            title: '날짜별 상세',
            subtitle: '출차·정산·이전 비교일 대비 변화·기간 비중을 한 번만 표시합니다.',
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
              columns: const [
                DataColumn(label: Text('날짜')),
                DataColumn(label: Text('출차')),
                DataColumn(label: Text('정산')),
                DataColumn(label: Text('출차 변화')),
                DataColumn(label: Text('정산 변화')),
                DataColumn(label: Text('출차 비중')),
                DataColumn(label: Text('정산 비중')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    selected: selectedObservation != null &&
                        selectedObservation!.year == row.date.year &&
                        selectedObservation!.month == row.date.month &&
                        selectedObservation!.day == row.date.day,
                    onSelectChanged: (_) => onSelectObservation(row.date),
                    cells: [
                      DataCell(Text(row.dateStr)),
                      DataCell(Text('${_fmt(row.departure)}대')),
                      DataCell(Text('₩${_fmt(row.fee)}')),
                      DataCell(Text(row.no == 1 ? '-' : _signed(row.departureDelta, suffix: '대'))),
                      DataCell(Text(row.no == 1 ? '-' : _signed(row.feeDelta, prefix: '₩'))),
                      DataCell(Text('${(row.departureShare * 100).toStringAsFixed(1)}%')),
                      DataCell(Text('${(row.feeShare * 100).toStringAsFixed(1)}%')),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RawAnalysisGate extends StatelessWidget {
  final String title;
  final bool loading;
  final int progressCurrent;
  final int progressTotal;
  final DateTime? selectedDate;
  final bool selectedAvailable;
  final bool allAvailable;
  final int availableDateCount;
  final int totalDateCount;
  final VoidCallback? onSelected;
  final VoidCallback? onAll;

  const _RawAnalysisGate({
    required this.title,
    required this.loading,
    required this.progressCurrent,
    required this.progressTotal,
    required this.selectedDate,
    required this.selectedAvailable,
    required this.allAvailable,
    required this.availableDateCount,
    required this.totalDateCount,
    required this.onSelected,
    required this.onAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final coverageComplete =
        totalDateCount > 0 && availableDateCount == totalDateCount;
    final selectedDateValue = selectedDate;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_download_outlined, size: 36, color: cs.primary),
              const SizedBox(height: 14),
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                '이 분석은 검증된 원본 차량 로그를 사용합니다. 범위를 선택한 뒤 명시적으로 분석을 시작할 때만 GCS 원본을 불러옵니다.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: transitionDuration,
                curve: CommonUiMotion.standard,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: coverageComplete
                      ? cs.primaryContainer
                      : cs.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '원본 사용 가능 $availableDateCount / $totalDateCount일',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: coverageComplete
                        ? cs.onPrimaryContainer
                        : cs.onErrorContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!coverageComplete) ...[
                const SizedBox(height: 8),
                Text(
                  '비교 날짜 전체 분석은 모든 비교 날짜에 원본 로그가 있을 때 사용할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: transitionDuration,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: loading
                    ? Column(
                        key: const ValueKey<String>('raw-loading'),
                        children: [
                          CircularProgressIndicator(
                            value: progressTotal > 0
                                ? progressCurrent / progressTotal
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            progressTotal > 0
                                ? '원본 로그 분석 중 · $progressCurrent / $progressTotal'
                                : '원본 로그 분석 준비 중',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey<String>('raw-actions'),
                        children: [
                          if (selectedDateValue != null)
                            FilledButton.tonalIcon(
                              onPressed: selectedAvailable ? onSelected : null,
                              icon: const Icon(Icons.event_rounded),
                              label: Text('${_dateOnly(selectedDateValue)} 분석'),
                            ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: allAvailable ? onAll : null,
                            icon: const Icon(Icons.dataset_rounded),
                            label: const Text('비교 날짜 전체 분석'),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsHourlyView extends StatelessWidget {
  final StatisticsDeepReport report;
  final DateTime? selectedObservation;
  final _AnalyticsHourlyMetric metric;
  final ValueChanged<_AnalyticsHourlyMetric> onMetricChanged;

  const _AnalyticsHourlyView({
    required this.report,
    required this.selectedObservation,
    required this.metric,
    required this.onMetricChanged,
  });

  @override
  Widget build(BuildContext context) {
    final section = _deepSectionForObservation(report, selectedObservation);
    final values = metric == _AnalyticsHourlyMetric.input
        ? section.metrics.inputTotalCounts
        : section.metrics.outputTotalCounts;
    final peak = _peakIndex(values);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsSectionTitle(
            icon: Icons.schedule_rounded,
            title: '시간대',
            subtitle: '${section.subtitle} · 원본 차량 ${section.rows.length}대 기준',
          ),
          const SizedBox(height: 12),
          SegmentedButton<_AnalyticsHourlyMetric>(
            segments: const [
              ButtonSegment(value: _AnalyticsHourlyMetric.input, label: Text('입차'), icon: Icon(Icons.login_rounded)),
              ButtonSegment(value: _AnalyticsHourlyMetric.output, label: Text('출차'), icon: Icon(Icons.logout_rounded)),
            ],
            selected: <_AnalyticsHourlyMetric>{metric},
            onSelectionChanged: (values) => onMetricChanged(values.first),
          ),
          const SizedBox(height: 16),
          _HourlyBarChart(
            values: values,
            title: metric == _AnalyticsHourlyMetric.input ? '입차 시간대' : '출차 시간대',
          ),
          const SizedBox(height: 14),
          Text(
            peak == null ? '확인 가능한 시간대 데이터가 없습니다.' : '피크 ${peak.toString().padLeft(2, '0')}:00 · ${values[peak]}대',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _HourlyBarChart extends StatelessWidget {
  final List<int> values;
  final String title;

  const _HourlyBarChart({required this.values, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 10),
        StatisticsExpandableChart(
          title: title,
          subtitle: '시간대별 차량 분포',
          debugLabel: 'hourly_$title',
          preview: SizedBox(
            height: 310,
            child: _HourlyBarChartBody(
              values: values,
              interactive: false,
              landscape: false,
            ),
          ),
          expandedBuilder: (context, landscape) => _ExpandedHourlyBarChart(
            values: values,
            title: title,
            landscape: landscape,
          ),
        ),
      ],
    );
  }
}

class _HourlyBarChartBody extends StatelessWidget {
  final List<int> values;
  final bool interactive;
  final bool landscape;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  const _HourlyBarChartBody({
    required this.values,
    required this.interactive,
    required this.landscape,
    this.selectedIndex,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxValue = values.fold<int>(
      0,
      (current, value) => math.max(current, value).toInt(),
    );
    final maxY = math.max(maxValue * 1.2, 1).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          values.length * (landscape ? 36.0 : 28.0) + 54,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: width,
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : landscape
                    ? 430
                    : 310,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: true, drawVerticalLine: false),
                barTouchData: BarTouchData(
                  enabled: interactive,
                  touchCallback: interactive
                      ? (event, response) {
                          final spot = response?.spot;
                          if (spot == null) return;
                          onSelected?.call(spot.touchedBarGroupIndex);
                        }
                      : null,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: cs.inverseSurface,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final hour = group.x.toInt();
                      if (hour < 0 || hour >= values.length) return null;
                      return BarTooltipItem(
                        '${hour.toString().padLeft(2, '0')}:00\n${values[hour]}대',
                        TextStyle(
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: landscape ? 42 : 34,
                      getTitlesWidget: (value, meta) => Text(
                        value.round().toString(),
                        style: TextStyle(
                          fontSize: landscape ? 10 : 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: landscape ? 32 : 28,
                      interval: landscape ? 2 : 3,
                      getTitlesWidget: (value, meta) {
                        final hour = value.round();
                        final step = landscape ? 2 : 3;
                        if (hour < 0 || hour > 23 || hour % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            '$hour시',
                            style: TextStyle(
                              fontSize: landscape ? 10 : 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < values.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i].toDouble(),
                          width: landscape ? 14 : 10,
                          color: selectedIndex == null || selectedIndex == i
                              ? cs.primary
                              : cs.primary.withOpacity(.38),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpandedHourlyBarChart extends StatefulWidget {
  final List<int> values;
  final String title;
  final bool landscape;

  const _ExpandedHourlyBarChart({
    required this.values,
    required this.title,
    required this.landscape,
  });

  @override
  State<_ExpandedHourlyBarChart> createState() =>
      _ExpandedHourlyBarChartState();
}

class _ExpandedHourlyBarChartState extends State<_ExpandedHourlyBarChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final index = _selectedIndex;
    return Column(
      children: [
        Expanded(
          child: _HourlyBarChartBody(
            values: widget.values,
            interactive: true,
            landscape: widget.landscape,
            selectedIndex: index,
            onSelected: (next) {
              if (next < 0 || next >= widget.values.length) return;
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = next);
              StatisticsChartInteractionLog.log(
                'select chart=${widget.title} hour=$next value=${widget.values[next]}',
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        StatisticsChartSelectionPanel(
          title: index == null
              ? '막대를 눌러 시간대별 상세값을 확인하세요.'
              : '${index.toString().padLeft(2, '0')}:00 ~ ${index.toString().padLeft(2, '0')}:59',
          values: index == null
              ? const <String>[]
              : <String>['${widget.values[index]}대'],
          icon: Icons.schedule_rounded,
        ),
      ],
    );
  }
}

class _AnalyticsPaymentView extends StatelessWidget {
  final StatisticsDeepReport report;
  final DateTime? selectedObservation;
  final _AnalyticsPaymentMetric metric;
  final ValueChanged<_AnalyticsPaymentMetric> onMetricChanged;

  const _AnalyticsPaymentView({
    required this.report,
    required this.selectedObservation,
    required this.metric,
    required this.onMetricChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedObservationValue = selectedObservation;
    final rows = _deepRowsForObservation(report, selectedObservationValue);
    final vehicleCounts = <String, int>{};
    final fees = <String, int>{};
    for (final row in rows) {
      final label = row.paymentMethodLabel;
      vehicleCounts[label] = (vehicleCounts[label] ?? 0) + 1;
      fees[label] = (fees[label] ?? 0) + (row.fee ?? 0);
    }
    final source =
        metric == _AnalyticsPaymentMetric.vehicles ? vehicleCounts : fees;
    final entries = source.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final scopeText = selectedObservationValue == null
        ? report.scopeLabel
        : _dateOnly(selectedObservationValue);
    final title = metric == _AnalyticsPaymentMetric.vehicles
        ? '결제수단별 차량 수'
        : '결제수단별 정산금';
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AnalyticsSectionTitle(
            icon: Icons.payments_rounded,
            title: '결제',
            subtitle: '$scopeText · 원본 차량 ${rows.length}대 기준',
          ),
          const SizedBox(height: 12),
          SegmentedButton<_AnalyticsPaymentMetric>(
            segments: const [
              ButtonSegment(
                value: _AnalyticsPaymentMetric.vehicles,
                label: Text('차량 수'),
              ),
              ButtonSegment(
                value: _AnalyticsPaymentMetric.fee,
                label: Text('정산금'),
              ),
            ],
            selected: <_AnalyticsPaymentMetric>{metric},
            onSelectionChanged: (values) => onMetricChanged(values.first),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const _AnalyticsEmptyView(
              icon: Icons.money_off_rounded,
              title: '결제 데이터가 없습니다.',
              description: '선택 범위의 원본 로그에서 결제 정보를 확인할 수 없습니다.',
            )
          else
            StatisticsExpandableChart(
              title: title,
              subtitle: scopeText,
              debugLabel: 'payment_${metric.name}',
              preview: _PaymentBarsList(
                entries: entries,
                total: total,
                metric: metric,
              ),
              expandedBuilder: (context, landscape) => _ExpandedPaymentBars(
                entries: entries,
                total: total,
                metric: metric,
                landscape: landscape,
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentBarsList extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  final _AnalyticsPaymentMetric metric;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;
  final bool expanded;

  const _PaymentBarsList({
    required this.entries,
    required this.total,
    required this.metric,
    this.selectedIndex,
    this.onSelected,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      children.add(
        _HorizontalMetricBar(
          label: entry.key,
          value: entry.value,
          total: total,
          valueText: metric == _AnalyticsPaymentMetric.vehicles
              ? '${entry.value}대'
              : '₩${_fmt(entry.value)}',
          selected: selectedIndex == i,
          onTap: onSelected == null ? null : () => onSelected!(i),
        ),
      );
      if (i != entries.length - 1) {
        children.add(const SizedBox(height: 10));
      }
    }
    if (!expanded) {
      return Column(children: children);
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      children: children,
    );
  }
}

class _ExpandedPaymentBars extends StatefulWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  final _AnalyticsPaymentMetric metric;
  final bool landscape;

  const _ExpandedPaymentBars({
    required this.entries,
    required this.total,
    required this.metric,
    required this.landscape,
  });

  @override
  State<_ExpandedPaymentBars> createState() => _ExpandedPaymentBarsState();
}

class _ExpandedPaymentBarsState extends State<_ExpandedPaymentBars> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final index = _selectedIndex;
    final selected = index == null || index < 0 || index >= widget.entries.length
        ? null
        : widget.entries[index];
    final ratio = selected == null || widget.total <= 0
        ? 0.0
        : selected.value / widget.total;
    final bars = _PaymentBarsList(
      entries: widget.entries,
      total: widget.total,
      metric: widget.metric,
      selectedIndex: index,
      expanded: true,
      onSelected: (next) {
        HapticFeedback.selectionClick();
        setState(() => _selectedIndex = next);
        StatisticsChartInteractionLog.log(
          'select chart=payment_${widget.metric.name} index=$next label=${widget.entries[next].key} value=${widget.entries[next].value}',
        );
      },
    );
    final detail = StatisticsChartSelectionPanel(
      title: selected == null
          ? '막대 영역을 눌러 결제 상세값을 확인하세요.'
          : selected.key,
      values: selected == null
          ? const <String>[]
          : <String>[
              widget.metric == _AnalyticsPaymentMetric.vehicles
                  ? '${selected.value}대'
                  : '₩${_fmt(selected.value)}',
              '전체 대비 ${(ratio * 100).toStringAsFixed(1)}%',
            ],
      icon: Icons.payments_rounded,
    );
    if (widget.landscape) {
      return Row(
        children: [
          Expanded(flex: 3, child: bars),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Align(alignment: Alignment.topCenter, child: detail)),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: bars),
        const SizedBox(height: 10),
        detail,
      ],
    );
  }
}

class _HorizontalMetricBar extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final String valueText;
  final bool selected;
  final VoidCallback? onTap;

  const _HorizontalMetricBar({
    required this.label,
    required this.value,
    required this.total,
    required this.valueText,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = total <= 0 ? 0.0 : value / total;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      padding: EdgeInsets.all(selected ? 10 : 0),
      decoration: BoxDecoration(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected ? cs.onSecondaryContainer : cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                valueText,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? cs.onSecondaryContainer : cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: selected ? 11 : 8,
              backgroundColor: selected
                  ? cs.surface.withOpacity(.72)
                  : cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _AnalyticsWeekdayView extends StatelessWidget {
  final StatisticsDeepReport report;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _AnalyticsWeekdayView({
    required this.report,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final sections = report.weekdaySections;
    if (sections.isEmpty) {
      return const _AnalyticsEmptyView(
        icon: Icons.calendar_view_week_rounded,
        title: '요일 비교 표본이 부족합니다.',
        description: '같은 요일이 2일 이상 포함되어야 요일별 분석을 제공합니다.',
      );
    }
    final section = sections.firstWhere(
      (item) => item.id == selectedId,
      orElse: () => sections.first,
    );
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnalyticsSectionTitle(
            icon: Icons.calendar_view_week_rounded,
            title: '요일',
            subtitle: '동일 요일이 2일 이상 포함된 경우에만 표본을 묶어 비교합니다.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in sections)
                ChoiceChip(
                  label: Text(item.title.replaceAll(' 심화 통계', '')),
                  selected: item.id == section.id,
                  onSelected: (_) => onSelect(item.id),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _AnalyticsMetricBand(
            metrics: _ChartAMetrics(
              dayCount: section.sourceDateCount,
              totalDeparture: section.metrics.outputTotalSum,
              totalFee: section.totalFee,
              averageDeparture: section.metrics.outputTotalSum / section.sourceDateCount,
              averageFee: section.totalFee / section.sourceDateCount,
              maxDeparture: null,
              minDeparture: null,
              maxFee: null,
              minFee: null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${section.title} · 표본 ${section.sourceDateCount}일',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _HourlyBarChart(
            values: section.metrics.outputAverageCounts.map((value) => value.round()).toList(),
            title: '평균 출차 시간대',
          ),
        ],
      ),
    );
  }
}

StatisticsDeepSection _deepSectionForObservation(
  StatisticsDeepReport report,
  DateTime? observation,
) {
  if (observation == null) return report.overallSection;
  final key = _dateOnly(observation);
  return report.dailySections.firstWhere(
    (section) => section.dateStrs.contains(key),
    orElse: () => report.overallSection,
  );
}

List<StatisticsDeepVehicleRow> _deepRowsForObservation(
  StatisticsDeepReport report,
  DateTime? observation,
) {
  if (observation == null) return report.rows;
  final key = _dateOnly(observation);
  return report.rows.where((row) => row.dateStr == key).toList();
}

int? _peakIndex(List<int> values) {
  if (values.isEmpty) return null;
  var maxValue = 0;
  int? index;
  for (var i = 0; i < values.length; i++) {
    if (values[i] > maxValue) {
      maxValue = values[i];
      index = i;
    }
  }
  return index;
}

class _AnalyticsEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _AnalyticsEmptyView({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(description, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ASectorBreakdownCard extends StatelessWidget {
  final EndWorkSectorMetrics metrics;

  const _ASectorBreakdownCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withOpacity(.78)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '집계 예외',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '정상 방문 구역과 분리해 데이터 품질 상태를 표시합니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (metrics.unassignedVehicleCount > 0)
              _ASectorBreakdownRow(
                label: '미지정',
                vehicleCount: metrics.unassignedVehicleCount,
                lockedFee: metrics.unassignedLockedFee,
              ),
            if (metrics.unassignedVehicleCount > 0 &&
                metrics.invalidSectorVehicleCount > 0)
              const SizedBox(height: 8),
            if (metrics.invalidSectorVehicleCount > 0)
              _ASectorBreakdownRow(
                label: '확인 필요',
                vehicleCount: metrics.invalidSectorVehicleCount,
                lockedFee: metrics.invalidSectorLockedFee,
              ),
          ],
        ),
      ),
    );
  }
}

class _ASectorBreakdownRow extends StatelessWidget {
  final String label;
  final int vehicleCount;
  final num lockedFee;

  const _ASectorBreakdownRow({
    required this.label,
    required this.vehicleCount,
    required this.lockedFee,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(.62)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$vehicleCount대 · ₩${_fmt(lockedFee.round())}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AChartGrid extends StatelessWidget {
  final List<Widget> children;

  const _AChartGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _DateLineChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String scopeLabel;
  final List<_ChartARow> rows;
  final double Function(_ChartARow row) valueOf;
  final String Function(double value) valueText;
  final IconData icon;

  const _DateLineChartCard({
    required this.title,
    required this.subtitle,
    required this.scopeLabel,
    required this.rows,
    required this.valueOf,
    required this.valueText,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final values = rows.map(valueOf).toList();
    final hasData = values.any((v) => v > 0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$scopeLabel · $subtitle',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasData)
            SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  '표시할 데이터가 없습니다.',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            StatisticsExpandableChart(
              title: '$scopeLabel · $title',
              subtitle: subtitle,
              debugLabel: 'date_line_${scopeLabel}_$title',
              preview: SizedBox(
                height: 260,
                child: _DateLineChart(
                  rows: rows,
                  valueOf: valueOf,
                  valueText: valueText,
                  interactive: false,
                  landscape: false,
                ),
              ),
              expandedBuilder: (context, landscape) => _ExpandedDateLineChart(
                rows: rows,
                valueOf: valueOf,
                valueText: valueText,
                title: title,
                landscape: landscape,
              ),
            ),
        ],
      ),
    );
  }
}

class _DateLineChart extends StatelessWidget {
  final List<_ChartARow> rows;
  final double Function(_ChartARow row) valueOf;
  final String Function(double value) valueText;
  final bool interactive;
  final bool landscape;
  final ValueChanged<int>? onSelected;

  const _DateLineChart({
    required this.rows,
    required this.valueOf,
    required this.valueText,
    required this.interactive,
    required this.landscape,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final values = rows.map(valueOf).toList();
    final maxY = _chartMaxY(values);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pointWidth = landscape ? 74.0 : 58.0;
        final width = math.max(
          constraints.maxWidth,
          rows.length * pointWidth + 32,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: width,
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : landscape
                    ? 430
                    : 300,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(rows.length - 1, 0).toDouble(),
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: landscape ? 66 : 48,
                      getTitlesWidget: (value, meta) => Text(
                        valueText(value),
                        style: TextStyle(
                          fontSize: landscape ? 10 : 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: landscape ? 34 : 30,
                      interval: landscape
                          ? math.max(1, _axisLabelStep(rows.length) ~/ 2)
                              .toDouble()
                          : _axisLabelStep(rows.length).toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            rows[index].dateStr.substring(5),
                            style: TextStyle(
                              fontSize: landscape ? 11 : 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: interactive,
                  touchCallback: interactive
                      ? (event, response) {
                          final spots = response?.lineBarSpots;
                          if (spots == null || spots.isEmpty) return;
                          final index = spots.first.x.round();
                          if (index < 0 || index >= rows.length) return;
                          onSelected?.call(index);
                        }
                      : null,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: cs.inverseSurface,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final index = spot.x.round().clamp(0, rows.length - 1).toInt();
                        return LineTooltipItem(
                          '${rows[index].dateStr}\n${valueText(spot.y)}',
                          TextStyle(
                            color: cs.onInverseSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      rows.length,
                      (i) => FlSpot(i.toDouble(), valueOf(rows[i])),
                    ),
                    isCurved: true,
                    color: cs.primary,
                    barWidth: landscape ? 3.6 : 3.2,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: cs.primary.withOpacity(0.10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpandedDateLineChart extends StatefulWidget {
  final List<_ChartARow> rows;
  final double Function(_ChartARow row) valueOf;
  final String Function(double value) valueText;
  final String title;
  final bool landscape;

  const _ExpandedDateLineChart({
    required this.rows,
    required this.valueOf,
    required this.valueText,
    required this.title,
    required this.landscape,
  });

  @override
  State<_ExpandedDateLineChart> createState() =>
      _ExpandedDateLineChartState();
}

class _ExpandedDateLineChartState extends State<_ExpandedDateLineChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final row = _selectedIndex == null ||
            _selectedIndex! < 0 ||
            _selectedIndex! >= widget.rows.length
        ? null
        : widget.rows[_selectedIndex!];
    final value = row == null ? null : widget.valueOf(row);
    return Column(
      children: [
        Expanded(
          child: _DateLineChart(
            rows: widget.rows,
            valueOf: widget.valueOf,
            valueText: widget.valueText,
            interactive: true,
            landscape: widget.landscape,
            onSelected: (index) {
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = index);
              StatisticsChartInteractionLog.log(
                'select chart=${widget.title} index=$index date=${widget.rows[index].dateStr} value=${widget.valueText(widget.valueOf(widget.rows[index]))}',
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        StatisticsChartSelectionPanel(
          title: row == null
              ? '그래프의 점을 눌러 날짜별 상세값을 확인하세요.'
              : row.dateStr,
          values: row == null || value == null
              ? const <String>[]
              : <String>[
                  widget.valueText(value),
                  row.no == 1
                      ? '첫 비교값'
                      : widget.title.contains('정산')
                          ? '이전 비교일 ${_signed(row.feeDelta, prefix: '₩')}'
                          : '이전 비교일 ${_signed(row.departureDelta, suffix: '대')}',
                ],
          icon: Icons.show_chart_rounded,
        ),
      ],
    );
  }
}

class _AEmptyState extends StatelessWidget {
  const _AEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: StatisticsReportDesign.screenPanel(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_chart_outlined_rounded, size: 56, color: cs.primary),
            const SizedBox(height: 14),
            Text('출차·정산 비교에 표시할 데이터가 없습니다.', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('업무 통계 확인 시트에서 날짜 데이터를 선택한 뒤 다시 열어 주세요.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SectorCrossIntegrity {
  final bool expectedMetricsValid;
  final bool sectorIdentityValid;
  final bool assignedVehicleCountMatched;
  final bool unassignedVehicleCountMatched;
  final bool invalidVehicleCountMatched;
  final bool totalLockedFeeMatched;
  final bool assignedGroupsMatched;
  final List<String> debugLines;

  const _SectorCrossIntegrity({
    required this.expectedMetricsValid,
    required this.sectorIdentityValid,
    required this.assignedVehicleCountMatched,
    required this.unassignedVehicleCountMatched,
    required this.invalidVehicleCountMatched,
    required this.totalLockedFeeMatched,
    required this.assignedGroupsMatched,
    required this.debugLines,
  });

  bool get isValid =>
      expectedMetricsValid &&
      sectorIdentityValid &&
      assignedVehicleCountMatched &&
      unassignedVehicleCountMatched &&
      invalidVehicleCountMatched &&
      totalLockedFeeMatched &&
      assignedGroupsMatched;

  factory _SectorCrossIntegrity.compare({
    required EndWorkSectorMetrics expected,
    required StatisticsSectorReport actual,
  }) {
    final expectedVehicleById = <String, int>{};
    final expectedFeeById = <String, int>{};
    final expectedNamesById = <String, Set<String>>{};
    for (final item in expected.items) {
      final id = item.sectorId.trim();
      if (id.isEmpty) continue;
      expectedVehicleById[id] =
          (expectedVehicleById[id] ?? 0) + item.vehicleCount;
      expectedFeeById[id] =
          (expectedFeeById[id] ?? 0) + item.totalLockedFee.round();
      expectedNamesById
          .putIfAbsent(id, () => <String>{})
          .add(item.sectorName.trim());
    }

    final actualVehicleById = <String, int>{};
    final actualFeeById = <String, int>{};
    for (final group in actual.groups) {
      if (group.state != StatisticsSectorState.assigned ||
          group.sectorId == null) {
        continue;
      }
      final id = group.sectorId!.trim();
      actualVehicleById[id] =
          (actualVehicleById[id] ?? 0) + group.vehicleCount;
      actualFeeById[id] =
          (actualFeeById[id] ?? 0) + group.totalLockedFee;
    }

    final expectedIdentityConflicts = expectedNamesById.entries
        .where((entry) => entry.value.where((name) => name.isNotEmpty).length > 1)
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final sectorIdentityValid =
        expectedIdentityConflicts.isEmpty &&
        actual.integrity.sectorIdentityConflictCount == 0;

    final allIds = <String>{
      ...expectedVehicleById.keys,
      ...actualVehicleById.keys,
    }.toList()
      ..sort();
    final groupLines = <String>[];
    var groupsMatched = true;
    for (final id in allIds) {
      final expectedVehicles = expectedVehicleById[id] ?? 0;
      final actualVehicles = actualVehicleById[id] ?? 0;
      final expectedFee = expectedFeeById[id] ?? 0;
      final actualFee = actualFeeById[id] ?? 0;
      final vehicleMatched = expectedVehicles == actualVehicles;
      final feeMatched = expectedFee == actualFee;
      if (!vehicleMatched || !feeMatched) groupsMatched = false;
      groupLines.add(
        'cross sectorId=$id vehicles=$actualVehicles/$expectedVehicles '
        'fee=$actualFee/$expectedFee matched=${vehicleMatched && feeMatched}',
      );
    }

    final assignedMatched =
        actual.assignedVehicleCount == expected.assignedVehicleCount;
    final unassignedMatched =
        actual.unassignedVehicleCount == expected.unassignedVehicleCount;
    final invalidMatched =
        actual.invalidVehicleCount == expected.invalidSectorVehicleCount;
    final feeMatched =
        actual.totalLockedFee == expected.totalLockedFee.round();
    final expectedMetricsValid = expected.isInternallyConsistent;

    return _SectorCrossIntegrity(
      expectedMetricsValid: expectedMetricsValid,
      sectorIdentityValid: sectorIdentityValid,
      assignedVehicleCountMatched: assignedMatched,
      unassignedVehicleCountMatched: unassignedMatched,
      invalidVehicleCountMatched: invalidMatched,
      totalLockedFeeMatched: feeMatched,
      assignedGroupsMatched: groupsMatched,
      debugLines: <String>[
        'cross expectedInternal=$expectedMetricsValid',
        'cross identityValid=$sectorIdentityValid '
            'expectedConflicts=${expectedIdentityConflicts.join(',')} '
            'actualConflicts=${actual.integrity.sectorIdentityConflictCount}',
        'cross assigned=${actual.assignedVehicleCount}/${expected.assignedVehicleCount} matched=$assignedMatched',
        'cross unassigned=${actual.unassignedVehicleCount}/${expected.unassignedVehicleCount} matched=$unassignedMatched',
        'cross invalid=${actual.invalidVehicleCount}/${expected.invalidSectorVehicleCount} matched=$invalidMatched',
        'cross fee=${actual.totalLockedFee}/${expected.totalLockedFee.round()} matched=$feeMatched',
        ...groupLines,
      ],
    );
  }
}


List<_AnalyticsScope> _analyticsScopeOptions(_ChartAReport report) {
  final metrics = report.sectorMetrics;
  final scopes = <_AnalyticsScope>[const _AnalyticsScope.all()];
  if (metrics == null) return scopes;
  for (final item in metrics.items) {
    final id = item.sectorId.trim();
    final name = item.sectorName.trim();
    if (id.isEmpty && name.isEmpty) continue;
    scopes.add(
      _AnalyticsScope.sector(
        sectorId: id,
        sectorName: name,
      ),
    );
  }
  return scopes;
}

_AnalyticsScope _resolveAnalyticsScope(
  List<_AnalyticsScope> scopes,
  _AnalyticsScope selected,
) {
  for (final scope in scopes) {
    if (scope.key == selected.key) return scope;
  }
  return const _AnalyticsScope.all();
}

EndWorkSectorMetricItem? _sectorItemForScope(
  EndWorkSectorMetrics? metrics,
  _AnalyticsScope scope,
) {
  if (metrics == null || scope.isAll) return null;
  for (final item in metrics.items) {
    final id = item.sectorId.trim();
    final name = item.sectorName.trim();
    if (scope.sectorId.isNotEmpty && id == scope.sectorId) {
      if (scope.sectorName.isEmpty || name == scope.sectorName) return item;
    }
    if (scope.sectorId.isEmpty &&
        scope.sectorName.isNotEmpty &&
        name == scope.sectorName) {
      return item;
    }
  }
  return null;
}

_ChartAReport _scopeChartReport(
  _ChartAReport source,
  _AnalyticsScope scope,
) {
  if (scope.isAll) return source;
  final rawRows = <_ChartARow>[];
  for (final row in source.rows) {
    final item = _sectorItemForScope(row.sectorMetrics, scope);
    rawRows.add(
      _ChartARow(
        no: row.no,
        date: row.date,
        departure: item?.vehicleCount ?? 0,
        fee: item?.totalLockedFee.round() ?? 0,
        departureDelta: 0,
        feeDelta: 0,
        departureShare: 0,
        feeShare: 0,
        historyEntryCount: row.historyEntryCount,
        historyDetailedEntryCount: row.historyDetailedEntryCount,
        historyExcludedEntryCount: row.historyExcludedEntryCount,
        historyFirstEntryCount: row.historyFirstEntryCount,
        historyUnverifiedDetailedEntryCount:
            row.historyUnverifiedDetailedEntryCount,
        historyLegacyDetailedEntryCount: row.historyLegacyDetailedEntryCount,
        historyAggregationMode: row.historyAggregationMode,
        historyLogsUrls: row.historyLogsUrls,
        historyAggregated: row.historyAggregated,
        historySectorEntryCount: row.historySectorEntryCount,
        sectorMetrics: row.sectorMetrics,
      ),
    );
  }
  final totalDeparture =
      rawRows.fold<int>(0, (sum, row) => sum + row.departure);
  final totalFee = rawRows.fold<int>(0, (sum, row) => sum + row.fee);
  final rows = <_ChartARow>[];
  for (var i = 0; i < rawRows.length; i++) {
    final current = rawRows[i];
    final previous = i == 0 ? null : rawRows[i - 1];
    rows.add(
      current.copyWith(
        no: i + 1,
        departureDelta:
            previous == null ? 0 : current.departure - previous.departure,
        feeDelta: previous == null ? 0 : current.fee - previous.fee,
        departureShare:
            totalDeparture == 0 ? 0 : current.departure / totalDeparture,
        feeShare: totalFee == 0 ? 0 : current.fee / totalFee,
      ),
    );
  }
  return _ChartAReport(
    rows: rows,
    rangeLabel: source.rangeLabel,
    metrics: _ChartAMetrics.fromRows(rows),
    sectorMetrics: source.sectorMetrics,
    sections: source.sections,
    tocItems: source.tocItems,
  );
}

StatisticsDeepReport _scopeDeepReport(
  StatisticsDeepReport source,
  _AnalyticsScope scope,
) {
  if (scope.isAll) return source;
  final rows = source.rows.where((row) {
    if (row.sectorState != StatisticsSectorState.assigned) return false;
    final id = row.normalizedSectorId;
    final name = row.normalizedSectorName;
    if (scope.sectorId.isNotEmpty && id == scope.sectorId) {
      return scope.sectorName.isEmpty || name == scope.sectorName;
    }
    return scope.sectorId.isEmpty &&
        scope.sectorName.isNotEmpty &&
        name == scope.sectorName;
  }).toList();
  return StatisticsDeepReport.fromRows(
    division: source.division,
    area: source.area,
    scopeLabel: '${source.scopeLabel} · ${scope.label}',
    rows: rows,
    objectNames: source.objectNames,
    dateStrs: source.dateStrs,
    sectorEnabled: source.sectorEnabled,
    diagnostics: source.diagnostics,
  );
}

class _ChartAReport {
  final List<_ChartARow> rows;
  final String rangeLabel;
  final _ChartAMetrics metrics;
  final EndWorkSectorMetrics? sectorMetrics;
  final List<_ChartASection> sections;
  final List<_ChartATocItem> tocItems;

  const _ChartAReport({
    required this.rows,
    required this.rangeLabel,
    required this.metrics,
    required this.sectorMetrics,
    required this.sections,
    required this.tocItems,
  });

  factory _ChartAReport.from(
    Map<DateTime, Map<String, dynamic>> reportDataMap, {
    required bool sectorEnabled,
  }) {
    final sortedDates = reportDataMap.keys.toList()..sort();
    final rawRows = <_ChartARow>[];
    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final counts = reportDataMap[date] ?? const <String, dynamic>{};
      final departure = _chartInt(
        counts['vehicleOutput'] ??
            counts['출차'] ??
            counts['vehicleInput'] ??
            counts['입차'],
      );
      final fee = _chartInt(
        counts['totalLockedFee'] ?? counts['정산금'],
      );
      final sectorMetrics = sectorEnabled
          ? EndWorkSectorMetrics.fromDynamic(counts['sector'])
          : null;
      rawRows.add(
        _ChartARow(
          no: i + 1,
          date: DateTime(date.year, date.month, date.day),
          departure: departure,
          fee: fee,
          departureDelta: 0,
          feeDelta: 0,
          departureShare: 0,
          feeShare: 0,
          historyEntryCount: _chartInt(counts['historyEntryCount']).clamp(1, 1 << 30).toInt(),
          historyDetailedEntryCount: _chartInt(counts['historyDetailedEntryCount']),
          historyExcludedEntryCount: _chartInt(counts['historyExcludedEntryCount']),
          historyFirstEntryCount: _chartInt(counts['historyFirstEntryCount']),
          historyUnverifiedDetailedEntryCount:
              _chartInt(counts['historyUnverifiedDetailedEntryCount']),
          historyLegacyDetailedEntryCount:
              _chartInt(counts['historyLegacyDetailedEntryCount']),
          historyAggregationMode:
              counts['historyAggregationMode']?.toString() ?? 'unknown',
          historyLogsUrls: _chartStringList(counts['historyLogsUrls']),
          historyAggregated: counts['historyAggregated'] == true,
          historySectorEntryCount: _chartInt(counts['historySectorEntryCount']),
          sectorMetrics: sectorMetrics,
        ),
      );
    }

    final totalDeparture = rawRows.fold<int>(0, (sum, row) => sum + row.departure);
    final totalFee = rawRows.fold<int>(0, (sum, row) => sum + row.fee);
    final rows = <_ChartARow>[];
    for (int i = 0; i < rawRows.length; i++) {
      final prev = i == 0 ? null : rawRows[i - 1];
      rows.add(
        rawRows[i].copyWith(
          no: i + 1,
          departureDelta: prev == null ? 0 : rawRows[i].departure - prev.departure,
          feeDelta: prev == null ? 0 : rawRows[i].fee - prev.fee,
          departureShare: totalDeparture == 0 ? 0 : rawRows[i].departure / totalDeparture,
          feeShare: totalFee == 0 ? 0 : rawRows[i].fee / totalFee,
        ),
      );
    }

    final metrics = _ChartAMetrics.fromRows(rows);
    final mergedSectorMetrics = EndWorkSectorMetrics.merge(
      rows
          .map((row) => row.sectorMetrics)
          .whereType<EndWorkSectorMetrics>(),
    );
    final sectorMetrics =
        mergedSectorMetrics.enabled ? mergedSectorMetrics : null;
    final rangeLabel = rows.isEmpty ? '-' : '${rows.first.dateStr} ~ ${rows.last.dateStr}';
    final sections = <_ChartASection>[
      _ChartASection(
        id: 'overview',
        title: '전체 요약 분석',
        subtitle: '출차와 정산금의 전체 흐름을 함께 봅니다.',
        type: _ChartASectionType.overview,
        icon: Icons.dashboard_rounded,
        rows: rows,
        metrics: metrics,
      ),
      _ChartASection(
        id: 'departure',
        title: '출차 분석',
        subtitle: '날짜별 출차 대수, 평균, 최고·최저 흐름입니다.',
        type: _ChartASectionType.departure,
        icon: Icons.logout_rounded,
        rows: rows,
        metrics: metrics,
      ),
      _ChartASection(
        id: 'fee',
        title: '정산금 분석',
        subtitle: '날짜별 정산금, 평균, 최고·최저 흐름입니다.',
        type: _ChartASectionType.fee,
        icon: Icons.payments_rounded,
        rows: rows,
        metrics: metrics,
      ),
      if (sectorMetrics != null)
        _ChartASection(
          id: 'sector',
          title: '방문 구역 분석',
          subtitle: '방문 구역별 차량 수와 잠금 금액을 기간 합산합니다.',
          type: _ChartASectionType.sector,
          icon: Icons.grid_view_rounded,
          rows: rows,
          metrics: metrics,
          sectorMetrics: sectorMetrics,
        ),
      _ChartASection(
        id: 'daily_table',
        title: '날짜별 상세표',
        subtitle: '출차·정산금·이전 비교일 대비 증감·기간 내 비중을 함께 정리했습니다.',
        type: _ChartASectionType.dailyTable,
        icon: Icons.table_chart_rounded,
        rows: rows,
        metrics: metrics,
      ),
    ];
    final toc = <_ChartATocItem>[
      const _ChartATocItem(id: 'cover', title: '표지', level: 0),
      const _ChartATocItem(id: 'summary', title: '보고서 요약', level: 0),
      const _ChartATocItem(id: 'a_group', title: '출차·정산 비교 본문', level: 0, isGroup: true),
      for (final section in sections) _ChartATocItem(id: section.id, title: section.title, level: 1),
    ];

    return _ChartAReport(
      rows: rows,
      rangeLabel: rangeLabel,
      metrics: metrics,
      sectorMetrics: sectorMetrics,
      sections: sections,
      tocItems: toc,
    );
  }
}

class _ChartASection {
  final String id;
  final String title;
  final String subtitle;
  final _ChartASectionType type;
  final IconData icon;
  final List<_ChartARow> rows;
  final _ChartAMetrics metrics;
  final EndWorkSectorMetrics? sectorMetrics;

  const _ChartASection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.icon,
    required this.rows,
    required this.metrics,
    this.sectorMetrics,
  });
}

enum _ChartASectionType { overview, departure, fee, sector, dailyTable }

class _ChartAMetrics {
  final int dayCount;
  final int totalDeparture;
  final int totalFee;
  final double averageDeparture;
  final double averageFee;
  final _ChartARow? maxDeparture;
  final _ChartARow? minDeparture;
  final _ChartARow? maxFee;
  final _ChartARow? minFee;

  const _ChartAMetrics({
    required this.dayCount,
    required this.totalDeparture,
    required this.totalFee,
    required this.averageDeparture,
    required this.averageFee,
    required this.maxDeparture,
    required this.minDeparture,
    required this.maxFee,
    required this.minFee,
  });

  factory _ChartAMetrics.fromRows(List<_ChartARow> rows) {
    final totalDeparture = rows.fold<int>(0, (sum, row) => sum + row.departure);
    final totalFee = rows.fold<int>(0, (sum, row) => sum + row.fee);
    _ChartARow? maxDeparture;
    _ChartARow? minDeparture;
    _ChartARow? maxFee;
    _ChartARow? minFee;
    for (final row in rows) {
      if (maxDeparture == null || row.departure > maxDeparture.departure) maxDeparture = row;
      if (minDeparture == null || row.departure < minDeparture.departure) minDeparture = row;
      if (maxFee == null || row.fee > maxFee.fee) maxFee = row;
      if (minFee == null || row.fee < minFee.fee) minFee = row;
    }
    final count = rows.length;
    return _ChartAMetrics(
      dayCount: count,
      totalDeparture: totalDeparture,
      totalFee: totalFee,
      averageDeparture: count == 0 ? 0 : totalDeparture / count,
      averageFee: count == 0 ? 0 : totalFee / count,
      maxDeparture: maxDeparture,
      minDeparture: minDeparture,
      maxFee: maxFee,
      minFee: minFee,
    );
  }
}

class _ChartARow {
  final int no;
  final DateTime date;
  final int departure;
  final int fee;
  final int departureDelta;
  final int feeDelta;
  final double departureShare;
  final double feeShare;
  final int historyEntryCount;
  final int historyDetailedEntryCount;
  final int historyExcludedEntryCount;
  final int historyFirstEntryCount;
  final int historyUnverifiedDetailedEntryCount;
  final int historyLegacyDetailedEntryCount;
  final String historyAggregationMode;
  final List<String> historyLogsUrls;
  final bool historyAggregated;
  final int historySectorEntryCount;
  final EndWorkSectorMetrics? sectorMetrics;

  const _ChartARow({
    required this.no,
    required this.date,
    required this.departure,
    required this.fee,
    required this.departureDelta,
    required this.feeDelta,
    required this.departureShare,
    required this.feeShare,
    required this.historyEntryCount,
    required this.historyDetailedEntryCount,
    required this.historyExcludedEntryCount,
    required this.historyFirstEntryCount,
    required this.historyUnverifiedDetailedEntryCount,
    required this.historyLegacyDetailedEntryCount,
    required this.historyAggregationMode,
    required this.historyLogsUrls,
    required this.historyAggregated,
    required this.historySectorEntryCount,
    required this.sectorMetrics,
  });

  String get dateStr => _dateOnly(date);

  _ChartARow copyWith({
    int? no,
    int? departureDelta,
    int? feeDelta,
    double? departureShare,
    double? feeShare,
  }) {
    return _ChartARow(
      no: no ?? this.no,
      date: date,
      departure: departure,
      fee: fee,
      departureDelta: departureDelta ?? this.departureDelta,
      feeDelta: feeDelta ?? this.feeDelta,
      departureShare: departureShare ?? this.departureShare,
      feeShare: feeShare ?? this.feeShare,
      historyEntryCount: historyEntryCount,
      historyDetailedEntryCount: historyDetailedEntryCount,
      historyExcludedEntryCount: historyExcludedEntryCount,
      historyFirstEntryCount: historyFirstEntryCount,
      historyUnverifiedDetailedEntryCount:
          historyUnverifiedDetailedEntryCount,
      historyLegacyDetailedEntryCount: historyLegacyDetailedEntryCount,
      historyAggregationMode: historyAggregationMode,
      historyLogsUrls: historyLogsUrls,
      historyAggregated: historyAggregated,
      historySectorEntryCount: historySectorEntryCount,
      sectorMetrics: sectorMetrics,
    );
  }
}

class _ChartATocItem {
  final String id;
  final String title;
  final int level;
  final bool isGroup;

  const _ChartATocItem({
    required this.id,
    required this.title,
    required this.level,
    this.isGroup = false,
  });
}

class _MailDraft {
  final String subject;
  final String body;

  const _MailDraft({required this.subject, required this.body});
}

class _MailAttachment {
  final String filename;
  final String mimeType;
  final Uint8List bytes;

  const _MailAttachment({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
}

class _MailComposeDialog extends StatefulWidget {
  final String initialSubject;
  final String initialBody;

  const _MailComposeDialog({
    required this.initialSubject,
    required this.initialBody,
  });

  @override
  State<_MailComposeDialog> createState() => _MailComposeDialogState();
}

class _MailComposeDialogState extends State<_MailComposeDialog> {
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.initialSubject);
    _bodyCtrl = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('PDF + 차량 CSV 메일 발신'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(
                labelText: '메일 제목(필수)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '메일 본문(선택)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PDF와 전체 차량 로그 CSV를 함께 첨부하며 수신자는 설정(EmailConfig)에서 관리됩니다.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              _MailDraft(
                subject: _subjectCtrl.text.trim(),
                body: _bodyCtrl.text,
              ),
            );
          },
          icon: const Icon(Icons.send_outlined),
          label: const Text('발신'),
        ),
      ],
    );
  }
}

class _DeepLoadRequest {
  final List<DateTime> dates;
  final DateTime? start;
  final DateTime? end;
  final String label;

  const _DeepLoadRequest._({
    required this.dates,
    required this.start,
    required this.end,
    required this.label,
  });

  factory _DeepLoadRequest.dates({
    required List<DateTime> dates,
    required String label,
  }) {
    return _DeepLoadRequest._(
      dates: dates,
      start: null,
      end: null,
      label: label,
    );
  }

  bool get isRange => start != null && end != null;
}

String _dateOnly(DateTime dt) => dt.toIso8601String().split('T').first;


int _chartInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
}

List<String> _chartStringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  final result = <String>[];
  for (final item in value) {
    final text = item?.toString().trim() ?? '';
    if (text.isEmpty || result.contains(text)) continue;
    result.add(text);
  }
  return List<String>.unmodifiable(result);
}

String _fmt(int value) {
  final negative = value < 0;
  final n = negative ? -value : value;
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromEnd = s.length - i;
    buf.write(s[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
      buf.write(',');
    }
  }
  return negative ? '-${buf.toString()}' : buf.toString();
}

String _signed(int value, {String prefix = '', String suffix = ''}) {
  if (value == 0) return '${prefix}0$suffix';
  final sign = value > 0 ? '+' : '-';
  final absValue = value.abs();
  return '$sign$prefix${_fmt(absValue)}$suffix';
}

String _compactChartValue(double value) {
  final abs = value.abs();
  if (abs >= 100000000) {
    final v = value / 100000000;
    return '${v.toStringAsFixed(v.abs() >= 10 ? 0 : 1)}억';
  }
  if (abs >= 10000) {
    final v = value / 10000;
    return '${v.toStringAsFixed(v.abs() >= 10 ? 0 : 1)}만';
  }
  if (abs >= 1000) {
    final v = value / 1000;
    return '${v.toStringAsFixed(v.abs() >= 10 ? 0 : 1)}천';
  }
  return value.round().toString();
}

int _axisLabelStep(int len, {int maxLabels = 7}) {
  if (len <= 0) return 1;
  if (len <= maxLabels) return 1;
  final step = (len / maxLabels).ceil();
  return step < 1 ? 1 : step;
}

double _chartMaxY(List<double> values) {
  if (values.isEmpty) return 1;
  final maxValue = values.fold<double>(0, (p, e) => e > p ? e : p);
  if (maxValue <= 0) return 1;
  final padded = maxValue * 1.18;
  if (padded < 5) return 5;
  return padded;
}
