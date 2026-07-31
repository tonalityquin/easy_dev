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
import '../../../../app/auth/google_auth_v7.dart';
import '../../../../app/config/email_config.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../dashboard/domain/models/end_work_sector_metrics.dart';
import 'statistics_chart_b_page.dart';
import 'statistics_deep_log_service.dart';
import 'statistics_deep_model.dart';
import 'statistics_report_design.dart';
import 'statistics_sector_pdf_builder.dart';

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

class _StatisticsChartPageState extends State<StatisticsChartPage> {
  final TextEditingController _mailSubjectCtrl = TextEditingController();
  final TextEditingController _mailBodyCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final StatisticsDeepLogService _deepLogService = StatisticsDeepLogService();
  bool _sending = false;
  bool _deepLoading = false;
  bool _tocOpen = false;
  String _selectedId = 'cover';
  StatisticsDeepReport? _deepReport;
  String? _deepLabel;
  late Map<String, GlobalKey> _sectionKeys;

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

  Future<DateTimeRange?> _showChartRangePicker({
    required BuildContext anchorContext,
    required DateTime firstDate,
    required DateTime lastDate,
    required DateTimeRange initialDateRange,
  }) {
    if (widget.useCommonUi) {
      return showCommonDateRangePicker(
        context: anchorContext,
        firstDate: firstDate,
        lastDate: lastDate,
        initialDateRange: initialDateRange,
        cancelText: '취소',
        confirmText: '적용',
      );
    }
    return showDateRangePicker(
      context: anchorContext,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
      cancelText: '취소',
      confirmText: '적용',
    );
  }

  @override
  void initState() {
    super.initState();
    _sectionKeys = <String, GlobalKey>{};
  }

