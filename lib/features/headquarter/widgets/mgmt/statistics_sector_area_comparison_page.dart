import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../app/config/email_config.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../shared/utils/gmail_pdf_mailer.dart';
import '../../../dashboard/domain/models/end_work_sector_metrics.dart';
import '../../../dashboard/domain/repositories/end_work_report_repository.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import 'statistics_deep_log_service.dart';
import 'statistics_deep_model.dart';
import 'statistics_expandable_chart.dart';
import 'statistics_report_design.dart';

class StatisticsSectorAreaComparisonPage extends StatefulWidget {
  final String division;
  final List<String> areas;
  final List<DateTime> dates;
  final bool useCommonUi;
  final bool embedded;

  const StatisticsSectorAreaComparisonPage({
    super.key,
    required this.division,
    required this.areas,
    required this.dates,
    required this.useCommonUi,
    this.embedded = false,
  });

  @override
  State<StatisticsSectorAreaComparisonPage> createState() =>
      _StatisticsSectorAreaComparisonPageState();
}

class _StatisticsSectorAreaComparisonPageState
    extends State<StatisticsSectorAreaComparisonPage> {
  final StatisticsDeepLogService _service = StatisticsDeepLogService();
  final EndWorkReportRepository _reportRepository = EndWorkReportRepository();
  late Set<String> _selectedAreas;
  bool _loading = false;
  bool _sending = false;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  StatisticsSectorAreaComparisonReport? _report;

  @override
  void initState() {
    super.initState();
    _selectedAreas = widget.areas.take(3).toSet();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.layout;
    final content = SafeArea(
      top: !widget.embedded,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 4 : 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.embedded) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Area 방문 구역 비교',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '선택한 Area의 원본 로그를 명시적으로 불러와 방문 구역을 비교합니다.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _sending || _report == null || _report!.results.isEmpty
                        ? null
                        : _openMailDialog,
                    icon: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      child: _sending
                          ? const SizedBox(
                              key: ValueKey<String>('comparison_pdf_sending_embedded'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              key: ValueKey<String>('comparison_pdf_ready_embedded'),
                            ),
                    ),
                    tooltip: '비교 PDF 발신',
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            _AreaSelectionPanel(
              areas: widget.areas,
              selectedAreas: _selectedAreas,
              loading: _loading,
              onChanged: _toggleArea,
              onLoad: _load,
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: duration,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              child: _loading
                  ? const _LoadingPanel(key: ValueKey<String>('loading'))
                  : _report == null
                      ? const _EmptyPanel(key: ValueKey<String>('empty'))
                      : _AreaComparisonView(
                          key: ValueKey<String>(
                            _report!.results.map((e) => e.area).join('|'),
                          ),
                          report: _report!,
                        ),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return ColoredBox(color: cs.surface, child: content);
    }
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Area 방문 구역 비교'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          IconButton(
            onPressed: _sending || _report == null || _report!.results.isEmpty
                ? null
                : _openMailDialog,
            icon: AnimatedSwitcher(
              duration: duration,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              child: _sending
                  ? const SizedBox(
                      key: ValueKey<String>('comparison_pdf_sending'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      key: ValueKey<String>('comparison_pdf_ready'),
                    ),
            ),
            tooltip: '비교 PDF 발신',
          ),
        ],
      ),
      body: content,
    );
  }

  Future<void> _openMailDialog() async {
    final report = _report;
    if (report == null || report.results.isEmpty) return;
    final defaultSubject = _subjectController.text.trim().isEmpty
        ? 'Area 방문 구역 비교 리포트 (${_comparisonRangeLabel(report.dates)})'
        : _subjectController.text.trim();
    final subjectController = TextEditingController(text: defaultSubject);
    final bodyController = TextEditingController(text: _bodyController.text);
    final draft = await showDialog<_AreaComparisonMailDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Area 비교 PDF 발신'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: '본문'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final subject = subjectController.text.trim();
              if (subject.isEmpty) return;
              Navigator.of(dialogContext).pop(
                _AreaComparisonMailDraft(
                  subject: subject,
                  body: bodyController.text.trim(),
                ),
              );
            },
            child: const Text('발신'),
          ),
        ],
      ),
    );
    subjectController.dispose();
    bodyController.dispose();
    if (draft == null) return;
    _subjectController.text = draft.subject;
    _bodyController.text = draft.body;
    await _sendComparisonPdf(report, draft);
  }

  Future<void> _sendComparisonPdf(
    StatisticsSectorAreaComparisonReport report,
    _AreaComparisonMailDraft draft,
  ) async {
    if (_sending) return;
    setState(() => _sending = true);
    DeveloperOperationTrace? trace;
    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: 'Area 방문 구역 비교 PDF',
        initialMessage: 'Area 비교 PDF를 생성하고 Gmail 첨부파일을 준비합니다.',
        useCommonUi: widget.useCommonUi,
        developerModeMessage:
            '개발자 모드 ON: 비교 PDF 생성과 Gmail 발신 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 비교 PDF 생성과 Gmail 발신 로그를 콘솔에 기록합니다.',
      );
      for (final result in report.results) {
        trace.log(
          'area=${result.area} vehicles=${result.sectorReport.totalVehicleCount} '
          'input=${result.sectorReport.totalInputCount} '
          'fee=${result.sectorReport.totalLockedFee} '
          'integrity=${result.sectorReport.integrity.isValid} '
          'sourceFields=${result.sectorReport.sourceFieldAvailable} '
          'complete=${result.sectorReport.sourceFieldComplete} '
          'analyzable=${result.sectorReport.analyzableVehicleCount} '
          'unavailable=${result.sectorReport.unavailableVehicleCount}',
          progress: .12,
        );
        if (!result.sectorReport.integrity.isValid) {
          await trace.fail(
            '${result.area} Area의 Sector 데이터 무결성을 확인해 주세요.',
          );
          return;
        }
      }
      final config = await EmailConfig.load();
      if (!EmailConfig.isValidToList(config.to)) {
        await trace.fail('PDF 수신자 설정이 올바르지 않습니다.');
        return;
      }
      if (!mounted) return;
      final pdfPalette = StatisticsReportDesign.pdfPalette(context);
      trace.log(
        'pdf=build areas=${report.results.length} '
        'design=app-theme-v4 ${pdfPalette.debugLabel}',
        progress: .32,
      );
      final pdfBytes = await _buildComparisonPdf(
        report,
        pdfPalette,
        trace: trace,
      );
      final filename =
          'Area_Sector_Comparison_${_comparisonRangeLabel(report.dates).replaceAll(' ', '_').replaceAll('~', '-')}.pdf';
      trace.log(
        'pdf=ready bytes=${pdfBytes.length} filename=$filename',
        progress: .72,
      );
      await GmailPdfMailer.sendPdf(
        pdfBytes: pdfBytes,
        filename: filename,
        to: config.to,
        subject: draft.subject,
        body: draft.body,
      );
      trace.log('gmail=sent recipients=${config.to}', progress: .94);
      await trace.succeed('Area 방문 구역 비교 PDF 발신이 완료되었습니다.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Area 비교 PDF를 발신했습니다.')),
        );
      }
    } catch (error, stackTrace) {
      if (trace != null) {
        await trace.fail(
          'Area 비교 PDF 발신에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      } else {
        debugPrint('[STAT_AREA_COMPARE] send failed error=$error');
        debugPrint('$stackTrace');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Area 비교 PDF 발신 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Uint8List> _buildComparisonPdf(
    StatisticsSectorAreaComparisonReport report,
    StatisticsPdfPalette palette, {
    DeveloperOperationTrace? trace,
  }) async {
    pw.Font? regular;
    pw.Font? bold;
    try {
      regular = pw.Font.ttf(
        await rootBundle.load(
          'assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf',
        ),
      );
      bold = pw.Font.ttf(
        await rootBundle.load(
          'assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf',
        ),
      );
    } catch (error) {
      _logAreaDebug(
        trace,
        '[STAT_AREA_COMPARE] pdf font fallback error=$error',
        progress: .36,
      );
    }
    final theme = regular == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(
            base: regular,
            bold: bold ?? regular,
          );
    final design = StatisticsReportDesign.pdf(palette);
    final createdAt = DateTime.now();
    final rangeLabel = _comparisonRangeLabel(report.dates);
    final totalVehicles = report.results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.totalVehicleCount,
    );
    final totalAnalyzable = report.results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.analyzableVehicleCount,
    );
    final totalUnavailable = report.results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.unavailableVehicleCount,
    );
    final totalInput = report.results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.totalInputCount,
    );
    final totalFee = report.results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.totalLockedFee,
    );
    final totalSectorCount = report.results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.sectorCount,
    );
    final doc = pw.Document();
    _logAreaDebug(
      trace,
      '[STAT_AREA_COMPARE] pdf design=app-theme-v4 ${palette.debugLabel} '
      'areas=${report.results.length} vehicles=$totalVehicles input=$totalInput fee=$totalFee '
      'metricCard=uniform62 radius7 accent=leftBorder metaSlot=reserved',
      progress: .42,
    );

    pw.Widget footer(pw.Context context) {
      return design.footer(
        context: context,
        createdAt: createdAt,
        labelText: 'PARKINWORKIN · Area 방문 구역 비교',
      );
    }

    pw.Widget header(pw.Context context) {
      return design.runningHeader(
        reportTitle: 'Area 방문 구역 비교',
        area: report.division,
        rangeLabel: rangeLabel,
      );
    }

    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => design.cover(
          reportCode: 'AREA COMPARISON',
          titleText: 'Area 방문 구역 비교 보고서',
          subtitle: '여러 Area의 완료 차량·입차·Sector·정산 결과를 동일한 기준으로 비교합니다.',
          description:
              '앱의 Area 비교 화면과 동일한 공통 Sector 모델을 사용하며, 정상·미지정·확인 필요 상태와 무결성 결과를 함께 제공합니다.',
          createdAt: createdAt,
          tags: [
            StatisticsPdfTagData(
              label: report.division,
              tone: StatisticsPdfTone.neutral,
            ),
            StatisticsPdfTagData(
              label: rangeLabel,
              tone: StatisticsPdfTone.primary,
            ),
            StatisticsPdfTagData(
              label: '${report.results.length}개 Area',
              tone: StatisticsPdfTone.secondary,
            ),
            if (report.failures.isNotEmpty)
              StatisticsPdfTagData(
                label: '조회 실패 ${report.failures.length}개',
                tone: StatisticsPdfTone.warning,
              ),
          ],
          metrics: [
            StatisticsPdfMetricData(
              label: '비교 Area',
              value: '${report.results.length}개',
              tone: StatisticsPdfTone.primary,
            ),
            StatisticsPdfMetricData(
              label: '완료 차량',
              value: '$totalVehicles대',
              tone: StatisticsPdfTone.success,
            ),
            StatisticsPdfMetricData(
              label: '분석 가능',
              value: '$totalAnalyzable대',
              tone: StatisticsPdfTone.primary,
            ),
            StatisticsPdfMetricData(
              label: '원천 없음',
              value: '$totalUnavailable대',
              tone: totalUnavailable == 0
                  ? StatisticsPdfTone.success
                  : StatisticsPdfTone.warning,
            ),
            StatisticsPdfMetricData(
              label: '입차 합계',
              value: '$totalInput대',
              tone: StatisticsPdfTone.input,
            ),
            StatisticsPdfMetricData(
              label: 'Sector 합계',
              value: '$totalSectorCount개',
              tone: StatisticsPdfTone.secondary,
            ),
            StatisticsPdfMetricData(
              label: '잠금 금액',
              value: '₩${_fmt(totalFee)}',
              tone: StatisticsPdfTone.fee,
            ),
            StatisticsPdfMetricData(
              label: '조회 실패',
              value: '${report.failures.length}개',
              tone: report.failures.isEmpty
                  ? StatisticsPdfTone.success
                  : StatisticsPdfTone.warning,
            ),
          ],
          division: report.division,
          rangeLabel: rangeLabel,
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: 'Area 비교 요약',
            subtitle: '$rangeLabel · ${report.results.length}개 Area',
            eyebrow: 'AREA EXECUTIVE SUMMARY',
            sectionNumber: 'A01',
            tone: StatisticsPdfTone.primary,
          ),
          pw.SizedBox(height: 10),
          design.metricGrid([
            StatisticsPdfMetricData(
              label: '완료 차량',
              value: '$totalVehicles대',
              tone: StatisticsPdfTone.success,
            ),
            StatisticsPdfMetricData(
              label: '입차 합계',
              value: '$totalInput대',
              tone: StatisticsPdfTone.input,
            ),
            StatisticsPdfMetricData(
              label: '잠금 금액',
              value: '₩${_fmt(totalFee)}',
              tone: StatisticsPdfTone.fee,
            ),
          ]),
          pw.SizedBox(height: 10),
          _comparisonPdfAreaSummary(report.results, design),
          if (totalUnavailable > 0) ...[
            pw.SizedBox(height: 12),
            design.notice(
              titleText: '일부 차량의 방문 구역 원천 데이터 제외',
              message:
                  '전체 $totalVehicles대 중 $totalAnalyzable대만 Area별 Sector 비교에 포함했습니다.',
              tone: StatisticsPdfTone.warning,
              details: <String>[
                '원천 필드 없음 $totalUnavailable대',
                '제외 차량은 Area 완료 차량 합계에는 포함되지만 Sector별 입차·금액 차트에서는 제외됩니다.',
              ],
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _comparisonPdfBars(
                  design: design,
                  title: 'Area별 Sector 입차 합계',
                  subtitle: 'Area 내부 Sector 그룹의 입차 수 합계',
                  results: report.results,
                  value: (result) => result.sectorReport.totalInputCount,
                  label: (result) =>
                      '${result.sectorReport.totalInputCount}대',
                  tone: StatisticsPdfTone.input,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _comparisonPdfBars(
                  design: design,
                  title: 'Area별 Sector 잠금 금액',
                  subtitle: 'Area 내부 Sector 그룹의 잠금 금액 합계',
                  results: report.results,
                  value: (result) => result.sectorReport.totalLockedFee,
                  label: (result) =>
                      '₩${_fmt(result.sectorReport.totalLockedFee)}',
                  tone: StatisticsPdfTone.fee,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: 'Area·Sector 상세 비교',
            subtitle: '각 Area의 방문 구역별 차량·입차·출차·잠금 금액을 비교합니다.',
            eyebrow: 'AREA SECTOR DETAIL',
            sectionNumber: 'A02',
            tone: StatisticsPdfTone.secondary,
          ),
          pw.SizedBox(height: 10),
          _comparisonPdfSectorTable(report.results, design),
          if (report.failures.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            design.notice(
              titleText: '조회 실패 Area',
              message: '${report.failures.length}개 Area의 조회 결과를 문서에서 제외했습니다.',
              tone: StatisticsPdfTone.warning,
              details: [
                for (final failure in report.failures)
                  '${failure.area}: ${failure.message}',
              ],
            ),
          ],
        ],
      ),
    );

    final bytes = await doc.save();
    _logAreaDebug(
      trace,
      '[STAT_AREA_COMPARE] pdf complete bytes=${bytes.length} style=app-theme-v4',
      progress: .68,
    );
    return bytes;
  }

  pw.Widget _comparisonPdfAreaSummary(
    List<StatisticsSectorAreaResult> results,
    StatisticsPdfDesign design,
  ) {
    return design.dataTable(
      headers: const [
        'Area',
        '완료 차량',
        '분석 가능',
        '원천 없음',
        '입차',
        'Sector',
        '미지정',
        '확인 필요',
        '잠금 금액',
        '무결성',
      ],
      rows: [
        for (final result in results)
          [
            result.area,
            '${result.sectorReport.totalVehicleCount}대',
            '${result.sectorReport.analyzableVehicleCount}대',
            '${result.sectorReport.unavailableVehicleCount}대',
            '${result.sectorReport.totalInputCount}대',
            '${result.sectorReport.sectorCount}개',
            '${result.sectorReport.unassignedVehicleCount}대',
            '${result.sectorReport.invalidVehicleCount}대',
            '₩${_fmt(result.sectorReport.totalLockedFee)}',
            result.sectorReport.integrity.isValid ? '정상' : '확인',
          ],
      ],
      numericColumns: const <int>{1, 2, 3, 4, 5, 6, 7},
      tone: StatisticsPdfTone.primary,
      fontSize: 7.2,
      headerFontSize: 7.3,
      horizontalPadding: 3.5,
      verticalPadding: 4.5,
    );
  }

  pw.Widget _comparisonPdfBars({
    required StatisticsPdfDesign design,
    required String title,
    required String subtitle,
    required List<StatisticsSectorAreaResult> results,
    required int Function(StatisticsSectorAreaResult result) value,
    required String Function(StatisticsSectorAreaResult result) label,
    required StatisticsPdfTone tone,
  }) {
    final maxValue = results.fold<int>(0, (previous, result) {
      final current = value(result);
      return current > previous ? current : previous;
    });
    final accent = design.toneColor(tone);
    final track = design.toneSoft(tone);
    return design.chartCard(
      titleText: title,
      subtitle: subtitle,
      badge: '${results.length}개 Area',
      tone: tone,
      child: pw.Column(
        children: [
          for (final result in results)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 82,
                    child: pw.Text(
                      result.area,
                      maxLines: 2,
                      style: design.body(size: 7.5),
                    ),
                  ),
                  pw.Container(
                    width: 210,
                    height: 9,
                    alignment: pw.Alignment.centerLeft,
                    decoration: pw.BoxDecoration(
                      color: track,
                      borderRadius: pw.BorderRadius.circular(4.5),
                    ),
                    child: pw.Container(
                      width: maxValue <= 0
                          ? 0
                          : value(result) / maxValue * 210,
                      height: 9,
                      decoration: pw.BoxDecoration(
                        color: accent,
                        borderRadius: pw.BorderRadius.circular(4.5),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Text(
                      label(result),
                      textAlign: pw.TextAlign.right,
                      style: design.body(size: 7.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _comparisonPdfSectorTable(
    List<StatisticsSectorAreaResult> results,
    StatisticsPdfDesign design,
  ) {
    return design.dataTable(
      headers: const [
        'Area',
        '방문 구역',
        '상태',
        '차량',
        '입차',
        '출차',
        '잠금 금액',
      ],
      rows: [
        for (final result in results)
          for (final group in result.sectorReport.groups)
            [
              result.area,
              group.sectorLabel,
              group.state == StatisticsSectorState.assigned
                  ? '정상'
                  : group.state == StatisticsSectorState.unassigned
                      ? '미지정'
                      : '확인 필요',
              '${group.vehicleCount}대',
              '${group.inputCount}대',
              '${group.outputCount}대',
              '₩${_fmt(group.totalLockedFee)}',
            ],
      ],
      numericColumns: const <int>{3, 4, 5, 6},
      tone: StatisticsPdfTone.secondary,
      fontSize: 7,
      headerFontSize: 7.1,
      horizontalPadding: 3.3,
      verticalPadding: 4.1,
    );
  }

  void _toggleArea(String area, bool selected) {
    final next = <String>{..._selectedAreas};
    if (selected) {
      next.add(area);
    } else {
      next.remove(area);
    }
    setState(() => _selectedAreas = next);
    debugPrint('[STAT_AREA_COMPARE] selection=${next.join(',')}');
  }

  _AreaHistorySourceSelection _resolveHistorySource({
    required String area,
    required Map<String, Map<String, dynamic>> areaDays,
  }) {
    final requestedDates = widget.dates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    final selectedDates = <DateTime>[];
    final gcsLogUrls = <String>{};
    final sectorMetrics = <EndWorkSectorMetrics>[];
    var reportDays = 0;
    var detailedEntries = 0;
    var excludedEntries = 0;
    var firstEntries = 0;
    var unverifiedDetailedEntries = 0;
    var legacyDetailedEntries = 0;
    var sectorEntries = 0;

    for (final date in requestedDates) {
      final dateStr = _areaDateOnly(date);
      final day = areaDays[dateStr];
      if (day == null) continue;
      reportDays++;
      final urls = _areaStringList(day['_historyLogsUrls']);
      if (urls.isNotEmpty) {
        selectedDates.add(date);
        gcsLogUrls.addAll(urls);
      }
      detailedEntries += _areaInt(day['_historyDetailedEntryCount']);
      excludedEntries += _areaInt(day['_historyExcludedEntryCount']);
      firstEntries += _areaInt(day['_historyFirstEntryCount']);
      unverifiedDetailedEntries +=
          _areaInt(day['_historyUnverifiedDetailedEntryCount']);
      legacyDetailedEntries += _areaInt(day['_historyLegacyDetailedEntryCount']);
      sectorEntries += _areaInt(day['_historySectorEntryCount']);
      final metrics = _areaMap(day['metrics']);
      final sector = EndWorkSectorMetrics.fromDynamic(metrics?['sector']);
      if (sector != null && sector.enabled && urls.isNotEmpty) {
        sectorMetrics.add(sector);
      }
    }

    final mergedSector = EndWorkSectorMetrics.merge(sectorMetrics);
    return _AreaHistorySourceSelection(
      area: area,
      requestedDateCount: requestedDates.length,
      reportDayCount: reportDays,
      dates: List<DateTime>.unmodifiable(selectedDates),
      gcsLogUrls: List<String>.unmodifiable(gcsLogUrls.toList()..sort()),
      expectedSector: mergedSector.enabled ? mergedSector : null,
      detailedEntryCount: detailedEntries,
      excludedEntryCount: excludedEntries,
      firstEntryCount: firstEntries,
      unverifiedDetailedEntryCount: unverifiedDetailedEntries,
      legacyDetailedEntryCount: legacyDetailedEntries,
      sectorEntryCount: sectorEntries,
    );
  }

  bool _validateAreaSectorCross({
    required String area,
    required EndWorkSectorMetrics expected,
    required StatisticsSectorReport actual,
    required DeveloperOperationTrace trace,
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
      expectedNamesById.putIfAbsent(id, () => <String>{}).add(item.sectorName.trim());
    }
    final actualAssignedGroups = actual.groups
        .where((group) => group.state == StatisticsSectorState.assigned)
        .toList(growable: false);
    final actualVehicleById = <String, int>{};
    final actualFeeById = <String, int>{};
    for (final group in actualAssignedGroups) {
      final id = group.sectorId?.trim() ?? '';
      if (id.isEmpty) continue;
      actualVehicleById[id] = (actualVehicleById[id] ?? 0) + group.vehicleCount;
      actualFeeById[id] = (actualFeeById[id] ?? 0) + group.totalLockedFee;
    }

    final expectedIdentityConflicts = expectedNamesById.entries
        .where((entry) => entry.value.where((name) => name.isNotEmpty).length > 1)
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final sectorIdentityValid = expectedIdentityConflicts.isEmpty &&
        actual.integrity.sectorIdentityConflictCount == 0;
    final assignedMatched =
        actual.assignedVehicleCount == expected.assignedVehicleCount;
    final unassignedMatched =
        actual.unassignedVehicleCount == expected.unassignedVehicleCount;
    final invalidMatched =
        actual.invalidVehicleCount == expected.invalidSectorVehicleCount;
    final feeMatched = expected.legacyFeeClassification ||
        actual.totalLockedFee == expected.totalLockedFee.round();
    var groupsMatched = true;
    final allIds = <String>{
      ...expectedVehicleById.keys,
      ...actualVehicleById.keys,
    }.toList()
      ..sort();
    for (final id in allIds) {
      final vehicleMatched =
          (actualVehicleById[id] ?? 0) == (expectedVehicleById[id] ?? 0);
      final groupFeeMatched = expected.legacyFeeClassification ||
          (actualFeeById[id] ?? 0) == (expectedFeeById[id] ?? 0);
      if (!vehicleMatched || !groupFeeMatched) groupsMatched = false;
      trace.log(
        'area=$area cross sectorId=$id '
        'vehicles=${actualVehicleById[id] ?? 0}/${expectedVehicleById[id] ?? 0} '
        'fee=${actualFeeById[id] ?? 0}/${expectedFeeById[id] ?? 0} '
        'matched=${vehicleMatched && groupFeeMatched}',
      );
    }
    final expectedInternal = expected.isInternallyConsistent;
    trace.log('area=$area cross expectedInternal=$expectedInternal');
    trace.log(
      'area=$area cross identityValid=$sectorIdentityValid '
      'expectedConflicts=${expectedIdentityConflicts.join(',')} '
      'actualConflicts=${actual.integrity.sectorIdentityConflictCount}',
    );
    trace.log(
      'area=$area cross assigned=${actual.assignedVehicleCount}/${expected.assignedVehicleCount} matched=$assignedMatched',
    );
    trace.log(
      'area=$area cross unassigned=${actual.unassignedVehicleCount}/${expected.unassignedVehicleCount} matched=$unassignedMatched',
    );
    trace.log(
      'area=$area cross invalid=${actual.invalidVehicleCount}/${expected.invalidSectorVehicleCount} matched=$invalidMatched',
    );
    trace.log(
      'area=$area cross fee=${actual.totalLockedFee}/${expected.totalLockedFee.round()} matched=$feeMatched legacy=${expected.legacyFeeClassification}',
    );
    return expectedInternal &&
        sectorIdentityValid &&
        assignedMatched &&
        unassignedMatched &&
        invalidMatched &&
        feeMatched &&
        groupsMatched;
  }

  Future<void> _load() async {
    if (_loading || _selectedAreas.length < 2) return;
    setState(() => _loading = true);
    DeveloperOperationTrace? trace;
    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: 'Area 방문 구역 비교',
        initialMessage: '선택한 Area의 검증된 상세 업무종료 로그를 비교하고 있습니다.',
        useCommonUi: widget.useCommonUi,
        developerModeMessage:
            '개발자 모드 ON: Firestore history·연결 GCS·무결성 로그를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: Area별 검증된 history/GCS 조회 로그를 콘솔에 기록합니다.',
      );
      final areas = _selectedAreas.toList()..sort();
      trace.log(
        'division=${widget.division} areas=${areas.join(',')} dates=${widget.dates.length} source=verifiedDetailedGcsHistory',
        progress: .06,
      );
      final monthKeys = widget.dates
          .map((date) => '${date.year}${date.month.toString().padLeft(2, '0')}')
          .toSet()
          .toList()
        ..sort();
      trace.log(
        'firestore direct source months=${monthKeys.join(',')}',
        progress: .12,
      );
      final selections = <String, _AreaHistorySourceSelection>{};
      for (final area in areas) {
        final areaDays = await _reportRepository.loadAreaMonths(
          division: widget.division.trim(),
          area: area,
          monthKeys: monthKeys,
        );
        trace.log(
          'area=$area firestoreMonthReads=${monthKeys.length} loadedDays=${areaDays.length}',
          progress: .14,
        );
        final selection = _resolveHistorySource(
          area: area,
          areaDays: areaDays,
        );
        selections[area] = selection;
        trace.log(
          'area=$area requestedDays=${selection.requestedDateCount} '
          'reportDays=${selection.reportDayCount} '
          'linkedDays=${selection.dates.length} '
          'detailedGcs=${selection.detailedEntryCount} '
          'excluded=${selection.excludedEntryCount} '
          'first=${selection.firstEntryCount} '
          'unverifiedDetailed=${selection.unverifiedDetailedEntryCount} '
          'legacyDetailed=${selection.legacyDetailedEntryCount} '
          'sectorEntries=${selection.sectorEntryCount} '
          'linkedLogs=${selection.gcsLogUrls.length}',
          progress: .16,
        );
      }

      final results = <StatisticsSectorAreaResult>[];
      final failures = <StatisticsSectorAreaFailure>[];
      for (int start = 0; start < areas.length; start += 3) {
        final batch = areas.skip(start).take(3).toList();
        final batchResults = await Future.wait(
          batch.map((area) async {
            final selection = selections[area]!;
            if (selection.gcsLogUrls.isEmpty || selection.dates.isEmpty) {
              return StatisticsSectorAreaFailure(
                area: area,
                message: '검증된 상세 업무종료 history에 연결된 GCS 로그가 없습니다.',
              );
            }
            if (selection.expectedSector == null) {
              return StatisticsSectorAreaFailure(
                area: area,
                message: '검증된 상세 업무종료 history에 Sector 집계가 없습니다.',
              );
            }
            try {
              final deep = await _service.loadByDates(
                division: widget.division,
                area: area,
                dates: selection.dates,
                scopeLabel: _comparisonRangeLabel(widget.dates),
                sectorEnabled: true,
                gcsLogUrls: selection.gcsLogUrls,
                onLog: (message) {
                  trace?.log('area=$area $message', progress: .34);
                },
              );
              final sector = deep.sectorReport;
              if (sector == null) {
                return StatisticsSectorAreaFailure(
                  area: area,
                  message: '방문 구역 보고서를 생성하지 못했습니다.',
                );
              }
              if (!sector.integrity.isValid) {
                return StatisticsSectorAreaFailure(
                  area: area,
                  message: 'GCS 상세 로그 Sector 무결성 검증에 실패했습니다.',
                );
              }
              if (!sector.sourceFieldComplete) {
                return StatisticsSectorAreaFailure(
                  area: area,
                  message: 'GCS 상세 로그에 Sector 원천 필드가 없는 차량이 있습니다.',
                );
              }
              final activeTrace = trace;
              if (activeTrace == null) {
                return StatisticsSectorAreaFailure(
                  area: area,
                  message: '통계 검증 로그를 초기화하지 못했습니다.',
                );
              }
              activeTrace.log(
                'area=$area cross source expected=firestoreVerifiedDetailedGcsHistoryAggregate actual=gcsVerifiedHistoryLinkedCsvMerge',
                progress: .7,
              );
              final crossValid = _validateAreaSectorCross(
                area: area,
                expected: selection.expectedSector!,
                actual: sector,
                trace: activeTrace,
              );
              if (!crossValid) {
                return StatisticsSectorAreaFailure(
                  area: area,
                  message: 'Firestore 상세 history와 연결 GCS Sector 합계가 일치하지 않습니다.',
                );
              }
              return StatisticsSectorAreaResult(
                area: area,
                deepReport: deep,
                sectorReport: sector,
              );
            } catch (e) {
              return StatisticsSectorAreaFailure(
                area: area,
                message: e.toString(),
              );
            }
          }),
        );
        for (final result in batchResults) {
          if (result is StatisticsSectorAreaResult) {
            results.add(result);
            trace.log(
              'area=${result.area} vehicles=${result.sectorReport.totalVehicleCount} '
              'input=${result.sectorReport.totalInputCount} '
              'sectors=${result.sectorReport.sectorCount} '
              'analyzable=${result.sectorReport.analyzableVehicleCount} '
              'unavailable=${result.sectorReport.unavailableVehicleCount} '
              'integrity=${result.sectorReport.integrity.isValid}',
              progress: math.min(.9, .24 + results.length / areas.length * .62).toDouble(),
            );
          } else if (result is StatisticsSectorAreaFailure) {
            failures.add(result);
            trace.log('area=${result.area} failure=${result.message}');
          }
        }
      }
      results.sort((a, b) => a.area.compareTo(b.area));
      failures.sort((a, b) => a.area.compareTo(b.area));
      final report = StatisticsSectorAreaComparisonReport(
        division: widget.division,
        dates: widget.dates,
        results: results,
        failures: failures,
      );
      if (!mounted) return;
      setState(() => _report = report);
      await trace.succeed(
        'Area 비교 완료: 성공 ${results.length}개, 실패 ${failures.length}개',
      );
    } catch (e, st) {
      if (trace != null) {
        await trace.fail(
          'Area 방문 구역 비교에 실패했습니다.',
          error: e,
          stackTrace: st,
        );
      } else {
        debugPrint('[STAT_AREA_COMPARE] load failed error=$e');
        debugPrint('$st');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

}

Map<String, dynamic>? _areaMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

int _areaInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
}

List<String> _areaStringList(Object? value) {
  if (value is! List) return const <String>[];
  final result = value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return result;
}

String _areaDateOnly(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _AreaHistorySourceSelection {
  final String area;
  final int requestedDateCount;
  final int reportDayCount;
  final List<DateTime> dates;
  final List<String> gcsLogUrls;
  final EndWorkSectorMetrics? expectedSector;
  final int detailedEntryCount;
  final int excludedEntryCount;
  final int firstEntryCount;
  final int unverifiedDetailedEntryCount;
  final int legacyDetailedEntryCount;
  final int sectorEntryCount;

  const _AreaHistorySourceSelection({
    required this.area,
    required this.requestedDateCount,
    required this.reportDayCount,
    required this.dates,
    required this.gcsLogUrls,
    required this.expectedSector,
    required this.detailedEntryCount,
    required this.excludedEntryCount,
    required this.firstEntryCount,
    required this.unverifiedDetailedEntryCount,
    required this.legacyDetailedEntryCount,
    required this.sectorEntryCount,
  });
}

class _AreaComparisonMailDraft {
  final String subject;
  final String body;

  const _AreaComparisonMailDraft({
    required this.subject,
    required this.body,
  });
}

void _logAreaDebug(
  DeveloperOperationTrace? trace,
  String message, {
  double? progress,
}) {
  if (trace != null) {
    trace.log(message, progress: progress);
    return;
  }
  debugPrint(message);
}

String _comparisonRangeLabel(List<DateTime> dates) {
  if (dates.isEmpty) return '-';
  final sorted = dates
      .map((date) => DateTime(date.year, date.month, date.day))
      .toSet()
      .toList()
    ..sort((a, b) => a.compareTo(b));
  String format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  if (sorted.length == 1) return format(sorted.first);
  return '${format(sorted.first)} ~ ${format(sorted.last)}';
}

class StatisticsSectorAreaComparisonReport {
  final String division;
  final List<DateTime> dates;
  final List<StatisticsSectorAreaResult> results;
  final List<StatisticsSectorAreaFailure> failures;

  const StatisticsSectorAreaComparisonReport({
    required this.division,
    required this.dates,
    required this.results,
    required this.failures,
  });
}

class StatisticsSectorAreaResult {
  final String area;
  final StatisticsDeepReport deepReport;
  final StatisticsSectorReport sectorReport;

  const StatisticsSectorAreaResult({
    required this.area,
    required this.deepReport,
    required this.sectorReport,
  });
}

class StatisticsSectorAreaFailure {
  final String area;
  final String message;

  const StatisticsSectorAreaFailure({
    required this.area,
    required this.message,
  });
}

class _AreaSelectionPanel extends StatelessWidget {
  final List<String> areas;
  final Set<String> selectedAreas;
  final bool loading;
  final void Function(String area, bool selected) onChanged;
  final VoidCallback onLoad;

  const _AreaSelectionPanel({
    required this.areas,
    required this.selectedAreas,
    required this.loading,
    required this.onChanged,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: StatisticsReportDesign.screenPanel(context, emphasized: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '비교할 Area 선택',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '동일한 날짜 범위의 Sector별 완료 차량과 정산 정보를 비교합니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in areas)
                FilterChip(
                  label: Text(area),
                  selected: selectedAreas.contains(area),
                  onSelected: loading
                      ? null
                      : (selected) => onChanged(area, selected),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: loading || selectedAreas.length < 2 ? null : onLoad,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.compare_arrows_rounded),
            label: Text(
              loading ? '비교 중' : '${selectedAreas.length}개 Area 비교',
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaComparisonView extends StatelessWidget {
  final StatisticsSectorAreaComparisonReport report;

  const _AreaComparisonView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report.results.any((result) => result.sectorReport.hasUnavailableData)) ...[
          _AreaSourceCoveragePanel(results: report.results),
          const SizedBox(height: 12),
        ],
        _AreaMetricGrid(results: report.results),
        const SizedBox(height: 12),
        _AreaInputBarChart(results: report.results),
        const SizedBox(height: 12),
        _AreaFeeBarChart(results: report.results),
        const SizedBox(height: 12),
        _AreaSectorBreakdownTable(results: report.results),
        if (report.failures.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AreaFailurePanel(failures: report.failures),
        ],
      ],
    );
  }
}

class _AreaSourceCoveragePanel extends StatelessWidget {
  final List<StatisticsSectorAreaResult> results;

  const _AreaSourceCoveragePanel({required this.results});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unavailable = results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.unavailableVehicleCount,
    );
    final total = results.fold<int>(
      0,
      (sum, result) => sum + result.sectorReport.totalVehicleCount,
    );
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations == true
          ? Duration.zero
          : CommonUiMotion.layout,
      curve: CommonUiMotion.enter,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: cs.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '비교 대상 전체 $total대 중 방문 구역 원천 필드가 없는 $unavailable대는 Sector 비교에서 제외했습니다. Area별 카드와 PDF에서 제외 수를 함께 표시합니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaMetricGrid extends StatelessWidget {
  final List<StatisticsSectorAreaResult> results;

  const _AreaMetricGrid({required this.results});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final result in results)
          Container(
            width: 238,
            padding: const EdgeInsets.all(14),
            decoration: StatisticsReportDesign.screenPanel(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.area,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text('분석 가능 ${result.sectorReport.analyzableVehicleCount}대'),
                Text('원천 없음 ${result.sectorReport.unavailableVehicleCount}대'),
                Text('입차 ${result.sectorReport.totalInputCount}대'),
                Text('Sector ${result.sectorReport.sectorCount}개'),
                Text('미지정 ${result.sectorReport.unassignedVehicleCount}대'),
                Text('확인 필요 ${result.sectorReport.invalidVehicleCount}대'),
                Text('잠금 금액 ₩${_fmt(result.sectorReport.totalLockedFee)}'),
              ],
            ),
          ),
      ],
    );
  }
}

class _AreaInputBarChart extends StatelessWidget {
  final List<StatisticsSectorAreaResult> results;

  const _AreaInputBarChart({required this.results});

  @override
  Widget build(BuildContext context) {
    return _AreaChartPanel(
      title: 'Area별 Sector 입차 합계',
      subtitle: '각 Area의 당일 완료 업무 기준 입차 대수를 비교합니다.',
      child: StatisticsExpandableChart(
        title: 'Area별 Sector 입차 합계',
        subtitle: '각 Area의 당일 완료 업무 기준 입차 대수를 비교합니다.',
        debugLabel: 'area_input',
        preview: _AreaBarChart(
          results: results,
          value: (result) => result.sectorReport.totalInputCount.toDouble(),
          tooltip: (result) =>
              '${result.area}\n${result.sectorReport.totalInputCount}대',
          color: Theme.of(context).colorScheme.primary,
          currency: false,
          interactive: false,
          landscape: false,
        ),
        expandedBuilder: (context, landscape) => _ExpandedAreaBarChart(
          results: results,
          value: (result) => result.sectorReport.totalInputCount.toDouble(),
          valueText: (result) => '${result.sectorReport.totalInputCount}대',
          tooltip: (result) =>
              '${result.area}\n${result.sectorReport.totalInputCount}대',
          color: Theme.of(context).colorScheme.primary,
          currency: false,
          landscape: landscape,
          debugLabel: 'area_input',
        ),
      ),
    );
  }
}

class _AreaFeeBarChart extends StatelessWidget {
  final List<StatisticsSectorAreaResult> results;

  const _AreaFeeBarChart({required this.results});

  @override
  Widget build(BuildContext context) {
    return _AreaChartPanel(
      title: 'Area별 Sector 잠금 금액',
      subtitle: 'Area별 완료 업무의 잠금 금액 합계를 비교합니다.',
      child: StatisticsExpandableChart(
        title: 'Area별 Sector 잠금 금액',
        subtitle: 'Area별 완료 업무의 잠금 금액 합계를 비교합니다.',
        debugLabel: 'area_fee',
        preview: _AreaBarChart(
          results: results,
          value: (result) => result.sectorReport.totalLockedFee.toDouble(),
          tooltip: (result) =>
              '${result.area}\n₩${_fmt(result.sectorReport.totalLockedFee)}',
          color: Theme.of(context).colorScheme.tertiary,
          currency: true,
          interactive: false,
          landscape: false,
        ),
        expandedBuilder: (context, landscape) => _ExpandedAreaBarChart(
          results: results,
          value: (result) => result.sectorReport.totalLockedFee.toDouble(),
          valueText: (result) =>
              '₩${_fmt(result.sectorReport.totalLockedFee)}',
          tooltip: (result) =>
              '${result.area}\n₩${_fmt(result.sectorReport.totalLockedFee)}',
          color: Theme.of(context).colorScheme.tertiary,
          currency: true,
          landscape: landscape,
          debugLabel: 'area_fee',
        ),
      ),
    );
  }
}

class _AreaBarChart extends StatelessWidget {
  final List<StatisticsSectorAreaResult> results;
  final double Function(StatisticsSectorAreaResult result) value;
  final String Function(StatisticsSectorAreaResult result) tooltip;
  final Color color;
  final bool currency;
  final bool interactive;
  final bool landscape;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  const _AreaBarChart({
    required this.results,
    required this.value,
    required this.tooltip,
    required this.color,
    required this.currency,
    required this.interactive,
    required this.landscape,
    this.selectedIndex,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxValue = results.fold<double>(
      0,
      (p, e) => math.max(p, value(e)).toDouble(),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          results.length * (landscape ? 150.0 : 108.0) + 72,
        ).toDouble();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: width,
            height: landscape ? 430 : 300,
            child: BarChart(
              BarChartData(
                maxY: maxValue <= 0 ? 5 : (maxValue * 1.25).ceilToDouble(),
                alignment: BarChartAlignment.spaceAround,
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
                      if (index < 0 || index >= results.length) return null;
                      return BarTooltipItem(
                        tooltip(results[index]),
                        TextStyle(
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: landscape ? 68 : 54,
                      getTitlesWidget: (value, meta) => Text(
                        currency ? _compact(value) : value.toInt().toString(),
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
                      reservedSize: landscape ? 62 : 54,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= results.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 8,
                          child: SizedBox(
                            width: landscape ? 132 : 80,
                            child: Text(
                              results[index].area,
                              textAlign: TextAlign.center,
                              maxLines: landscape ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: landscape ? 11 : 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (int i = 0; i < results.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: value(results[i]),
                          color: selectedIndex == null || selectedIndex == i
                              ? color
                              : color.withOpacity(.38),
                          width: landscape ? 30 : 22,
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

class _ExpandedAreaBarChart extends StatefulWidget {
  final List<StatisticsSectorAreaResult> results;
  final double Function(StatisticsSectorAreaResult result) value;
  final String Function(StatisticsSectorAreaResult result) valueText;
  final String Function(StatisticsSectorAreaResult result) tooltip;
  final Color color;
  final bool currency;
  final bool landscape;
  final String debugLabel;

  const _ExpandedAreaBarChart({
    required this.results,
    required this.value,
    required this.valueText,
    required this.tooltip,
    required this.color,
    required this.currency,
    required this.landscape,
    required this.debugLabel,
  });

  @override
  State<_ExpandedAreaBarChart> createState() => _ExpandedAreaBarChartState();
}

class _ExpandedAreaBarChartState extends State<_ExpandedAreaBarChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final index = _selectedIndex;
    final selected = index == null || index < 0 || index >= widget.results.length
        ? null
        : widget.results[index];
    final total = widget.results.fold<double>(
      0,
      (sum, result) => sum + widget.value(result),
    );
    final ratio = selected == null || total <= 0
        ? 0.0
        : widget.value(selected) / total;
    return Column(
      children: [
        Expanded(
          child: _AreaBarChart(
            results: widget.results,
            value: widget.value,
            tooltip: widget.tooltip,
            color: widget.color,
            currency: widget.currency,
            interactive: true,
            landscape: widget.landscape,
            selectedIndex: index,
            onSelected: (next) {
              if (next < 0 || next >= widget.results.length) return;
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = next);
              StatisticsChartInteractionLog.log(
                'select chart=${widget.debugLabel} index=$next area=${widget.results[next].area} value=${widget.valueText(widget.results[next])}',
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        StatisticsChartSelectionPanel(
          title: selected == null
              ? '막대를 눌러 Area별 상세값을 확인하세요.'
              : selected.area,
          values: selected == null
              ? const <String>[]
              : <String>[
                  widget.valueText(selected),
                  '비교 합계 대비 ${(ratio * 100).toStringAsFixed(1)}%',
                ],
          icon: Icons.compare_arrows_rounded,
        ),
      ],
    );
  }
}

class _AreaSectorBreakdownTable extends StatelessWidget {
  final List<StatisticsSectorAreaResult> results;

  const _AreaSectorBreakdownTable({required this.results});

  @override
  Widget build(BuildContext context) {
    return _AreaChartPanel(
      title: 'Area별 Sector 상세',
      subtitle: 'Sector ID는 Area 내부 식별자로 취급하며 Area 간 자동 병합하지 않습니다.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Area')),
            DataColumn(label: Text('방문 구역')),
            DataColumn(label: Text('입차')),
            DataColumn(label: Text('출차')),
            DataColumn(label: Text('차량')),
            DataColumn(label: Text('잠금 금액')),
            DataColumn(label: Text('무결성')),
          ],
          rows: [
            for (final result in results)
              for (final group in result.sectorReport.groups)
                DataRow(
                  cells: [
                    DataCell(Text(result.area)),
                    DataCell(Text(group.sectorLabel)),
                    DataCell(Text('${group.inputCount}대')),
                    DataCell(Text('${group.outputCount}대')),
                    DataCell(Text('${group.vehicleCount}대')),
                    DataCell(Text('₩${_fmt(group.totalLockedFee)}')),
                    DataCell(
                      Text(result.sectorReport.integrity.isValid ? '정상' : '확인'),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _AreaFailurePanel extends StatelessWidget {
  final List<StatisticsSectorAreaFailure> failures;

  const _AreaFailurePanel({required this.failures});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '조회 실패 Area',
            style: TextStyle(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final failure in failures)
            Text(
              '${failure.area}: ${failure.message}',
              style: TextStyle(color: cs.onErrorContainer),
            ),
        ],
      ),
    );
  }
}

class _AreaChartPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _AreaChartPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: const Center(
        child: Text('두 개 이상의 Area를 선택한 뒤 비교를 실행해 주세요.'),
      ),
    );
  }
}

String _fmt(int value) {
  final text = value.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

String _compact(double value) {
  if (value.abs() >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}억';
  }
  if (value.abs() >= 10000) {
    return '${(value / 10000).toStringAsFixed(0)}만';
  }
  return value.toInt().toString();
}
