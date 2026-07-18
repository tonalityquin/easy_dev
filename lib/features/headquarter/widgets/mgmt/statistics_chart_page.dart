import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../app/auth/google_auth_v7.dart';
import '../../../../app/config/email_config.dart';
import 'statistics_chart_b_page.dart';
import 'statistics_deep_log_service.dart';
import 'statistics_deep_model.dart';
import 'statistics_report_design.dart';

class StatisticsChartPage extends StatefulWidget {
  const StatisticsChartPage({
    super.key,
    required this.reportDataMap,
    this.division = '',
    this.area = '',
    this.usePromptUi = false,
  });

  final Map<DateTime, Map<String, int>> reportDataMap;
  final String division;
  final String area;
  final bool usePromptUi;

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
    if (widget.usePromptUi) {
      return showPromptOverlayDialog<T>(
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
    if (widget.usePromptUi) {
      return showPromptDateRangePicker(
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
      duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
      curve: PromptUiMotion.enter,
      alignment: 0.02,
    );
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
    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) return;
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      final pdfBytes = await _buildStatsPdfBytes(
        report: report,
        deepReport: _deepReport,
      );
      final filename = '${_safeFileName('통계그래프A_${_dateTag(DateTime.now())}')}.pdf';

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: filename,
        to: toCsv,
        subject: subject,
        body: body,
      );
    } catch (e, st) {
      debugPrint('메일 전송 실패: $e');
      debugPrint('$st');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Uint8List> _buildStatsPdfBytes({
    required _ChartAReport report,
    StatisticsDeepReport? deepReport,
  }) async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final data = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(data);
    } catch (_) {}

    try {
      final data = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(data);
    } catch (_) {
      bold = regular;
    }

    final theme = regular == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(
      base: regular,
      bold: bold ?? regular,
      italic: regular,
      boldItalic: bold ?? regular,
    );

    final doc = pw.Document();
    final createdAt = DateTime.now();

