import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'statistics_deep_model.dart';
import 'statistics_report_design.dart';

class StatisticsSectorPdfBuilder {
  static void append({
    required pw.Document doc,
    required pw.ThemeData theme,
    required pw.Widget Function(pw.Context context) footer,
    required StatisticsDeepReport report,
    required StatisticsPdfDesign design,
  }) {
    final sector = report.sectorReport;
    if (!report.sectorEnabled || sector == null) return;

    pw.Widget header(pw.Context context) {
      return design.runningHeader(
        reportTitle: '방문 구역 분석 보고서',
        area: report.area,
        rangeLabel: report.scopeLabel,
      );
    }

    if (!sector.hasAnalyzableData) {
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
          header: header,
          footer: footer,
          build: (context) => [
            design.sectionHeader(
              titleText: '방문 구역 분석',
              subtitle: '${report.area} · ${report.scopeLabel}',
              eyebrow: 'SECTOR ANALYTICS',
              tone: StatisticsPdfTone.secondary,
            ),
            pw.SizedBox(height: 16),
            design.notice(
              titleText: '방문 구역 원천 데이터 없음',
              message:
                  '선택한 로그에는 방문 구역 필드가 없어 Sector 통계를 생성하지 않았습니다.',
              tone: StatisticsPdfTone.warning,
              details: <String>[
                'Sector 지원 이전에 생성된 CSV이거나 방문 구역 필드가 저장되지 않은 범위입니다.',
                '전체 ${sector.totalVehicleCount}대는 기본 통계에 포함되며 방문 구역 분석에서만 제외됩니다.',
              ],
            ),
          ],
        ),
      );
      return;
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 25, 26, 30),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: '방문 구역 운영 요약',
            subtitle: '${report.area} · ${report.scopeLabel} · 당일 완료 업무 기준',
            eyebrow: 'SECTOR EXECUTIVE SUMMARY',
            sectionNumber: 'S1',
            tone: StatisticsPdfTone.secondary,
          ),
          pw.SizedBox(height: 12),
          design.metricGrid([
            StatisticsPdfMetricData(
              label: '분석 가능',
              value: '${sector.analyzableVehicleCount}대',
              tone: StatisticsPdfTone.primary,
            ),
            StatisticsPdfMetricData(
              label: '원천 없음',
              value: '${sector.unavailableVehicleCount}대',
              tone: sector.unavailableVehicleCount == 0
                  ? StatisticsPdfTone.success
                  : StatisticsPdfTone.warning,
            ),
            StatisticsPdfMetricData(
              label: 'Sector',
              value: '${sector.sectorCount}개',
              tone: StatisticsPdfTone.secondary,
            ),
            StatisticsPdfMetricData(
              label: '입차 합계',
              value: '${sector.totalInputCount}대',
              tone: StatisticsPdfTone.input,
            ),
            StatisticsPdfMetricData(
              label: '잠금 금액',
              value: '₩${_fmt(sector.totalLockedFee)}',
              tone: StatisticsPdfTone.fee,
            ),
            StatisticsPdfMetricData(
              label: '정상 지정',
              value: '${sector.assignedVehicleCount}대',
              tone: StatisticsPdfTone.success,
            ),
            StatisticsPdfMetricData(
              label: '미지정',
              value: '${sector.unassignedVehicleCount}대',
              tone: StatisticsPdfTone.warning,
            ),
            StatisticsPdfMetricData(
              label: '확인 필요',
              value: '${sector.invalidVehicleCount}대',
              tone: StatisticsPdfTone.danger,
            ),
          ]),
          pw.SizedBox(height: 12),
          _integrityPanel(sector.integrity, design),
          if (sector.hasUnavailableData) ...[
            pw.SizedBox(height: 12),
            design.notice(
              titleText: '일부 차량의 방문 구역 원천 데이터 제외',
              message:
                  '전체 ${sector.totalVehicleCount}대 중 ${sector.analyzableVehicleCount}대만 Sector 통계에 포함했습니다.',
              tone: StatisticsPdfTone.warning,
              details: <String>[
                '원천 필드 없음 ${sector.unavailableVehicleCount}대',
                '분석률 ${(sector.analyzableRatio * 100).toStringAsFixed(1)}%',
                '제외 차량은 기본 차량 로그에 원천 데이터 없음으로 표시됩니다.',
              ],
            ),
          ],
          pw.SizedBox(height: 12),
          _sectorSummaryTable(sector, design),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 25, 26, 30),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: 'Sector별 입차 및 잠금 금액',
            subtitle: '차량 수와 금액을 분리해 방문 구역별 운영 규모를 비교합니다.',
            eyebrow: 'SECTOR DISTRIBUTION',
            sectionNumber: 'S2',
            tone: StatisticsPdfTone.input,
          ),
          pw.SizedBox(height: 12),
          _horizontalBars(
            design: design,
            title: 'Sector별 입차 대수',
            subtitle: '입차 시각이 확인된 당일 완료 차량 기준',
            groups: sector.groups,
            value: (group) => group.inputCount.toDouble(),
            label: (group) => '${group.inputCount}대',
            tone: StatisticsPdfTone.input,
          ),
          pw.SizedBox(height: 12),
          _horizontalBars(
            design: design,
            title: 'Sector별 잠금 금액',
            subtitle: '차량별 잠금 정산액 합계',
            groups: sector.groups,
            value: (group) => group.totalLockedFee.toDouble(),
            label: (group) => '₩${_fmt(group.totalLockedFee)}',
            tone: StatisticsPdfTone.fee,
          ),
        ],
      ),
    );

    final topGroups = sector.groups
        .where((group) => group.state == StatisticsSectorState.assigned)
        .take(5)
        .toList();
    if (topGroups.isEmpty) topGroups.addAll(sector.groups.take(5));

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: header,
        footer: footer,
        build: (context) => [
          design.sectionHeader(
            titleText: '날짜·시간대별 Sector 입차와 출차',
            subtitle: '차량 수 상위 방문 구역을 최대 5개까지 비교합니다.',
            eyebrow: 'SECTOR TIMELINE',
            sectionNumber: 'S3',
            tone: StatisticsPdfTone.input,
          ),
          pw.SizedBox(height: 10),
          _dailyLineChart(report, topGroups, design),
          pw.SizedBox(height: 10),
          _dailyTable(report, topGroups, design),
          pw.SizedBox(height: 12),
          _hourlyLineChart(
            title: '시간대별 입차 그래프',
            groups: topGroups,
            input: true,
            design: design,
          ),
          pw.SizedBox(height: 10),
          _hourlyTable(
            title: '시간대별 입차 수치',
            groups: topGroups,
            input: true,
            design: design,
          ),
          pw.SizedBox(height: 12),
          _hourlyLineChart(
            title: '시간대별 출차 그래프',
            groups: topGroups,
            input: false,
            design: design,
          ),
          pw.SizedBox(height: 10),
          _hourlyTable(
            title: '시간대별 출차 수치',
            groups: topGroups,
            input: false,
            design: design,
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
            titleText: 'Sector 정산·결제·요일 분석',
            subtitle: '금액이 있는 차량만 평균 정산액의 분모에 포함합니다.',
            eyebrow: 'SECTOR SETTLEMENT',
            sectionNumber: 'S4',
            tone: StatisticsPdfTone.fee,
          ),
          pw.SizedBox(height: 10),
          _paymentStackedBars(sector.groups, design),
          pw.SizedBox(height: 10),
          _paymentTable(sector.groups, design),
          pw.SizedBox(height: 12),
          _feeStatisticsTable(sector.groups, design),
          pw.SizedBox(height: 12),
          _weekdayTable(sector.groups, design),
        ],
      ),
    );

    for (final group in sector.groups) {
      _appendGroupVehicleTables(
        doc: doc,
        theme: theme,
        footer: footer,
        header: header,
        group: group,
        design: design,
      );
    }
  }

  static pw.Widget _integrityPanel(
    StatisticsSectorIntegrity integrity,
    StatisticsPdfDesign design,
  ) {
    return design.notice(
      titleText: integrity.isValid
          ? '화면·PDF 합계 무결성 정상'
          : '화면·PDF 합계 무결성 확인 필요',
      message: integrity.isValid
          ? '차량 수, 입차 수와 잠금 금액이 공통 Sector 모델에서 일치합니다.'
          : '일부 합계가 일치하지 않아 원천 로그 확인이 필요합니다.',
      tone: integrity.isValid
          ? StatisticsPdfTone.success
          : StatisticsPdfTone.danger,
      details: integrity.debugLines,
    );
  }

  static pw.Widget _sectorSummaryTable(
    StatisticsSectorReport report,
    StatisticsPdfDesign design,
  ) {
    return design.dataTable(
      headers: const [
        '방문 구역',
        '상태',
        '차량',
        '입차',
        '출차',
        '잠금 금액',
        '평균 정산',
        '입차 집중',
        '출차 집중',
      ],
      rows: [
        for (final group in report.groups)
          [
            group.sectorLabel,
            _stateLabel(group.state),
            '${group.vehicleCount}대',
            '${group.inputCount}대',
            '${group.outputCount}대',
            '₩${_fmt(group.totalLockedFee)}',
            group.averageLockedFee == null
                ? '-'
                : '₩${_fmt(group.averageLockedFee!.round())}',
            group.peakInputHour == null
                ? '-'
                : '${group.peakInputHour!.toString().padLeft(2, '0')}시',
            group.peakOutputHour == null
                ? '-'
                : '${group.peakOutputHour!.toString().padLeft(2, '0')}시',
          ],
      ],
      numericColumns: const <int>{2, 3, 4, 5, 6},
      tone: StatisticsPdfTone.secondary,
      fontSize: 7.1,
      headerFontSize: 7.2,
      horizontalPadding: 3.4,
      verticalPadding: 4.6,
    );
  }

  static pw.Widget _horizontalBars({
    required StatisticsPdfDesign design,
    required String title,
    required String subtitle,
    required List<StatisticsSectorGroup> groups,
    required double Function(StatisticsSectorGroup group) value,
    required String Function(StatisticsSectorGroup group) label,
    required StatisticsPdfTone tone,
  }) {
    final maxValue = groups.fold<double>(
      0,
      (previous, group) => math.max(previous, value(group)).toDouble(),
    );
    final accent = design.toneColor(tone);
    final track = design.toneSoft(tone);
    return design.chartCard(
      titleText: title,
      subtitle: subtitle,
      badge: '${groups.length}개 구역',
      tone: tone,
      child: pw.Column(
        children: [
          for (final group in groups)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 94,
                    child: pw.Text(
                      group.sectorLabel,
                      maxLines: 2,
                      style: design.body(size: 7.8),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(
                    width: 315,
                    height: 9,
                    alignment: pw.Alignment.centerLeft,
                    decoration: pw.BoxDecoration(
                      color: track,
                      borderRadius: pw.BorderRadius.circular(999),
                    ),
                    child: pw.Container(
                      width: maxValue <= 0
                          ? 0
                          : value(group) / maxValue * 315,
                      height: 9,
                      decoration: pw.BoxDecoration(
                        color: accent,
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.Expanded(
                    child: pw.Text(
                      label(group),
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

  static pw.Widget _dailyLineChart(
    StatisticsDeepReport report,
    List<StatisticsSectorGroup> groups,
    StatisticsPdfDesign design,
  ) {
    final dates = <String>{...report.dateStrs};
    for (final group in groups) {
      dates.addAll(group.dailyInputCounts.keys);
    }
    final labels = dates.toList()..sort();
    return _multiSeriesLineChart(
      title: '날짜별 Sector 입차 추이',
      subtitle: '실제 입차 시각의 날짜를 기준으로 집계합니다.',
      labels: labels,
      groups: groups,
      values: (group) => [
        for (final label in labels) group.dailyInputCounts[label] ?? 0,
      ],
      compactXAxis: true,
      design: design,
      tone: StatisticsPdfTone.input,
    );
  }

  static pw.Widget _hourlyLineChart({
    required String title,
    required List<StatisticsSectorGroup> groups,
    required bool input,
    required StatisticsPdfDesign design,
  }) {
    final labels = <String>[
      for (int hour = 0; hour < 24; hour++)
        hour.toString().padLeft(2, '0'),
    ];
    return _multiSeriesLineChart(
      title: title,
      subtitle: input
          ? '입차 시각 기준 24시간 분포'
          : '출차 완료 시각 기준 24시간 분포',
      labels: labels,
      groups: groups,
      values: (group) => input
          ? group.hourlyInputCounts
          : group.hourlyOutputCounts,
      compactXAxis: false,
      design: design,
      tone: input ? StatisticsPdfTone.input : StatisticsPdfTone.output,
    );
  }

  static pw.Widget _multiSeriesLineChart({
    required String title,
    required String subtitle,
    required List<String> labels,
    required List<StatisticsSectorGroup> groups,
    required List<int> Function(StatisticsSectorGroup group) values,
    required bool compactXAxis,
    required StatisticsPdfDesign design,
    required StatisticsPdfTone tone,
  }) {
    if (labels.isEmpty || groups.isEmpty) {
      return design.notice(
        titleText: title,
        message: '그래프로 표시할 데이터가 없습니다.',
      );
    }
    final series = <List<int>>[
      for (final group in groups) values(group),
    ];
    var maxValue = 0;
    for (final values in series) {
      for (final value in values) {
        if (value > maxValue) maxValue = value;
      }
    }
    final svg = _lineChartSvg(
      labels: labels,
      series: series,
      colors: design.palette.seriesHex,
      maxValue: maxValue,
      compactXAxis: compactXAxis,
      design: design,
    );
    return design.chartCard(
      titleText: title,
      subtitle: subtitle,
      badge: '${groups.length}개 구역',
      tone: tone,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (int index = 0; index < groups.length; index++)
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 9,
                      height: 9,
                      decoration: pw.BoxDecoration(
                        color: design.palette.series[
                            index % design.palette.series.length],
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                    ),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      groups[index].sectorLabel,
                      style: design.body(size: 7.4),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.SizedBox(height: 170, child: pw.SvgImage(svg: svg)),
        ],
      ),
    );
  }

  static String _lineChartSvg({
    required List<String> labels,
    required List<List<int>> series,
    required List<String> colors,
    required int maxValue,
    required bool compactXAxis,
    required StatisticsPdfDesign design,
  }) {
    const width = 760.0;
    const height = 210.0;
    const left = 42.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 34.0;
    final plotWidth = width - left - right;
    final plotHeight = height - top - bottom;
    final divisor = maxValue <= 0 ? 1 : maxValue;
    final buffer = StringBuffer()
      ..write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $width $height">',
      )
      ..write(
        '<rect width="$width" height="$height" rx="14" fill="${design.palette.surfaceHex}"/>',
      );
    for (int index = 0; index <= 4; index++) {
      final y = top + plotHeight * index / 4;
      final value = (divisor * (4 - index) / 4).round();
      buffer
        ..write(
          '<line x1="$left" y1="$y" x2="${width - right}" y2="$y" stroke="${design.palette.lineHex}" stroke-width="1"/>',
        )
        ..write(
          '<text x="${left - 6}" y="${y + 3}" text-anchor="end" font-size="9" fill="${design.palette.mutedHex}">$value</text>',
        );
    }
    final denominator = labels.length <= 1 ? 1 : labels.length - 1;
    final tickStep = labels.length <= 8 ? 1 : (labels.length / 8).ceil();
    for (int index = 0; index < labels.length; index += tickStep) {
      final x = left + plotWidth * index / denominator;
      final label = compactXAxis && labels[index].length >= 5
          ? labels[index].substring(5)
          : labels[index];
      buffer
        ..write(
          '<line x1="$x" y1="${height - bottom}" x2="$x" y2="${height - bottom + 4}" stroke="${design.palette.mutedHex}" stroke-width="1"/>',
        )
        ..write(
          '<text x="$x" y="${height - 12}" text-anchor="middle" font-size="8" fill="${design.palette.mutedHex}">${_xml(label)}</text>',
        );
    }
    for (int seriesIndex = 0;
        seriesIndex < series.length;
        seriesIndex++) {
      final values = series[seriesIndex];
      final points = <String>[];
      for (int index = 0; index < labels.length; index++) {
        final x = left + plotWidth * index / denominator;
        final value = index < values.length ? values[index] : 0;
        final y = top + plotHeight * (1 - value / divisor);
        points.add('$x,$y');
      }
      final color = colors[seriesIndex % colors.length];
      buffer.write(
        '<polyline points="${points.join(' ')}" fill="none" stroke="$color" stroke-width="2.6" stroke-linejoin="round" stroke-linecap="round"/>',
      );
      for (final point in points) {
        final parts = point.split(',');
        buffer.write(
          '<circle cx="${parts[0]}" cy="${parts[1]}" r="2.3" fill="$color"/>',
        );
      }
    }
    buffer
      ..write(
        '<line x1="$left" y1="${height - bottom}" x2="${width - right}" y2="${height - bottom}" stroke="${design.palette.inkHex}" stroke-width="1.2"/>',
      )
      ..write(
        '<line x1="$left" y1="$top" x2="$left" y2="${height - bottom}" stroke="${design.palette.inkHex}" stroke-width="1.2"/>',
      )
      ..write('</svg>');
    return buffer.toString();
  }

  static pw.Widget _paymentStackedBars(
    List<StatisticsSectorGroup> groups,
    StatisticsPdfDesign design,
  ) {
    final methods = <String>{};
    for (final group in groups) {
      methods.addAll(group.feeByPaymentMethod.keys);
    }
    final sortedMethods = methods.toList()..sort();
    return design.chartCard(
      titleText: 'Sector별 결제수단 누적 금액',
      subtitle: '각 방문 구역의 결제수단별 잠금 금액 구성',
      badge: '${sortedMethods.length}개 결제수단',
      tone: StatisticsPdfTone.fee,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (int index = 0; index < sortedMethods.length; index++)
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 9,
                      height: 9,
                      decoration: pw.BoxDecoration(
                        color: design.palette.series[
                            index % design.palette.series.length],
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                    ),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      sortedMethods[index],
                      style: design.body(size: 7.4),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 8),
          for (final group in groups)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 92,
                    child: pw.Text(
                      group.sectorLabel,
                      style: design.body(size: 7.8),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      height: 12,
                      decoration: pw.BoxDecoration(
                        color: design.palette.surfaceAlt,
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                      child: pw.Row(
                        children: [
                          for (int index = 0;
                              index < sortedMethods.length;
                              index++)
                            if ((group.feeByPaymentMethod[
                                        sortedMethods[index]] ??
                                    0) >
                                0)
                              pw.Expanded(
                                flex: group.feeByPaymentMethod[
                                        sortedMethods[index]] ??
                                    0,
                                child: pw.Container(
                                  height: 12,
                                  color: design.palette.series[
                                      index % design.palette.series.length],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.SizedBox(
                    width: 76,
                    child: pw.Text(
                      '₩${_fmt(group.totalLockedFee)}',
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

  static pw.Widget _dailyTable(
    StatisticsDeepReport report,
    List<StatisticsSectorGroup> groups,
    StatisticsPdfDesign design,
  ) {
    final dates = <String>{...report.dateStrs};
    for (final group in groups) {
      dates.addAll(group.dailyInputCounts.keys);
    }
    final sortedDates = dates.toList()..sort();
    return design.dataTable(
      headers: ['입차일', for (final group in groups) group.sectorLabel],
      rows: [
        for (final date in sortedDates)
          [
            date,
            for (final group in groups)
              '${group.dailyInputCounts[date] ?? 0}대',
          ],
      ],
      numericColumns: <int>{
        for (int index = 1; index <= groups.length; index++) index,
      },
      tone: StatisticsPdfTone.input,
      fontSize: 7.2,
      headerFontSize: 7.3,
      horizontalPadding: 3.6,
      verticalPadding: 4.2,
    );
  }

  static pw.Widget _hourlyTable({
    required String title,
    required List<StatisticsSectorGroup> groups,
    required bool input,
    required StatisticsPdfDesign design,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: design.title(size: 10.5)),
        pw.SizedBox(height: 6),
        design.dataTable(
          headers: ['시각', for (final group in groups) group.sectorLabel],
          rows: [
            for (int hour = 0; hour < 24; hour++)
              [
                '${hour.toString().padLeft(2, '0')}시',
                for (final group in groups)
                  '${(input ? group.hourlyInputCounts : group.hourlyOutputCounts)[hour]}대',
              ],
          ],
          numericColumns: <int>{
            for (int index = 1; index <= groups.length; index++) index,
          },
          tone: input ? StatisticsPdfTone.input : StatisticsPdfTone.output,
          fontSize: 6.9,
          headerFontSize: 7,
          horizontalPadding: 3.2,
          verticalPadding: 3.2,
        ),
      ],
    );
  }

  static pw.Widget _paymentTable(
    List<StatisticsSectorGroup> groups,
    StatisticsPdfDesign design,
  ) {
    final methods = <String>{};
    for (final group in groups) {
      methods.addAll(group.feeByPaymentMethod.keys);
    }
    final sortedMethods = methods.toList()..sort();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Sector별 결제수단 금액', style: design.title(size: 10.5)),
        pw.SizedBox(height: 6),
        design.dataTable(
          headers: [
            '방문 구역',
            for (final method in sortedMethods) method,
            '합계',
          ],
          rows: [
            for (final group in groups)
              [
                group.sectorLabel,
                for (final method in sortedMethods)
                  '₩${_fmt(group.feeByPaymentMethod[method] ?? 0)}',
                '₩${_fmt(group.totalLockedFee)}',
              ],
          ],
          numericColumns: <int>{
            for (int index = 1; index <= sortedMethods.length + 1; index++)
              index,
          },
          tone: StatisticsPdfTone.fee,
          fontSize: 6.9,
          headerFontSize: 7,
          horizontalPadding: 3.2,
          verticalPadding: 3.8,
        ),
      ],
    );
  }

  static pw.Widget _feeStatisticsTable(
    List<StatisticsSectorGroup> groups,
    StatisticsPdfDesign design,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Sector별 정산 분포 비교', style: design.title(size: 10.5)),
        pw.SizedBox(height: 6),
        design.dataTable(
          headers: const [
            '방문 구역',
            '표본',
            '평균',
            '중앙값',
            '최솟값',
            '최댓값',
            '25%',
            '75%',
          ],
          rows: [
            for (final group in groups)
              [
                group.sectorLabel,
                '${group.feeVehicleCount}대',
                _money(group.averageLockedFee),
                _money(group.medianLockedFee),
                _money(group.minLockedFee),
                _money(group.maxLockedFee),
                _money(group.lowerQuartileLockedFee),
                _money(group.upperQuartileLockedFee),
              ],
          ],
          numericColumns: const <int>{1, 2, 3, 4, 5, 6, 7},
          tone: StatisticsPdfTone.fee,
          fontSize: 6.8,
          headerFontSize: 6.9,
          horizontalPadding: 3,
          verticalPadding: 3.8,
        ),
      ],
    );
  }

  static pw.Widget _weekdayTable(
    List<StatisticsSectorGroup> groups,
    StatisticsPdfDesign design,
  ) {
    final data = <List<String>>[];
    for (final group in groups) {
      for (int weekday = 1; weekday <= 7; weekday++) {
        final days = group.weekdayDateCounts[weekday] ?? 0;
        if (days <= 0) continue;
        data.add([
          group.sectorLabel,
          '${_weekdayName(weekday)}요일',
          '${group.weekdayInputCounts[weekday] ?? 0}대',
          '$days일',
          '${group.inputAverageForWeekday(weekday).toStringAsFixed(1)}대',
        ]);
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('요일별 Sector 상세 분석', style: design.title(size: 10.5)),
        pw.SizedBox(height: 6),
        design.dataTable(
          headers: const ['방문 구역', '요일', '입차 합계', '대상 일수', '1일 평균'],
          rows: data,
          numericColumns: const <int>{2, 3, 4},
          tone: StatisticsPdfTone.secondary,
          fontSize: 7,
          headerFontSize: 7.1,
          horizontalPadding: 3.4,
          verticalPadding: 3.8,
        ),
      ],
    );
  }

  static void _appendGroupVehicleTables({
    required pw.Document doc,
    required pw.ThemeData theme,
    required pw.Widget Function(pw.Context context) footer,
    required pw.Widget Function(pw.Context context) header,
    required StatisticsSectorGroup group,
    required StatisticsPdfDesign design,
  }) {
    const chunkSize = 30;
    if (group.rows.isEmpty) return;
    for (int start = 0; start < group.rows.length; start += chunkSize) {
      final chunk = group.rows.skip(start).take(chunkSize).toList();
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(22, 25, 22, 30),
          header: header,
          footer: footer,
          build: (context) => [
            design.sectionHeader(
              titleText: '${group.sectorLabel} 차량 로그',
              subtitle:
                  '${start + 1} - ${start + chunk.length} / ${group.rows.length}',
              eyebrow: 'SECTOR VEHICLE APPENDIX',
              tone: _stateTone(group.state),
            ),
            pw.SizedBox(height: 10),
            design.metricGrid([
              StatisticsPdfMetricData(
                label: '차량',
                value: '${group.vehicleCount}대',
                tone: _stateTone(group.state),
              ),
              StatisticsPdfMetricData(
                label: '입차',
                value: '${group.inputCount}대',
                tone: StatisticsPdfTone.input,
              ),
              StatisticsPdfMetricData(
                label: '잠금 금액',
                value: '₩${_fmt(group.totalLockedFee)}',
                tone: StatisticsPdfTone.fee,
              ),
            ]),
            pw.SizedBox(height: 10),
            design.dataTable(
              headers: const [
                'No',
                '날짜',
                '차량 번호',
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
                    _time(row.createdAt),
                    row.departureTimeEstimated
                        ? '${_time(row.departureAt)} 추정'
                        : _time(row.departureAt),
                    row.fee == null ? '-' : '₩${_fmt(row.fee!)}',
                    row.paymentMethodLabel,
                  ],
              ],
              numericColumns: const <int>{0, 5},
              tone: _stateTone(group.state),
              fontSize: 7,
              headerFontSize: 7.1,
              horizontalPadding: 3.4,
              verticalPadding: 4.3,
            ),
          ],
        ),
      );
    }
  }

  static StatisticsPdfTone _stateTone(StatisticsSectorState state) {
    switch (state) {
      case StatisticsSectorState.assigned:
        return StatisticsPdfTone.success;
      case StatisticsSectorState.unassigned:
        return StatisticsPdfTone.warning;
      case StatisticsSectorState.invalid:
        return StatisticsPdfTone.danger;
      case StatisticsSectorState.unavailable:
        return StatisticsPdfTone.neutral;
    }
  }

  static String _stateLabel(StatisticsSectorState state) {
    switch (state) {
      case StatisticsSectorState.assigned:
        return '정상';
      case StatisticsSectorState.unassigned:
        return '미지정';
      case StatisticsSectorState.invalid:
        return '확인 필요';
      case StatisticsSectorState.unavailable:
        return '원천 없음';
    }
  }

  static String _weekdayName(int weekday) {
    switch (weekday) {
      case 1:
        return '월';
      case 2:
        return '화';
      case 3:
        return '수';
      case 4:
        return '목';
      case 5:
        return '금';
      case 6:
        return '토';
      case 7:
        return '일';
    }
    return '-';
  }

  static String _time(DateTime? value) {
    if (value == null) return '-';
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
  }

  static String _money(num? value) {
    if (value == null) return '-';
    return '₩${_fmt(value.round())}';
  }

  static String _fmt(int value) {
    final text = value.abs().toString();
    final buffer = StringBuffer();
    for (int index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
      buffer.write(text[index]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }

  static String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