  @override
  void dispose() {
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncSectionKeys(_ChartAReport report) {
    _sectionKeys = <String, GlobalKey>{
      'cover': GlobalKey(),
      'summary': GlobalKey(),
      for (final section in report.sections) section.id: GlobalKey(),
    };
  }

  Future<void> _scrollTo(String id) async {
    if (id.endsWith('_group')) return;
    final key = _sectionKeys[id];
    final context = key?.currentContext;
    if (context == null) return;
    setState(() {
      _selectedId = id;
      _tocOpen = false;
    });
    final reduceMotion =
        MediaQuery.maybeOf(this.context)?.disableAnimations ?? false;
    await Scrollable.ensureVisible(
      context,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
      curve: CommonUiMotion.enter,
      alignment: 0.02,
    );
  }

  Set<String> _reportDateKeys(_ChartAReport report) {
    return report.rows.map((row) => row.dateStr).toSet();
  }

  bool _deepReportMatchesChartReport(
    StatisticsDeepReport deep,
    _ChartAReport report,
  ) {
    final expected = _reportDateKeys(report);
    final actual = deep.dateStrs.toSet();
    return expected.length == actual.length && expected.containsAll(actual);
  }

  EndWorkSectorMetrics? _sectorMetricsForRequest(
    _ChartAReport report,
    _DeepLoadRequest request,
  ) {
    final requestedKeys = <String>{};
    if (request.isRange) {
      var cursor = DateTime(
        request.start!.year,
        request.start!.month,
        request.start!.day,
      );
      final end = DateTime(
        request.end!.year,
        request.end!.month,
        request.end!.day,
      );
      while (!cursor.isAfter(end)) {
        requestedKeys.add(_dateOnly(cursor));
        cursor = cursor.add(const Duration(days: 1));
      }
    } else {
      requestedKeys.addAll(request.dates.map(_dateOnly));
    }

    final availableKeys = _reportDateKeys(report);
    if (requestedKeys.isEmpty || !availableKeys.containsAll(requestedKeys)) {
      debugPrint(
        '[STAT_SECTOR_CROSS] skipped requested=${requestedKeys.length} '
        'available=${availableKeys.length} complete=${availableKeys.containsAll(requestedKeys)}',
      );
      return null;
    }

    final selected = report.rows.where(
      (row) => requestedKeys.contains(row.dateStr),
    );
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

  Future<void> _openMailDialogAndSend(_ChartAReport report) async {
    HapticFeedback.selectionClick();
    if (report.rows.isEmpty) return;

    final draft = await _showChartDialog<_MailDraft>(
      barrierDismissible: true,
      builder: (ctx) => _MailComposeDialog(
        initialSubject: _mailSubjectCtrl.text.trim().isEmpty
            ? '통계 그래프 A 리포트 (${report.rangeLabel})'
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
        title: '통계 PDF 방문 구역 집계',
        initialMessage: '방문 구역 통계를 포함한 PDF를 준비하고 있습니다.',
        useCommonUi: widget.useCommonUi,
        developerModeMessage:
            '개발자 모드 ON: PDF 생성 및 발신 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: PDF 생성 및 발신 로그를 콘솔에 기록합니다.',
      );
      trace.log(
        'range=${report.rangeLabel} days=${report.metrics.dayCount} '
        'sectorEnabled=${report.sectorMetrics != null} '
        'sectorCount=${report.sectorMetrics?.sectorCount ?? 0}',
        progress: .12,
      );
      StatisticsDeepReport? deepReportForPdf = _deepReport;
      if (deepReportForPdf != null &&
          !_deepReportMatchesChartReport(deepReportForPdf, report)) {
        trace.log('deep=reload reason=dateScopeMismatch');
        deepReportForPdf = null;
      }
      final area = widget.area.trim();
      final sectorEnabled = widget.areaSectorEnabled[area] == true;
      if (sectorEnabled && deepReportForPdf == null) {
        final dates = report.rows
            .map((row) => DateTime.tryParse(row.dateStr))
            .whereType<DateTime>()
            .map((date) => DateTime(date.year, date.month, date.day))
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
        if (dates.isEmpty) {
          await trace.fail('Sector PDF에 필요한 조회 날짜를 구성하지 못했습니다.');
          return;
        }
        trace.log(
          'deep=autoLoad area=$area dates=${dates.length} sectorEnabled=true',
          progress: .16,
        );
        deepReportForPdf = await _deepLogService.loadByDates(
          division: widget.division.trim(),
          area: area,
          dates: dates,
          scopeLabel: report.rangeLabel,
          sectorEnabled: true,
        );
        if (mounted) {
          setState(() {
            _deepReport = deepReportForPdf;
            _deepLabel = deepReportForPdf!.scopeLabel;
          });
        }
      }
      final deepSector = deepReportForPdf?.sectorReport;
      if (sectorEnabled && deepSector == null) {
        await trace.fail('Sector 지원 Area이지만 공통 Sector 보고서가 없습니다.');
        return;
      }
      if (deepSector != null) {
        for (final line in deepSector.integrity.debugLines) {
          trace.log(line, progress: .18);
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
          await trace.fail('화면·PDF Sector 합계 무결성 검증에 실패했습니다.');
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
          final cross = _crossValidateSectorMetrics(
            expected: expectedSector,
            actual: deepSector,
          );
          for (final line in cross.debugLines) {
            trace.log(line, progress: .24);
          }
          if (!cross.isValid) {
            await trace.fail('Firestore 보고서와 GCS CSV의 Sector 합계가 일치하지 않습니다.');
            return;
          }
        }
      }

      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        await trace.fail('PDF 수신자 설정이 올바르지 않습니다.');
        return;
      }
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      if (!mounted) return;
      final pdfPalette = StatisticsReportDesign.pdfPalette(context);
      trace.log(
        'pdf=build sectorGroups=${deepSector?.groups.length ?? 0} '
        'design=app-theme-v3 ${pdfPalette.debugLabel}',
        progress: .34,
      );
      final pdfBytes = await _buildStatsPdfBytes(
        report: report,
        deepReport: deepReportForPdf,
        palette: pdfPalette,
      );
      final filename =
          '${_safeFileName('통계그래프A_${_dateTag(DateTime.now())}')}.pdf';
      trace.log(
        'pdf=ready bytes=${pdfBytes.length} filename=$filename',
        progress: .62,
      );

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: filename,
        to: toCsv,
        subject: subject,
        body: body,
      );
      trace.log('gmail=sent recipients=$toCsv', progress: .92);
      await trace.succeed(
        deepSector != null
            ? '방문 구역 통계를 포함한 PDF 발신이 완료되었습니다.'
            : '방문 구역 집계가 없는 통계 PDF 발신이 완료되었습니다.',
      );
    } catch (e, st) {
      debugPrint('메일 전송 실패: $e');
      debugPrint('$st');
      if (trace != null) {
        await trace.fail(
          '통계 PDF 생성 또는 발신에 실패했습니다.',
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
    debugPrint(
      '[STAT_PDF_DESIGN] build style=app-theme-v3 ${palette.debugLabel} '
      'days=${report.metrics.dayCount} deep=${deepReport != null} '
      'sector=${deepReport?.sectorReport != null}',
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
          label: '심화 차량',
          value: '${_fmt(deepReport.rows.length)}대',
          tone: StatisticsPdfTone.input,
        ),
      if (deepReport != null)
        StatisticsPdfMetricData(
          label: '심화 입차',
          value: '${_fmt(deepReport.overallSection.metrics.inputTotalSum)}대',
          tone: StatisticsPdfTone.input,
        ),
      if (deepReport != null)
        StatisticsPdfMetricData(
          label: '심화 출차',
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
        label: 'Statistics Graph A',
        tone: StatisticsPdfTone.output,
      ),
      if (deepReport != null)
        const StatisticsPdfTagData(
          label: 'Deep Statistics B',
          tone: StatisticsPdfTone.input,
        ),
      if (deepReport?.sectorReport != null)
        const StatisticsPdfTagData(
          label: 'Sector Analytics',
          tone: StatisticsPdfTone.success,
        ),
    ];

    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => design.cover(
          reportCode: 'STATISTICS REPORT',
          titleText: '통계 운영 분석 보고서',
          subtitle: '출차·정산·입차·방문 구역 데이터를 하나의 운영 문서로 구성했습니다.',
          description:
              '앱의 통계 화면과 동일한 지표 순서와 상태 체계를 사용하며, 화면과 PDF는 같은 집계 모델을 공유합니다.',
          createdAt: createdAt,
          tags: coverTags,
          metrics: coverMetrics,
          division: widget.division,
          area: widget.area,
          rangeLabel: report.rangeLabel,
        ),
      ),
    );

    final tocRows = <List<String>>[
      ['01', '경영 요약', '핵심 KPI와 날짜별 운영 결과'],
      for (int index = 0; index < report.sections.length; index++)
        [
          (index + 2).toString().padLeft(2, '0'),
          report.sections[index].title,
          report.sections[index].subtitle,
        ],
    ];
    if (deepReport != null) {
      var number = tocRows.length + 1;
      tocRows.add([
        number.toString().padLeft(2, '0'),
        deepReport.overallSection.title,
        deepReport.scopeLabel,
      ]);
      number++;
      if (deepReport.sectorEnabled && deepReport.sectorReport != null) {
        tocRows.add([
          number.toString().padLeft(2, '0'),
          '방문 구역 분석',
          'Sector별 입차·출차·정산·결제수단·요일·차량 로그',
        ]);
        number++;
      }
      for (final section in deepReport.dailySections) {
        tocRows.add([
          number.toString().padLeft(2, '0'),
          section.title,
          section.subtitle,
        ]);
        number++;
      }
      for (final section in deepReport.weekdaySections) {
        tocRows.add([
          number.toString().padLeft(2, '0'),
          section.title,
          section.subtitle,
        ]);
        number++;
      }
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
            titleText: '문서 구성',
            subtitle: '화면에서 확인한 지표를 운영 의사결정 순서로 재배치했습니다.',
            eyebrow: 'REPORT MAP',
            sectionNumber: '01',
          ),
          pw.SizedBox(height: 14),
          design.notice(
            titleText: '읽는 순서',
            message: '핵심 요약에서 전체 흐름을 확인한 뒤 세부 통계와 차량 로그로 이동합니다.',
            tone: StatisticsPdfTone.primary,
          ),
          pw.SizedBox(height: 12),
          design.dataTable(
            headers: const ['No', '섹션', '주요 내용'],
            rows: tocRows,
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(34),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(2.1),
            },
            tone: StatisticsPdfTone.primary,
            fontSize: 8.5,
            headerFontSize: 8.5,
            verticalPadding: 6,
          ),
        ],
      ),
    );

    for (int sectionIndex = 0;
        sectionIndex < report.sections.length;
        sectionIndex++) {
      final section = report.sections[sectionIndex];
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
          header: header,
          footer: footer,
          build: (context) => [
            design.sectionHeader(
              titleText: section.title,
              subtitle: section.subtitle,
              eyebrow: 'STATISTICS GRAPH A',
              sectionNumber: (sectionIndex + 2).toString().padLeft(2, '0'),
              tone: _pdfSectionTone(section.type),
            ),
            pw.SizedBox(height: 12),
            _pdfASectionMetrics(section, design),
            pw.SizedBox(height: 12),
            if (section.type == _ChartASectionType.overview) ...[
              _pdfLineBars(
                design: design,
                title: '날짜별 출차 흐름',
                subtitle: '날짜별 완료 차량의 출차 대수를 비교합니다.',
                rows: section.rows,
                valueOf: (row) => row.departure.toDouble(),
                suffix: '대',
                decimal: false,
                tone: StatisticsPdfTone.output,
              ),
              pw.SizedBox(height: 10),
              _pdfLineBars(
                design: design,
                title: '날짜별 정산금 흐름',
                subtitle: '날짜별 잠금 정산금의 규모를 비교합니다.',
                rows: section.rows,
                valueOf: (row) => row.fee.toDouble(),
                suffix: '원',
                decimal: false,
                tone: StatisticsPdfTone.fee,
              ),
            ] else if (section.type == _ChartASectionType.departure) ...[
              _pdfLineBars(
                design: design,
                title: '출차 대수 추이',
                subtitle: '전일 대비 증감과 함께 확인합니다.',
                rows: section.rows,
                valueOf: (row) => row.departure.toDouble(),
                suffix: '대',
                decimal: false,
                tone: StatisticsPdfTone.output,
              ),
            ] else if (section.type == _ChartASectionType.fee) ...[
              _pdfLineBars(
                design: design,
                title: '정산금 추이',
                subtitle: '전일 대비 잠금 금액 증감을 확인합니다.',
                rows: section.rows,
                valueOf: (row) => row.fee.toDouble(),
                suffix: '원',
                decimal: false,
                tone: StatisticsPdfTone.fee,
              ),
            ] else if (section.type == _ChartASectionType.sector &&
                section.sectorMetrics != null) ...[
              _pdfSectorTable(section.sectorMetrics!, design),
              if (section.sectorMetrics!.legacyFeeClassification) ...[
                pw.SizedBox(height: 10),
                design.notice(
                  titleText: '구버전 Sector 금액 분류',
                  message:
                      '이 보고서는 미지정과 데이터 확인 필요 잠금 금액이 통합되어 있을 수 있습니다.',
                  tone: StatisticsPdfTone.warning,
                  details: const <String>[
                    '차량 수는 분리되지만 과거 집계값만으로 금액을 정확히 재분류할 수 없습니다.',
                    '개별 차량 GCS 로그가 있는 범위는 심화 Sector 재집계값을 우선 확인합니다.',
                  ],
                ),
              ],
            ],
            if (section.type == _ChartASectionType.dailyTable) ...[
              _pdfARowsTable(section.rows, design),
            ],
          ],
        ),
      );
    }

    if (deepReport != null) {
      _addDeepReportSectionsToPdf(
        doc: doc,
        theme: theme,
        footer: footer,
        report: deepReport,
        design: design,
      );
      StatisticsSectorPdfBuilder.append(
        doc: doc,
        theme: theme,
        footer: footer,
        report: deepReport,
        design: design,
      );
    }

    final bytes = await doc.save();
    debugPrint(
      '[STAT_PDF_DESIGN] complete bytes=${bytes.length} style=app-theme-v3',
    );
    return bytes;
  }

  StatisticsPdfTone _pdfSectionTone(_ChartASectionType type) {
    switch (type) {
      case _ChartASectionType.overview:
        return StatisticsPdfTone.primary;
      case _ChartASectionType.departure:
        return StatisticsPdfTone.output;
      case _ChartASectionType.fee:
        return StatisticsPdfTone.fee;
      case _ChartASectionType.sector:
        return StatisticsPdfTone.secondary;
      case _ChartASectionType.dailyTable:
        return StatisticsPdfTone.neutral;
    }
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
    final rows = <List<String>>[
      for (final item in metrics.items)
        <String>[
          item.sectorName,
          '${item.vehicleCount}대',
          '₩${_fmt(item.totalLockedFee.round())}',
          metrics.assignedVehicleCount == 0
              ? '0.0%'
              : '${(item.vehicleCount / metrics.assignedVehicleCount * 100).toStringAsFixed(1)}%',
        ],
      if (metrics.unassignedVehicleCount > 0)
        <String>[
          '미지정',
          '${metrics.unassignedVehicleCount}대',
          '₩${_fmt(metrics.unassignedLockedFee.round())}',
          metrics.totalVehicleCount == 0
              ? '0.0%'
              : '${(metrics.unassignedVehicleCount / metrics.totalVehicleCount * 100).toStringAsFixed(1)}%',
        ],
      if (metrics.invalidSectorVehicleCount > 0)
        <String>[
          '데이터 확인 필요',
          '${metrics.invalidSectorVehicleCount}대',
          '₩${_fmt(metrics.invalidSectorLockedFee.round())}',
          metrics.totalVehicleCount == 0
              ? '0.0%'
              : '${(metrics.invalidSectorVehicleCount / metrics.totalVehicleCount * 100).toStringAsFixed(1)}%',
        ],
    ];
    return design.dataTable(
      headers: const ['방문 구역', '차량 수', '잠금 금액', '비중'],
      rows: rows,
      numericColumns: const <int>{1, 2, 3},
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.7),
        1: pw.FlexColumnWidth(.8),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(.7),
      },
      tone: StatisticsPdfTone.secondary,
      fontSize: 8.4,
      headerFontSize: 8.4,
      verticalPadding: 6,
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
    return design.dataTable(
      headers: const [
        'No',
        '날짜',
        '출차',
        '정산금',
        '출차 증감',
        '정산금 증감',
        '출차 비중',
        '정산금 비중',
      ],
      rows: [
        for (final row in rows)
          [
            row.no.toString(),
            row.dateStr,
            '${_fmt(row.departure)}대',
            '₩${_fmt(row.fee)}',
            _signed(row.departureDelta, suffix: '대'),
            _signed(row.feeDelta, prefix: '₩'),
            '${(row.departureShare * 100).toStringAsFixed(1)}%',
            '${(row.feeShare * 100).toStringAsFixed(1)}%',
          ],
      ],
      numericColumns: const <int>{0, 2, 3, 4, 5, 6, 7},
      tone: StatisticsPdfTone.neutral,
      fontSize: 7.2,
      headerFontSize: 7.4,
      horizontalPadding: 3.5,
      verticalPadding: 4.5,
    );
  }

  void _addDeepReportSectionsToPdf({
    required pw.Document doc,
    required pw.ThemeData theme,
    required pw.Widget Function(pw.Context context) footer,
    required StatisticsDeepReport report,
    required StatisticsPdfDesign design,
  }) {
    pw.Widget header(pw.Context context) {
      return design.runningHeader(
        reportTitle: '심화 통계 보고서',
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

    void addVehicleTables(StatisticsDeepSection section) {
      const chunkSize = 28;
      for (int start = 0; start < section.rows.length; start += chunkSize) {
        final chunk = section.rows.skip(start).take(chunkSize).toList();
        doc.addPage(
          pw.MultiPage(
            theme: theme,
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(22, 25, 22, 30),
            header: header,
            footer: footer,
            build: (context) => [
              design.sectionHeader(
                titleText: '${section.title} 차량 로그',
                subtitle:
                    '${start + 1} - ${start + chunk.length} / ${section.rows.length}',
                eyebrow: 'VEHICLE LOG',
                tone: StatisticsPdfTone.neutral,
              ),
              pw.SizedBox(height: 10),
              design.dataTable(
                headers: [
                  'No',
                  '날짜',
                  '차량 번호',
                  if (report.sectorEnabled) '방문 구역',
                  '입차',
                  '출차',
                  '정산액',
                  '결제수단',
                ],
                rows: [
                  for (final row in chunk)
                    [
                      row.no.toString(),
                      row.dateStr,
                      row.plateNumber,
                      if (report.sectorEnabled) row.sectorLabel,
                      _fmtPdfTime(row.createdAt),
                      row.departureTimeEstimated
                          ? '${_fmtPdfTime(row.departureAt)} 추정'
                          : _fmtPdfTime(row.departureAt),
                      row.fee == null ? '-' : '₩${_fmt(row.fee!)}',
                      row.paymentMethodLabel,
                    ],
                ],
                numericColumns: report.sectorEnabled
                    ? const <int>{0, 6}
                    : const <int>{0, 5},
                tone: StatisticsPdfTone.neutral,
                fontSize: report.sectorEnabled ? 6.8 : 7.1,
                headerFontSize: report.sectorEnabled ? 6.9 : 7.2,
                horizontalPadding: 3.1,
                verticalPadding: 4.4,
              ),
            ],
          ),
        );
      }
    }

    void addSection(
      StatisticsDeepSection section, {
      required bool includeVehicleTable,
      required int index,
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
              eyebrow: 'DEEP STATISTICS B',
              sectionNumber: index.toString().padLeft(2, '0'),
              tone: StatisticsPdfTone.input,
            ),
            pw.SizedBox(height: 12),
            metricPanel(section),
            pw.SizedBox(height: 12),
            chartSet(section),
          ],
        ),
      );
      if (includeVehicleTable) addVehicleTables(section);
    }

    var index = 1;
    addSection(
      report.overallSection,
      includeVehicleTable: true,
      index: index,
    );
    index++;
    for (final section in report.dailySections) {
      addSection(section, includeVehicleTable: false, index: index);
      index++;
    }
    for (final section in report.weekdaySections) {
      addSection(section, includeVehicleTable: false, index: index);
      index++;
    }
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    const scopes = <String>[
      'https://www.googleapis.com/auth/gmail.send',
    ];

    final client = await GoogleAuthV7.authedClient(scopes);
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
    } finally {
      client.close();
    }
  }

  Future<_DeepLoadRequest?> _pickDeepLoadRequest(_ChartAReport report) async {
    final sortedDates = report.rows.map((e) => e.date).toList()..sort((a, b) => a.compareTo(b));
    if (sortedDates.isEmpty) return null;
    if (sortedDates.length == 1) {
      final only = sortedDates.first;
      return _DeepLoadRequest.dates(dates: <DateTime>[only], label: _dateOnly(only));
    }

    return _showChartDialog<_DeepLoadRequest>(
      barrierDismissible: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final first = sortedDates.first;
        final last = sortedDates.last;
        return AlertDialog(
          title: const Text('심화 통계 범위 선택'),
          content: SizedBox(
            width: 390,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.dataset_rounded),
                  title: const Text('가져온 날짜 모두'),
                  subtitle: Text('${_dateOnly(first)} ~ ${_dateOnly(last)} / ${sortedDates.length}일'),
                  onTap: () => Navigator.of(ctx).pop(
                    _DeepLoadRequest.dates(
                      dates: sortedDates,
                      label: '${_dateOnly(first)} ~ ${_dateOnly(last)}',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.date_range_rounded),
                  title: const Text('기간 지정'),
                  subtitle: const Text('시작일과 종료일을 선택합니다.'),
                  onTap: () async {
                    final picked = await _showChartRangePicker(
                      anchorContext: ctx,
                      firstDate: first,
                      lastDate: last,
                      initialDateRange: DateTimeRange(
                        start: first,
                        end: last,
                      ),
                    );
                    if (picked == null) return;
                    final a = DateTime(picked.start.year, picked.start.month, picked.start.day);
                    final b = DateTime(picked.end.year, picked.end.month, picked.end.day);
                    Navigator.of(ctx).pop(
                      _DeepLoadRequest.range(
                        start: a,
                        end: b,
                        label: '${_dateOnly(a)} ~ ${_dateOnly(b)}',
                      ),
                    );
                  },
                ),
                Divider(color: cs.outlineVariant),
                for (final date in sortedDates)
                  ListTile(
                    leading: const Icon(Icons.event_rounded),
                    title: Text(_dateOnly(date)),
                    onTap: () => Navigator.of(ctx).pop(
                      _DeepLoadRequest.dates(
                        dates: <DateTime>[date],
                        label: _dateOnly(date),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openDeepStatistics(_ChartAReport report) async {
    if (_deepLoading) return;

    final division = widget.division.trim();
    final area = widget.area.trim();
    if (division.isEmpty || area.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('심화 통계에 필요한 사업부/지역 정보가 없습니다.')),
      );
      return;
    }

    final request = await _pickDeepLoadRequest(report);
    if (request == null) return;

    setState(() => _deepLoading = true);
    DeveloperOperationTrace? trace;
    try {
      final sectorEnabled = widget.areaSectorEnabled[area] == true;
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '심화 통계 조회',
        initialMessage: 'GCS 완료 업무 로그를 조회하고 통계를 구성하고 있습니다.',
        useCommonUi: widget.useCommonUi,
        developerModeMessage:
            '개발자 모드 ON: CSV·Sector·무결성 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 심화 통계 로그를 콘솔에 기록합니다.',
      );
      trace.log(
        'division=$division area=$area scope=${request.label} '
        'dates=${request.isRange ? 'range' : request.dates.length} '
        'sectorEnabled=$sectorEnabled',
        progress: .08,
      );

      final StatisticsDeepReport deep;
      if (request.isRange) {
        deep = await _deepLogService.loadByDateRange(
          division: division,
          area: area,
          start: request.start!,
          end: request.end!,
          sectorEnabled: sectorEnabled,
        );
      } else {
        deep = await _deepLogService.loadByDates(
          division: division,
          area: area,
          dates: request.dates,
          scopeLabel: request.label,
          sectorEnabled: sectorEnabled,
        );
      }

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
        for (final group in sector.groups) {
          trace.log(
            'sector=${group.sectorLabel} key=${group.key} '
            'vehicles=${group.vehicleCount} input=${group.inputCount} '
            'output=${group.outputCount} fee=${group.totalLockedFee} '
            'estimatedOutput=${group.estimatedDepartureCount}',
            progress: .78,
          );
        }
      }
      if (sectorEnabled && sector == null) {
        await trace.fail('Sector 지원 Area이지만 Sector 보고서가 생성되지 않았습니다.');
        return;
      }
      if (sector != null && !sector.integrity.isValid) {
        await trace.fail('심화 통계 Sector 합계 무결성 검증에 실패했습니다.');
        return;
      }
      if (sector != null) {
        trace.log(
          'sector source total=${sector.totalVehicleCount} '
          'analyzable=${sector.analyzableVehicleCount} '
          'unavailable=${sector.unavailableVehicleCount} '
          'complete=${sector.sourceFieldComplete}',
          progress: .82,
        );
      }
      final expectedSector = _sectorMetricsForRequest(report, request);
      if (sector != null && !sector.sourceFieldComplete) {
        trace.log(
          'sector cross validation skipped because source fields are unavailable for ${sector.unavailableVehicleCount} vehicles',
        );
      }
      if (expectedSector?.legacyFeeClassification == true) {
        trace.log('sector cross validation skipped for legacy fee classification');
      }
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
          await trace.fail('Firestore 보고서와 GCS CSV의 Sector 합계가 일치하지 않습니다.');
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _deepReport = deep;
        _deepLabel = deep.scopeLabel;
      });
      await trace.succeed(
        sectorEnabled
            ? 'Sector 통계와 차량 로그 구성이 완료되었습니다.'
            : '심화 통계 구성이 완료되었습니다.',
      );

      if (!mounted) return;
      final chartPage = StatisticsChartBPage(
        report: deep,
        availableAreas: widget.availableAreas,
        areaSectorEnabled: widget.areaSectorEnabled,
        useCommonUi: widget.useCommonUi,
      );
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final route = widget.useCommonUi
          ? PageRouteBuilder<StatisticsDeepReport>(
              transitionDuration:
                  reduceMotion ? Duration.zero : CommonUiMotion.overlay,
              reverseTransitionDuration:
                  reduceMotion ? Duration.zero : CommonUiMotion.overlay,
              pageBuilder: (_, __, ___) => CommonUiScope(child: chartPage),
              transitionsBuilder: (_, animation, __, child) {
                if (reduceMotion) return child;
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: CommonUiMotion.enter,
                  reverseCurve: CommonUiMotion.exit,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.025, 0),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
            )
          : MaterialPageRoute<StatisticsDeepReport>(
              builder: (_) => chartPage,
            );
      final visible =
          await Navigator.of(context).push<StatisticsDeepReport>(route);

      if (!mounted) return;
      final nextModel = visible ?? deep;
      setState(() {
        _deepReport = nextModel;
        _deepLabel = nextModel.scopeLabel;
      });
    } catch (e, st) {
      debugPrint('[STAT_DEEP] load failed: $e');
      debugPrint('$st');
      if (trace != null) {
        await trace.fail(
          '심화 통계 조회에 실패했습니다.',
          error: e,
          stackTrace: st,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('심화 통계 로드 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _deepLoading = false);
    }
  }

  Widget _buildDeepActionButton({
    required _ChartAReport report,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasDeep = _deepReport != null;
    final bg = _deepLoading
        ? cs.surfaceContainerHighest
        : hasDeep
        ? cs.tertiaryContainer
        : cs.secondaryContainer;
    final fg = _deepLoading
        ? cs.onSurfaceVariant
        : hasDeep
        ? cs.onTertiaryContainer
        : cs.onSecondaryContainer;
    final label = hasDeep && (_deepLabel ?? '').trim().isNotEmpty ? '심화 ${_deepLabel!.trim()}' : '심화';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: report.rows.isNotEmpty && !_deepLoading ? () => _openDeepStatistics(report) : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_deepLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              else
                Icon(Icons.auto_graph_rounded, size: 18, color: fg),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSendActionButton(_ChartAReport report) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilledButton.icon(
        onPressed: _sending || report.rows.isEmpty
            ? null
            : () => _openMailDialogAndSend(report),
        icon: AnimatedSwitcher(
          duration: duration,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          child: _sending
              ? SizedBox(
                  key: const ValueKey<String>('statistics_pdf_sending'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Icon(
                  Icons.picture_as_pdf_rounded,
                  key: ValueKey<String>('statistics_pdf_ready'),
                ),
        ),
        label: AnimatedSwitcher(
          duration: duration,
          child: Text(
            _sending ? '발신 중' : 'PDF 발신',
            key: ValueKey<bool>(_sending),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _ChartAReport.from(
      widget.reportDataMap,
      sectorEnabled: widget.areaSectorEnabled[widget.area.trim()] == true,
    );
    _syncSectionKeys(report);
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_sending && !_deepLoading,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('통계 그래프 A'),
          actions: [
            _buildDeepActionButton(report: report),
            _buildSendActionButton(report),
            IconButton(
              tooltip: _tocOpen ? '목차 닫기' : '목차 열기',
              onPressed: () => setState(() => _tocOpen = !_tocOpen),
              icon: Icon(_tocOpen ? Icons.close_rounded : Icons.menu_book_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: report.rows.isEmpty
            ? const _AEmptyState()
            : LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: _sectionKeys['cover'],
                          child: _AReportCover(
                            report: report,
                            division: widget.division,
                            area: widget.area,
                            deepReport: _deepReport,
                          ),
                        ),
                        const SizedBox(height: 14),
                        KeyedSubtree(
                          key: _sectionKeys['summary'],
                          child: _AReportSummary(report: report),
                        ),
                        const SizedBox(height: 14),
                        for (final section in report.sections) ...[
                          KeyedSubtree(
                            key: _sectionKeys[section.id],
                            child: _ASectionView(section: section),
                          ),
                          const SizedBox(height: 14),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                if (_tocOpen)
                  _AReportTocOverlay(
                    width: math.min(390.0, math.max(300.0, constraints.maxWidth * 0.86)),
                    report: report,
                    selectedId: _selectedId,
                    onTap: _scrollTo,
                    onClose: () => setState(() => _tocOpen = false),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '통계그래프A' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _dateTag(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
  }

}

class _AReportCover extends StatelessWidget {
  final _ChartAReport report;
  final String division;
  final String area;
  final StatisticsDeepReport? deepReport;

  const _AReportCover({
    required this.report,
    required this.division,
    required this.area,
    required this.deepReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: StatisticsReportDesign.screenPanel(context, emphasized: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatisticsReportDesign.screenPill(context: context, icon: Icons.insights_rounded, text: 'Statistics Graph A', strong: true),
              if (division.trim().isNotEmpty) StatisticsReportDesign.screenPill(context: context, icon: Icons.apartment_rounded, text: division.trim()),
              if (area.trim().isNotEmpty) StatisticsReportDesign.screenPill(context: context, icon: Icons.location_on_rounded, text: area.trim()),
              if (deepReport != null) StatisticsReportDesign.screenPill(context: context, icon: Icons.auto_graph_rounded, text: 'B 심화 포함'),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '통계 그래프 A',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '날짜별 출차와 정산금 집계를 보고서형 화면으로 재구성했습니다.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onPrimaryContainer.withOpacity(0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CoverMetric(label: '대상 기간', value: report.rangeLabel, icon: Icons.date_range_rounded),
              _CoverMetric(label: '대상 날짜', value: '${report.metrics.dayCount}일', icon: Icons.event_note_rounded),
              _CoverMetric(label: '출차 합계', value: '${_fmt(report.metrics.totalDeparture)}대', icon: Icons.logout_rounded),
              _CoverMetric(label: '정산금 합계', value: '₩${_fmt(report.metrics.totalFee)}', icon: Icons.payments_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CoverMetric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AReportSummary extends StatelessWidget {
  final _ChartAReport report;

  const _AReportSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ASectionHeaderLine(
            icon: Icons.dashboard_customize_rounded,
            title: '보고서 요약',
            subtitle: '통계 그래프 A의 전체 기간 핵심 지표입니다.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricTile(label: '출차 합계', value: '${_fmt(m.totalDeparture)}대', icon: Icons.logout_rounded),
              _MetricTile(label: '출차 평균', value: '${m.averageDeparture.toStringAsFixed(1)}대', icon: Icons.functions_rounded),
              _MetricTile(label: '정산금 합계', value: '₩${_fmt(m.totalFee)}', icon: Icons.payments_rounded),
              _MetricTile(label: '정산금 평균', value: '₩${_fmt(m.averageFee.round())}', icon: Icons.query_stats_rounded),
              _MetricTile(label: '최고 출차', value: m.maxDeparture == null ? '-' : '${m.maxDeparture!.dateStr} · ${m.maxDeparture!.departure}대', icon: Icons.trending_up_rounded),
              _MetricTile(label: '최고 정산금', value: m.maxFee == null ? '-' : '${m.maxFee!.dateStr} · ₩${_fmt(m.maxFee!.fee)}', icon: Icons.workspace_premium_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _ASectionView extends StatelessWidget {
  final _ChartASection section;

  const _ASectionView({required this.section});

  @override
  Widget build(BuildContext context) {
    final sectorMetrics = section.sectorMetrics;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ASectionHeaderLine(
            icon: section.icon,
            title: section.title,
            subtitle: section.subtitle,
          ),
          const SizedBox(height: 14),
          if (section.type == _ChartASectionType.sector &&
              sectorMetrics != null) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricTile(
                  label: '방문 구역',
                  value: '${sectorMetrics.sectorCount}개',
                  icon: Icons.grid_view_rounded,
                ),
                _MetricTile(
                  label: '지정 차량',
                  value: '${sectorMetrics.assignedVehicleCount}대',
                  icon: Icons.check_circle_outline_rounded,
                ),
                _MetricTile(
                  label: '미지정 차량',
                  value: '${sectorMetrics.unassignedVehicleCount}대',
                  icon: Icons.help_outline_rounded,
                ),
                _MetricTile(
                  label: '지정 잠금 금액',
                  value: '₩${_fmt(sectorMetrics.assignedLockedFee.round())}',
                  icon: Icons.payments_rounded,
                ),
                _MetricTile(
                  label: '미지정 잠금 금액',
                  value: '₩${_fmt(sectorMetrics.unassignedLockedFee.round())}',
                  icon: Icons.money_off_rounded,
                ),
                _MetricTile(
                  label: '데이터 확인 필요',
                  value: '${sectorMetrics.invalidSectorVehicleCount}대',
                  icon: Icons.rule_rounded,
                ),
                _MetricTile(
                  label: '확인 필요 잠금 금액',
                  value: '₩${_fmt(sectorMetrics.invalidSectorLockedFee.round())}',
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
            if (sectorMetrics.legacyFeeClassification) ...[
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                    ? Duration.zero
                    : CommonUiMotion.layout,
                curve: CommonUiMotion.enter,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '구버전 보고서에서는 미지정과 데이터 확인 필요 잠금 금액이 통합되어 있을 수 있습니다.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _ASectorBreakdownCard(metrics: sectorMetrics),
          ] else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricTile(
                  label: '대상 날짜',
                  value: '${section.metrics.dayCount}일',
                  icon: Icons.event_rounded,
                ),
                _MetricTile(
                  label: '출차 합계',
                  value: '${_fmt(section.metrics.totalDeparture)}대',
                  icon: Icons.logout_rounded,
                ),
                _MetricTile(
                  label: '출차 평균',
                  value: '${section.metrics.averageDeparture.toStringAsFixed(1)}대',
                  icon: Icons.functions_rounded,
                ),
                _MetricTile(
                  label: '정산금 합계',
                  value: '₩${_fmt(section.metrics.totalFee)}',
                  icon: Icons.payments_rounded,
                ),
                _MetricTile(
                  label: '정산금 평균',
                  value: '₩${_fmt(section.metrics.averageFee.round())}',
                  icon: Icons.query_stats_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (section.type == _ChartASectionType.overview)
              _AChartGrid(
                children: [
                  _DateLineChartCard(
                    title: '날짜별 출차 흐름',
                    subtitle: '출차 대수 추이',
                    rows: section.rows,
                    valueOf: (row) => row.departure.toDouble(),
                    valueText: (v) => '${_fmt(v.round())}대',
                    icon: Icons.logout_rounded,
                  ),
                  _DateLineChartCard(
                    title: '날짜별 정산금 흐름',
                    subtitle: '정산금 추이',
                    rows: section.rows,
                    valueOf: (row) => row.fee.toDouble(),
                    valueText: (v) => '₩${_fmt(v.round())}',
                    icon: Icons.payments_rounded,
                  ),
                ],
              )
            else if (section.type == _ChartASectionType.departure)
              _DateLineChartCard(
                title: '출차 대수 분석',
                subtitle: '날짜별 출차 대수와 증감 흐름',
                rows: section.rows,
                valueOf: (row) => row.departure.toDouble(),
                valueText: (v) => '${_fmt(v.round())}대',
                icon: Icons.logout_rounded,
              )
            else if (section.type == _ChartASectionType.fee)
              _DateLineChartCard(
                title: '정산금 분석',
                subtitle: '날짜별 정산금과 증감 흐름',
                rows: section.rows,
                valueOf: (row) => row.fee.toDouble(),
                valueText: (v) => '₩${_fmt(v.round())}',
                icon: Icons.payments_rounded,
              )
            else
              _ADailyTableCard(rows: section.rows),
            if (section.type != _ChartASectionType.dailyTable) ...[
              const SizedBox(height: 14),
              _ADailyTableCard(rows: section.rows),
            ],
          ],
        ],
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
              '방문 구역별 합계',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in metrics.items) ...[
              _ASectorBreakdownRow(
                label: item.sectorName,
                vehicleCount: item.vehicleCount,
                lockedFee: item.totalLockedFee,
              ),
              const SizedBox(height: 8),
            ],
            if (metrics.unassignedVehicleCount > 0)
              _ASectorBreakdownRow(
                label: '미지정',
                vehicleCount: metrics.unassignedVehicleCount,
                lockedFee: metrics.unassignedLockedFee,
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
  final List<_ChartARow> rows;
  final double Function(_ChartARow row) valueOf;
  final String Function(double value) valueText;
  final IconData icon;

  const _DateLineChartCard({
    required this.title,
    required this.subtitle,
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
    final maxY = _chartMaxY(values);
    final pointWidth = 58.0;
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
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(constraints.maxWidth, rows.length * pointWidth + 24);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: width,
                  height: 260,
                  child: hasData
                      ? LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: math.max(rows.length - 1, 0).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY / 4),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 46,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                valueText(value),
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: _axisLabelStep(rows.length).toDouble(),
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if (index < 0 || index >= rows.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Text(
                                  rows[index].dateStr.substring(5),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) {
                            return spots.map((spot) {
                              final index = spot.x.round().clamp(0, rows.length - 1);
                              return LineTooltipItem(
                                '${rows[index].dateStr}\n${valueText(spot.y)}',
                                TextStyle(color: cs.onInverseSurface, fontWeight: FontWeight.w900),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(rows.length, (i) => FlSpot(i.toDouble(), valueOf(rows[i]))),
                          isCurved: true,
                          color: cs.primary,
                          barWidth: 3.2,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: true, color: cs.primary.withOpacity(0.10)),
                        ),
                      ],
                    ),
                  )
                      : Center(
                    child: Text(
                      '표시할 데이터가 없습니다.',
                      style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ADailyTableCard extends StatelessWidget {
  final List<_ChartARow> rows;

  const _ADailyTableCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
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
              Icon(Icons.table_chart_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('날짜별 상세표', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ),
              Text('${rows.length}건', style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
              columns: const [
                DataColumn(label: Text('넘버링')),
                DataColumn(label: Text('날짜')),
                DataColumn(label: Text('출차 대수')),
                DataColumn(label: Text('정산금')),
                DataColumn(label: Text('출차 증감')),
                DataColumn(label: Text('정산금 증감')),
                DataColumn(label: Text('출차 비중')),
                DataColumn(label: Text('정산금 비중')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(row.no.toString())),
                      DataCell(Text(row.dateStr)),
                      DataCell(Text('${_fmt(row.departure)}대')),
                      DataCell(Text('₩${_fmt(row.fee)}')),
                      DataCell(Text(_signed(row.departureDelta, suffix: '대'))),
                      DataCell(Text(_signed(row.feeDelta, prefix: '₩'))),
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

class _ASectionHeaderLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ASectionHeaderLine({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(height: 10),
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _AReportTocOverlay extends StatelessWidget {
  final double width;
  final _ChartAReport report;
  final String selectedId;
  final ValueChanged<String> onTap;
  final VoidCallback onClose;

  const _AReportTocOverlay({
    required this.width,
    required this.report,
    required this.selectedId,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(color: CommonUiTheme.of(context).scrim),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: SizedBox(
                width: width,
                height: double.infinity,
                child: _AReportTocPanel(
                  report: report,
                  selectedId: selectedId,
                  onTap: onTap,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AReportTocPanel extends StatelessWidget {
  final _ChartAReport report;
  final String selectedId;
  final ValueChanged<String> onTap;
  final VoidCallback onClose;

  const _AReportTocPanel({
    required this.report,
    required this.selectedId,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: StatisticsReportDesign.screenTocPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('목차', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('통계 그래프 A', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(
                tooltip: '목차 닫기',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: report.tocItems.length,
              itemBuilder: (context, index) {
                final item = report.tocItems[index];
                final selected = selectedId == item.id;
                return Padding(
                  padding: EdgeInsets.only(left: item.level * 14.0, bottom: 6),
                  child: InkWell(
                    onTap: item.isGroup ? null : () => onTap(item.id),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: selected ? cs.primaryContainer : item.isGroup ? cs.surfaceContainerHighest : CommonUiTheme.of(context).transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? cs.primary.withOpacity(0.45) : cs.outlineVariant.withOpacity(0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.isGroup ? Icons.folder_rounded : Icons.article_rounded,
                            size: 18,
                            color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: item.isGroup || selected ? FontWeight.w900 : FontWeight.w700,
                                color: selected ? cs.onPrimaryContainer : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
            Text('통계 그래프 A에 표시할 데이터가 없습니다.', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
        subtitle: '출차·정산금·전일 대비 증감·기간 내 비중을 함께 정리했습니다.',
        type: _ChartASectionType.dailyTable,
        icon: Icons.table_chart_rounded,
        rows: rows,
        metrics: metrics,
      ),
    ];
    final toc = <_ChartATocItem>[
      const _ChartATocItem(id: 'cover', title: '표지', level: 0),
      const _ChartATocItem(id: 'summary', title: '보고서 요약', level: 0),
      const _ChartATocItem(id: 'a_group', title: '통계 그래프 A 본문', level: 0, isGroup: true),
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
      title: const Text('PDF 메일 발신'),
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
                '수신자는 설정(EmailConfig)에서 관리됩니다.',
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

  factory _DeepLoadRequest.range({
    required DateTime start,
    required DateTime end,
    required String label,
  }) {
    return _DeepLoadRequest._(
      dates: const <DateTime>[],
      start: start,
      end: end,
      label: label,
    );
  }

  bool get isRange => start != null && end != null;
}

String _dateOnly(DateTime dt) => dt.toIso8601String().split('T').first;

String _fmtPdfTime(DateTime? dt) {
  if (dt == null) return '-';
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

int _chartInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
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