    pw.Widget footer(pw.Context ctx) {
      return StatisticsReportDesign.pdfFooter(
        context: ctx,
        createdAt: createdAt,
        label: '통계 그래프 A 보고서',
      );
    }

    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 38, 34, 38),
        build: (ctx) {
          return pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(28),
            decoration: StatisticsReportDesign.pdfCard(fill: PdfColors.white),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PARKINWORKIN REPORT', style: StatisticsReportDesign.pdfLabel(size: 9)),
                pw.SizedBox(height: 20),
                pw.Text('통계 그래프 A 보고서', style: StatisticsReportDesign.pdfTitle(size: 29)),
                pw.SizedBox(height: 8),
                pw.Text(report.rangeLabel, style: StatisticsReportDesign.pdfBody(size: 13, color: StatisticsReportDesign.pdfMuted)),
                pw.SizedBox(height: 22),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: StatisticsReportDesign.pdfCard(fill: StatisticsReportDesign.pdfAccentSoft),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('날짜별 출차 · 정산금 집계 보고서', style: StatisticsReportDesign.pdfTitle(size: 14)),
                      pw.SizedBox(height: 5),
                      pw.Text('기존 업무 통계 확인 시트의 날짜별 집계 데이터를 A 전용 보고서 로직으로 재구성했습니다.', style: StatisticsReportDesign.pdfBody(size: 10, color: StatisticsReportDesign.pdfMuted)),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Row(
                  children: [
                    StatisticsReportDesign.pdfMetricCard(label: '대상 날짜', value: '${report.metrics.dayCount}일'),
                    pw.SizedBox(width: 8),
                    StatisticsReportDesign.pdfMetricCard(label: '출차 합계', value: '${_fmt(report.metrics.totalDeparture)}대'),
                    pw.SizedBox(width: 8),
                    StatisticsReportDesign.pdfMetricCard(label: '정산금 합계', value: '₩${_fmt(report.metrics.totalFee)}'),
                  ],
                ),
                if (deepReport != null) ...[
                  pw.SizedBox(height: 10),
                  pw.Row(
                    children: [
                      StatisticsReportDesign.pdfMetricCard(label: '심화 차량', value: '${_fmt(deepReport.rows.length)}대'),
                      pw.SizedBox(width: 8),
                      StatisticsReportDesign.pdfMetricCard(label: '심화 날짜', value: '${deepReport.dateStrs.length}일'),
                      pw.SizedBox(width: 8),
                      StatisticsReportDesign.pdfMetricCard(label: '심화 섹션', value: '${deepReport.sections.length}개'),
                    ],
                  ),
                ],
                pw.Spacer(),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: StatisticsReportDesign.pdfCard(fill: StatisticsReportDesign.pdfSoft),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('문서 정보', style: StatisticsReportDesign.pdfTitle(size: 13)),
                      pw.SizedBox(height: 5),
                      pw.Text('생성 시각: ${_fmtCompact(createdAt)}', style: StatisticsReportDesign.pdfBody(size: 10, color: StatisticsReportDesign.pdfMuted)),
                      if (widget.division.trim().isNotEmpty) pw.Text('사업부: ${widget.division.trim()}', style: StatisticsReportDesign.pdfBody(size: 10, color: StatisticsReportDesign.pdfMuted)),
                      if (widget.area.trim().isNotEmpty) pw.Text('지역: ${widget.area.trim()}', style: StatisticsReportDesign.pdfBody(size: 10, color: StatisticsReportDesign.pdfMuted)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final tocRows = <List<String>>[
      ['1', '통계 그래프 A 표지', report.rangeLabel],
      ['2', '목차', '전체 문서 구성'],
      for (int i = 0; i < report.sections.length; i++)
        ['${i + 3}', report.sections[i].title, report.sections[i].subtitle],
    ];

    if (deepReport != null) {
      var n = tocRows.length + 1;
      tocRows.add([n.toString(), deepReport.overallSection.title, deepReport.scopeLabel]);
      n++;
      for (final section in deepReport.dailySections) {
        tocRows.add([n.toString(), section.title, section.subtitle]);
        n++;
      }
      for (final section in deepReport.weekdaySections) {
        tocRows.add([n.toString(), section.title, section.subtitle]);
        n++;
      }
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 34, 28, 34),
        footer: footer,
        build: (ctx) => [
          StatisticsReportDesign.pdfSectionHeader(
            title: '목차',
            subtitle: '통계 그래프 A 보고서 구성',
            eyebrow: 'Table of Contents',
          ),
          pw.SizedBox(height: 14),
          pw.Table.fromTextArray(
            headers: const ['No', '섹션', '내용'],
            data: tocRows,
            border: pw.TableBorder.all(color: StatisticsReportDesign.pdfLine, width: 0.45),
            headerStyle: StatisticsReportDesign.pdfLabel(size: 9),
            cellStyle: StatisticsReportDesign.pdfBody(size: 9),
            headerDecoration: const pw.BoxDecoration(color: StatisticsReportDesign.pdfSoft),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          ),
        ],
      ),
    );

    for (final section in report.sections) {
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 34, 28, 34),
          footer: footer,
          build: (ctx) => [
            StatisticsReportDesign.pdfSectionHeader(
              title: section.title,
              subtitle: section.subtitle,
              eyebrow: 'Statistics Graph A',
            ),
            pw.SizedBox(height: 12),
            _pdfASectionMetrics(section),
            pw.SizedBox(height: 12),
            if (section.type == _ChartASectionType.overview) ...[
              _pdfLineBars(
                title: '날짜별 출차 흐름',
                subtitle: '날짜별 출차 대수',
                rows: section.rows,
                valueOf: (row) => row.departure.toDouble(),
                suffix: '대',
                decimal: false,
              ),
              pw.SizedBox(height: 10),
              _pdfLineBars(
                title: '날짜별 정산금 흐름',
                subtitle: '날짜별 정산금',
                rows: section.rows,
                valueOf: (row) => row.fee.toDouble(),
                suffix: '원',
                decimal: false,
              ),
            ] else if (section.type == _ChartASectionType.departure) ...[
              _pdfLineBars(
                title: '출차 대수 추이',
                subtitle: '전일 대비 증감 포함',
                rows: section.rows,
                valueOf: (row) => row.departure.toDouble(),
                suffix: '대',
                decimal: false,
              ),
            ] else if (section.type == _ChartASectionType.fee) ...[
              _pdfLineBars(
                title: '정산금 추이',
                subtitle: '전일 대비 증감 포함',
                rows: section.rows,
                valueOf: (row) => row.fee.toDouble(),
                suffix: '원',
                decimal: false,
              ),
            ],
            if (section.type == _ChartASectionType.dailyTable) ...[
              _pdfARowsTable(section.rows),
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
      );
    }

    return doc.save();
  }

  pw.Widget _pdfASectionMetrics(_ChartASection section) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            StatisticsReportDesign.pdfMetricCard(label: '대상 날짜', value: '${section.metrics.dayCount}일'),
            pw.SizedBox(width: 8),
            StatisticsReportDesign.pdfMetricCard(label: '출차 합계', value: '${_fmt(section.metrics.totalDeparture)}대'),
            pw.SizedBox(width: 8),
            StatisticsReportDesign.pdfMetricCard(label: '출차 평균', value: '${section.metrics.averageDeparture.toStringAsFixed(1)}대'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            StatisticsReportDesign.pdfMetricCard(label: '정산금 합계', value: '₩${_fmt(section.metrics.totalFee)}'),
            pw.SizedBox(width: 8),
            StatisticsReportDesign.pdfMetricCard(label: '정산금 평균', value: '₩${_fmt(section.metrics.averageFee.round())}'),
            pw.SizedBox(width: 8),
            StatisticsReportDesign.pdfMetricCard(label: '최고 출차', value: section.metrics.maxDeparture == null ? '-' : '${section.metrics.maxDeparture!.dateStr} · ${section.metrics.maxDeparture!.departure}대'),
          ],
        ),
      ],
    );
  }

  pw.Widget _pdfLineBars({
    required String title,
    required String subtitle,
    required List<_ChartARow> rows,
    required double Function(_ChartARow row) valueOf,
    required String suffix,
    required bool decimal,
  }) {
    final safeRows = rows.isEmpty ? <_ChartARow>[] : rows;
    final maxValue = safeRows.fold<double>(0, (p, e) {
      final v = valueOf(e);
      return v > p ? v : p;
    });
    final displayRows = safeRows.length > 28 ? safeRows.sublist(0, 28) : safeRows;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: StatisticsReportDesign.pdfCard(fill: PdfColors.white),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: StatisticsReportDesign.pdfTitle(size: 13)),
          pw.SizedBox(height: 3),
          pw.Text(subtitle, style: StatisticsReportDesign.pdfBody(size: 9, color: StatisticsReportDesign.pdfMuted)),
          pw.SizedBox(height: 10),
          if (displayRows.isEmpty)
            pw.Text('표시할 데이터가 없습니다.', style: StatisticsReportDesign.pdfBody(size: 10, color: StatisticsReportDesign.pdfMuted))
          else
            ...displayRows.map((row) {
              final value = valueOf(row);
              final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
              final width = ratio * 260;
              final text = decimal ? value.toStringAsFixed(1) : _fmt(value.round());
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 56, child: pw.Text(row.dateStr.substring(5), style: StatisticsReportDesign.pdfBody(size: 8, color: StatisticsReportDesign.pdfMuted))),
                    pw.Container(width: width, height: 7, color: StatisticsReportDesign.pdfAccent),
                    pw.SizedBox(width: 6),
                    pw.Text('$text$suffix', style: StatisticsReportDesign.pdfBody(size: 8.5)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  pw.Widget _pdfARowsTable(List<_ChartARow> rows) {
    return pw.Table.fromTextArray(
      headers: const ['No', '날짜', '출차', '정산금', '출차 증감', '정산금 증감', '출차 비중', '정산금 비중'],
      data: [
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
      border: pw.TableBorder.all(color: StatisticsReportDesign.pdfLine, width: 0.35),
      headerStyle: StatisticsReportDesign.pdfLabel(size: 8),
      cellStyle: StatisticsReportDesign.pdfBody(size: 7.8),
      headerDecoration: const pw.BoxDecoration(color: StatisticsReportDesign.pdfSoft),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    );
  }

  void _addDeepReportSectionsToPdf({
    required pw.Document doc,
    required pw.ThemeData theme,
    required pw.Widget Function(pw.Context ctx) footer,
    required StatisticsDeepReport report,
  }) {
    List<pw.Widget> paymentMethodMetricRows(Map<String, int> items) {
      final entries = items.entries.toList();
      final rows = <pw.Widget>[];
      for (int start = 0; start < entries.length; start += 3) {
        final chunk = entries.skip(start).take(3).toList();
        rows.add(pw.SizedBox(height: 8));
        rows.add(
          pw.Row(
            children: [
              for (int i = 0; i < chunk.length; i++) ...[
                if (i > 0) pw.SizedBox(width: 8),
                StatisticsReportDesign.pdfMetricCard(
                  label: '${chunk[i].key} 정산액',
                  value: '₩${_fmt(chunk[i].value)}',
                ),
              ],
              for (int i = chunk.length; i < 3; i++) ...[
                if (i > 0) pw.SizedBox(width: 8),
                pw.Expanded(child: pw.SizedBox()),
              ],
            ],
          ),
        );
      }
      return rows;
    }

    pw.Widget metricRow(StatisticsDeepSection section) {
      return pw.Column(
        children: [
          pw.Row(
            children: [
              StatisticsReportDesign.pdfMetricCard(label: '차량', value: '${section.rows.length}대'),
              pw.SizedBox(width: 8),
              StatisticsReportDesign.pdfMetricCard(label: '대상 날짜', value: '${section.sourceDateCount}일'),
              pw.SizedBox(width: 8),
              StatisticsReportDesign.pdfMetricCard(label: '정산액', value: '₩${_fmt(section.totalFee)}'),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              StatisticsReportDesign.pdfMetricCard(label: '입차 합계', value: '${_fmt(section.metrics.inputTotalSum)}대'),
              pw.SizedBox(width: 8),
              StatisticsReportDesign.pdfMetricCard(label: '출차 합계', value: '${_fmt(section.metrics.outputTotalSum)}대'),
              pw.SizedBox(width: 8),
              StatisticsReportDesign.pdfMetricCard(label: '평균 기준', value: '${section.sourceDateCount}일'),
            ],
          ),
          ...paymentMethodMetricRows(section.feeByPaymentMethod),
        ],
      );
    }

    pw.Widget hourlyBars({
      required String title,
      required String subtitle,
      required List<num> values,
      required bool decimal,
    }) {
      final maxValue = values.fold<double>(0, (p, e) => e.toDouble() > p ? e.toDouble() : p);
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: StatisticsReportDesign.pdfCard(fill: PdfColors.white),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: StatisticsReportDesign.pdfTitle(size: 12)),
            pw.SizedBox(height: 3),
            pw.Text(subtitle, style: StatisticsReportDesign.pdfBody(size: 8.8, color: StatisticsReportDesign.pdfMuted)),
            pw.SizedBox(height: 8),
            ...List.generate(24, (i) {
              final value = values[i].toDouble();
              final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
              final width = ratio * 210;
              final text = decimal ? value.toStringAsFixed(1) : value.toInt().toString();
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3.2),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 30, child: pw.Text('${i.toString().padLeft(2, '0')}시', style: StatisticsReportDesign.pdfBody(size: 7.5, color: StatisticsReportDesign.pdfMuted))),
                    pw.Container(width: width, height: 6.5, color: StatisticsReportDesign.pdfAccent),
                    pw.SizedBox(width: 6),
                    pw.Text('$text대', style: StatisticsReportDesign.pdfBody(size: 7.5)),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    pw.Widget chartSet(StatisticsDeepSection section) {
      final items = <pw.Widget>[
        hourlyBars(
          title: '입차 통산 합계',
          subtitle: '생성 시간 기준',
          values: section.metrics.inputTotalCounts,
          decimal: false,
        ),
        pw.SizedBox(height: 8),
        hourlyBars(
          title: '출차 통산 합계',
          subtitle: '출차 시간 기준',
          values: section.metrics.outputTotalCounts,
          decimal: false,
        ),
      ];

      if (section.showAverageCharts) {
        items.addAll([
          pw.SizedBox(height: 8),
          hourlyBars(
            title: '입차 평균',
            subtitle: '${section.sourceDateCount}일 기준 시간대별 평균',
            values: section.metrics.inputAverageCounts,
            decimal: true,
          ),
          pw.SizedBox(height: 8),
          hourlyBars(
            title: '출차 평균',
            subtitle: '${section.sourceDateCount}일 기준 시간대별 평균',
            values: section.metrics.outputAverageCounts,
            decimal: true,
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
            margin: const pw.EdgeInsets.fromLTRB(22, 34, 22, 34),
            footer: footer,
            build: (ctx) => [
              StatisticsReportDesign.pdfSectionHeader(
                title: '${section.title} 차량 상세표',
                subtitle: '${start + 1} ~ ${start + chunk.length} / ${section.rows.length}',
                eyebrow: 'Deep Statistics Detail',
              ),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: const ['No', '날짜', '차량 번호', '생성 시간', '출차 시간', '정산액', '결제수단'],
                data: [
                  for (final row in chunk)
                    [
                      row.no.toString(),
                      row.dateStr,
                      row.plateNumber,
                      _fmtPdfTime(row.createdAt),
                      _fmtPdfTime(row.departureAt),
                      row.fee == null ? '-' : '₩${_fmt(row.fee!)}',
                      row.paymentMethodLabel,
                    ],
                ],
                border: pw.TableBorder.all(color: StatisticsReportDesign.pdfLine, width: 0.35),
                headerStyle: StatisticsReportDesign.pdfLabel(size: 8),
                cellStyle: StatisticsReportDesign.pdfBody(size: 7.8),
                headerDecoration: const pw.BoxDecoration(color: StatisticsReportDesign.pdfSoft),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              ),
            ],
          ),
        );
      }
    }

    void addSection(StatisticsDeepSection section) {
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(26, 34, 26, 34),
          footer: footer,
          build: (ctx) => [
            StatisticsReportDesign.pdfSectionHeader(
              title: section.title,
              subtitle: section.subtitle,
              eyebrow: 'Statistics Graph B',
            ),
            pw.SizedBox(height: 12),
            metricRow(section),
            pw.SizedBox(height: 12),
            chartSet(section),
          ],
        ),
      );
      addVehicleTables(section);
    }

    addSection(report.overallSection);
    for (final section in report.dailySections) {
      addSection(section);
    }
    for (final section in report.weekdaySections) {
      addSection(section);
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
    try {
      final StatisticsDeepReport deep;
      if (request.isRange) {
        deep = await _deepLogService.loadByDateRange(
          division: division,
          area: area,
          start: request.start!,
          end: request.end!,
        );
      } else {
        deep = await _deepLogService.loadByDates(
          division: division,
          area: area,
          dates: request.dates,
          scopeLabel: request.label,
        );
      }

      if (!mounted) return;
      setState(() {
        _deepReport = deep;
        _deepLabel = deep.scopeLabel;
      });

      final chartPage = StatisticsChartBPage(report: deep);
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final route = widget.usePromptUi
          ? PageRouteBuilder<StatisticsDeepReport>(
              transitionDuration:
                  reduceMotion ? Duration.zero : PromptUiMotion.overlay,
              reverseTransitionDuration:
                  reduceMotion ? Duration.zero : PromptUiMotion.overlay,
              pageBuilder: (_, __, ___) => PromptUiScope(child: chartPage),
              transitionsBuilder: (_, animation, __, child) {
                if (reduceMotion) return child;
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: PromptUiMotion.enter,
                  reverseCurve: PromptUiMotion.exit,
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
    } catch (e) {
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilledButton.icon(
        onPressed: _sending || report.rows.isEmpty ? null : () => _openMailDialogAndSend(report),
        icon: _sending
            ? SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
        )
            : const Icon(Icons.picture_as_pdf_rounded),
        label: Text(_sending ? '발신 중' : 'PDF 발신'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _ChartAReport.from(widget.reportDataMap);
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

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ASectionHeaderLine(icon: section.icon, title: section.title, subtitle: section.subtitle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricTile(label: '대상 날짜', value: '${section.metrics.dayCount}일', icon: Icons.event_rounded),
              _MetricTile(label: '출차 합계', value: '${_fmt(section.metrics.totalDeparture)}대', icon: Icons.logout_rounded),
              _MetricTile(label: '출차 평균', value: '${section.metrics.averageDeparture.toStringAsFixed(1)}대', icon: Icons.functions_rounded),
              _MetricTile(label: '정산금 합계', value: '₩${_fmt(section.metrics.totalFee)}', icon: Icons.payments_rounded),
              _MetricTile(label: '정산금 평균', value: '₩${_fmt(section.metrics.averageFee.round())}', icon: Icons.query_stats_rounded),
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
            child: Container(color: PromptUiTheme.of(context).scrim),
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
                        color: selected ? cs.primaryContainer : item.isGroup ? cs.surfaceContainerHighest : PromptUiTheme.of(context).transparent,
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

class _ChartAReport {
  final List<_ChartARow> rows;
  final String rangeLabel;
  final _ChartAMetrics metrics;
  final List<_ChartASection> sections;
  final List<_ChartATocItem> tocItems;

  const _ChartAReport({
    required this.rows,
    required this.rangeLabel,
    required this.metrics,
    required this.sections,
    required this.tocItems,
  });

  factory _ChartAReport.from(Map<DateTime, Map<String, int>> reportDataMap) {
    final sortedDates = reportDataMap.keys.toList()..sort();
    final rawRows = <_ChartARow>[];
    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final counts = reportDataMap[date] ?? const <String, int>{};
      final departure = counts['vehicleOutput'] ?? counts['출차'] ?? counts['vehicleInput'] ?? counts['입차'] ?? 0;
      final fee = counts['totalLockedFee'] ?? counts['정산금'] ?? 0;
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

  const _ChartASection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.icon,
    required this.rows,
    required this.metrics,
  });
}

enum _ChartASectionType { overview, departure, fee, dailyTable }

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

  const _ChartARow({
    required this.no,
    required this.date,
    required this.departure,
    required this.fee,
    required this.departureDelta,
    required this.feeDelta,
    required this.departureShare,
    required this.feeShare,
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
