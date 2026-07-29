import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum StatisticsPdfTone {
  primary,
  secondary,
  success,
  warning,
  danger,
  neutral,
  input,
  output,
  fee,
}

class StatisticsPdfMetricData {
  const StatisticsPdfMetricData({
    required this.label,
    required this.value,
    this.caption,
    this.tone = StatisticsPdfTone.neutral,
  });

  final String label;
  final String value;
  final String? caption;
  final StatisticsPdfTone tone;
}

class StatisticsPdfTagData {
  const StatisticsPdfTagData({
    required this.label,
    this.tone = StatisticsPdfTone.neutral,
  });

  final String label;
  final StatisticsPdfTone tone;
}

class StatisticsPdfPalette {
  const StatisticsPdfPalette({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.onPrimary,
    required this.paper,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.line,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.secondary,
    required this.secondarySoft,
    required this.input,
    required this.output,
    required this.fee,
    required this.series,
    required this.seriesHex,
    required this.primaryHex,
    required this.inkHex,
    required this.mutedHex,
    required this.lineHex,
    required this.surfaceHex,
  });

  final PdfColor primary;
  final PdfColor primaryDark;
  final PdfColor primarySoft;
  final PdfColor onPrimary;
  final PdfColor paper;
  final PdfColor surface;
  final PdfColor surfaceAlt;
  final PdfColor ink;
  final PdfColor muted;
  final PdfColor line;
  final PdfColor success;
  final PdfColor successSoft;
  final PdfColor warning;
  final PdfColor warningSoft;
  final PdfColor danger;
  final PdfColor dangerSoft;
  final PdfColor secondary;
  final PdfColor secondarySoft;
  final PdfColor input;
  final PdfColor output;
  final PdfColor fee;
  final List<PdfColor> series;
  final List<String> seriesHex;
  final String primaryHex;
  final String inkHex;
  final String mutedHex;
  final String lineHex;
  final String surfaceHex;

  factory StatisticsPdfPalette.fromColorScheme(ColorScheme scheme) {
    final primary = scheme.primary;
    final primaryDark = Color.lerp(primary, Colors.black, .34)!;
    final primarySoft = Color.lerp(primary, Colors.white, .87)!;
    final paper = Color.lerp(scheme.surface, Colors.white, .92)!;
    final surface = Color.lerp(scheme.surface, Colors.white, .78)!;
    final surfaceAlt = Color.lerp(scheme.surfaceContainerHighest, Colors.white, .70)!;
    final ink = Color.lerp(scheme.onSurface, Colors.black, .22)!;
    final muted = Color.lerp(scheme.onSurfaceVariant, Colors.white, .12)!;
    final line = Color.lerp(scheme.outlineVariant, Colors.white, .40)!;
    final secondary = scheme.secondary;
    final success = Color.lerp(const Color(0xFF15803D), primary, .10)!;
    final warning = Color.lerp(const Color(0xFFB45309), primary, .08)!;
    final danger = scheme.error;
    final input = primary;
    final output = scheme.tertiary;
    final fee = scheme.secondary;
    final seriesColors = <Color>[
      primary,
      scheme.tertiary,
      scheme.secondary,
      success,
      warning,
      danger,
      Color.lerp(primary, scheme.tertiary, .52)!,
      Color.lerp(scheme.secondary, warning, .45)!,
    ];
    return StatisticsPdfPalette(
      primary: _pdf(primary),
      primaryDark: _pdf(primaryDark),
      primarySoft: _pdf(primarySoft),
      onPrimary: _pdf(primary.computeLuminance() > .48 ? Colors.black : Colors.white),
      paper: _pdf(paper),
      surface: _pdf(surface),
      surfaceAlt: _pdf(surfaceAlt),
      ink: _pdf(ink),
      muted: _pdf(muted),
      line: _pdf(line),
      success: _pdf(success),
      successSoft: _pdf(Color.lerp(success, Colors.white, .88)!),
      warning: _pdf(warning),
      warningSoft: _pdf(Color.lerp(warning, Colors.white, .88)!),
      danger: _pdf(danger),
      dangerSoft: _pdf(Color.lerp(danger, Colors.white, .90)!),
      secondary: _pdf(secondary),
      secondarySoft: _pdf(Color.lerp(secondary, Colors.white, .88)!),
      input: _pdf(input),
      output: _pdf(output),
      fee: _pdf(fee),
      series: seriesColors.map(_pdf).toList(growable: false),
      seriesHex: seriesColors.map(_hex).toList(growable: false),
      primaryHex: _hex(primary),
      inkHex: _hex(ink),
      mutedHex: _hex(muted),
      lineHex: _hex(line),
      surfaceHex: _hex(surface),
    );
  }

  String get debugLabel =>
      'primary=$primaryHex ink=$inkHex surface=$surfaceHex series=${seriesHex.length}';

  static PdfColor _pdf(Color color) => PdfColor.fromInt(color.value);

  static String _hex(Color color) {
    final value = color.value & 0x00FFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

class StatisticsPdfDesign {
  const StatisticsPdfDesign(this.palette);

  final StatisticsPdfPalette palette;

  PdfColor toneColor(StatisticsPdfTone tone) {
    switch (tone) {
      case StatisticsPdfTone.primary:
        return palette.primary;
      case StatisticsPdfTone.secondary:
        return palette.secondary;
      case StatisticsPdfTone.success:
        return palette.success;
      case StatisticsPdfTone.warning:
        return palette.warning;
      case StatisticsPdfTone.danger:
        return palette.danger;
      case StatisticsPdfTone.input:
        return palette.input;
      case StatisticsPdfTone.output:
        return palette.output;
      case StatisticsPdfTone.fee:
        return palette.fee;
      case StatisticsPdfTone.neutral:
        return palette.muted;
    }
  }

  PdfColor toneSoft(StatisticsPdfTone tone) {
    switch (tone) {
      case StatisticsPdfTone.primary:
        return palette.primarySoft;
      case StatisticsPdfTone.secondary:
        return palette.secondarySoft;
      case StatisticsPdfTone.success:
        return palette.successSoft;
      case StatisticsPdfTone.warning:
        return palette.warningSoft;
      case StatisticsPdfTone.danger:
        return palette.dangerSoft;
      case StatisticsPdfTone.input:
        return palette.primarySoft;
      case StatisticsPdfTone.output:
        return palette.secondarySoft;
      case StatisticsPdfTone.fee:
        return palette.warningSoft;
      case StatisticsPdfTone.neutral:
        return palette.surfaceAlt;
    }
  }

  pw.TextStyle title({double size = 22, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? palette.ink,
      fontWeight: pw.FontWeight.bold,
      lineSpacing: 1.1,
    );
  }

  pw.TextStyle body({double size = 10, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? palette.ink,
      lineSpacing: 1.25,
    );
  }

  pw.TextStyle label({double size = 9, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? palette.muted,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: .15,
    );
  }

  pw.BoxDecoration card({
    PdfColor? fill,
    double radius = 14,
    bool outlined = true,
  }) {
    return pw.BoxDecoration(
      color: fill ?? palette.surface,
      border: outlined
          ? pw.Border.all(color: palette.line, width: .65)
          : null,
      borderRadius: pw.BorderRadius.circular(radius),
    );
  }

  pw.Widget tag(StatisticsPdfTagData data) {
    final color = toneColor(data.tone);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      decoration: pw.BoxDecoration(
        color: toneSoft(data.tone),
        border: pw.Border.all(color: color, width: .45),
        borderRadius: pw.BorderRadius.circular(999),
      ),
      child: pw.Text(
        data.label,
        style: label(size: 7.8, color: color),
      ),
    );
  }

  pw.Widget cover({
    required String reportCode,
    required String titleText,
    required String subtitle,
    required DateTime createdAt,
    required List<StatisticsPdfTagData> tags,
    required List<StatisticsPdfMetricData> metrics,
    String? description,
    String? division,
    String? area,
    String? rangeLabel,
  }) {
    final info = <String>[
      if ((division ?? '').trim().isNotEmpty) '사업부  ${division!.trim()}',
      if ((area ?? '').trim().isNotEmpty) 'Area  ${area!.trim()}',
      if ((rangeLabel ?? '').trim().isNotEmpty) '조회 범위  ${rangeLabel!.trim()}',
      '생성 시각  ${_fmtDateTime(createdAt)}',
    ];
    return pw.Container(
      color: palette.paper,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: 205,
            padding: const pw.EdgeInsets.fromLTRB(36, 34, 36, 30),
            decoration: pw.BoxDecoration(
              color: palette.primaryDark,
              borderRadius: const pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(28),
                bottomRight: pw.Radius.circular(28),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'PARKINWORKIN',
                      style: label(size: 9, color: palette.onPrimary),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: pw.BoxDecoration(
                        color: palette.primary,
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                      child: pw.Text(
                        reportCode,
                        style: label(size: 8, color: palette.onPrimary),
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  titleText,
                  style: title(size: 30, color: palette.onPrimary),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  subtitle,
                  style: body(size: 12.5, color: palette.onPrimary),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(34, 26, 34, 30),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (tags.isNotEmpty)
                    pw.Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final item in tags) tag(item)],
                    ),
                  if ((description ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 18),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(14),
                      decoration: card(
                        fill: palette.primarySoft,
                      ),
                      child: pw.Text(
                        description!.trim(),
                        style: body(size: 10.5, color: palette.primaryDark),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 20),
                  metricGrid(metrics),
                  pw.Spacer(),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(14),
                    decoration: card(fill: palette.surfaceAlt),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('REPORT INFORMATION', style: label(size: 8)),
                        pw.SizedBox(height: 7),
                        for (final line in info)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3),
                            child: pw.Text(line, style: body(size: 9.5)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget metricGrid(List<StatisticsPdfMetricData> metrics) {
    final rows = <pw.Widget>[];
    for (int start = 0; start < metrics.length; start += 3) {
      final chunk = metrics.skip(start).take(3).toList();
      if (rows.isNotEmpty) rows.add(pw.SizedBox(height: 8));
      rows.add(
        pw.Row(
          children: [
            for (int index = 0; index < chunk.length; index++) ...[
              if (index > 0) pw.SizedBox(width: 8),
              metricCard(chunk[index]),
            ],
            for (int index = chunk.length; index < 3; index++) ...[
              if (index > 0) pw.SizedBox(width: 8),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ],
        ),
      );
    }
    return pw.Column(children: rows);
  }

  pw.Widget metricCard(StatisticsPdfMetricData data) {
    final accent = toneColor(data.tone);
    return pw.Expanded(
      child: pw.Container(
        decoration: card(fill: toneSoft(data.tone)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 4,
              height: 48,
              decoration: pw.BoxDecoration(
                color: accent,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(13),
                  bottomLeft: pw.Radius.circular(13),
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(10, 9, 9, 9),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(data.label, style: label(size: 8, color: accent)),
                    pw.SizedBox(height: 4),
                    pw.Text(data.value, style: title(size: 13)),
                    if ((data.caption ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        data.caption!.trim(),
                        style: body(size: 7.5, color: palette.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget runningHeader({
    required String reportTitle,
    String? area,
    String? rangeLabel,
  }) {
    final meta = <String>[
      if ((area ?? '').trim().isNotEmpty) area!.trim(),
      if ((rangeLabel ?? '').trim().isNotEmpty) rangeLabel!.trim(),
    ].join('  ·  ');
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.line, width: .55),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: palette.primary,
                  borderRadius: pw.BorderRadius.circular(999),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Text(reportTitle, style: label(size: 8.2, color: palette.ink)),
            ],
          ),
          if (meta.isNotEmpty)
            pw.Text(meta, style: body(size: 7.5, color: palette.muted)),
        ],
      ),
    );
  }

  pw.Widget sectionHeader({
    required String titleText,
    String? subtitle,
    String? eyebrow,
    String? sectionNumber,
    StatisticsPdfTone tone = StatisticsPdfTone.primary,
  }) {
    final accent = toneColor(tone);
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(0, 4, 0, 13),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.line, width: .75),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 5,
            height: 48,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(999),
            ),
          ),
          pw.SizedBox(width: 11),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if ((eyebrow ?? '').trim().isNotEmpty) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: toneSoft(tone),
                      borderRadius: pw.BorderRadius.circular(999),
                    ),
                    child: pw.Text(
                      eyebrow!.trim(),
                      style: label(size: 7.4, color: accent),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                pw.Text(titleText, style: title(size: 18)),
                if ((subtitle ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    subtitle!.trim(),
                    style: body(size: 9.2, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
          if ((sectionNumber ?? '').trim().isNotEmpty)
            pw.Container(
              width: 31,
              height: 31,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: toneSoft(tone),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                sectionNumber!.trim(),
                style: title(size: 10, color: accent),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget chartCard({
    required String titleText,
    required pw.Widget child,
    String? subtitle,
    String? badge,
    StatisticsPdfTone tone = StatisticsPdfTone.primary,
    double padding = 12,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(padding),
      decoration: card(fill: palette.surface),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(titleText, style: title(size: 11.5)),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        subtitle!.trim(),
                        style: body(size: 8, color: palette.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if ((badge ?? '').trim().isNotEmpty)
                tag(StatisticsPdfTagData(label: badge!.trim(), tone: tone)),
            ],
          ),
          pw.SizedBox(height: 9),
          child,
        ],
      ),
    );
  }

  pw.Widget notice({
    required String titleText,
    required String message,
    StatisticsPdfTone tone = StatisticsPdfTone.neutral,
    List<String> details = const <String>[],
  }) {
    final accent = toneColor(tone);
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(13),
      decoration: card(fill: toneSoft(tone)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: details.isEmpty ? 34 : 52,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(999),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(titleText, style: title(size: 11.5, color: accent)),
                pw.SizedBox(height: 4),
                pw.Text(message, style: body(size: 8.8)),
                for (final detail in details) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(detail, style: body(size: 7.7, color: palette.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget dataTable({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.TableColumnWidth>? columnWidths,
    Set<int> numericColumns = const <int>{},
    double fontSize = 7.6,
    double headerFontSize = 7.8,
    double horizontalPadding = 4.5,
    double verticalPadding = 4.5,
    StatisticsPdfTone tone = StatisticsPdfTone.primary,
  }) {
    final accent = toneColor(tone);
    pw.Widget cell(
      String text,
      int column, {
      required bool header,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: pw.Text(
          text,
          textAlign: numericColumns.contains(column)
              ? pw.TextAlign.right
              : pw.TextAlign.left,
          style: header
              ? label(size: headerFontSize, color: accent)
              : body(size: fontSize),
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      decoration: card(fill: palette.surface),
      child: pw.Table(
        columnWidths: columnWidths,
        border: pw.TableBorder.all(color: palette.line, width: .32),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: toneSoft(tone)),
            children: [
              for (int column = 0; column < headers.length; column++)
                cell(headers[column], column, header: true),
            ],
          ),
          for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: rowIndex.isOdd ? palette.surfaceAlt : palette.surface,
              ),
              children: [
                for (int column = 0; column < headers.length; column++)
                  cell(
                    column < rows[rowIndex].length ? rows[rowIndex][column] : '',
                    column,
                    header: false,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget footer({
    required pw.Context context,
    required DateTime createdAt,
    required String labelText,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: palette.line, width: .55),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 16, height: 2.4, color: palette.primary),
              pw.SizedBox(width: 6),
              pw.Text(labelText, style: label(size: 7.2)),
            ],
          ),
          pw.Text(
            '${_fmtDateTime(createdAt)}  ·  ${context.pageNumber} / ${context.pagesCount}',
            style: body(size: 7.2, color: palette.muted),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class StatisticsReportDesign {
  static const double radius = 28;
  static const double cardPadding = 18;

  static StatisticsPdfPalette pdfPalette(BuildContext context) {
    return StatisticsPdfPalette.fromColorScheme(Theme.of(context).colorScheme);
  }

  static StatisticsPdfDesign pdf(StatisticsPdfPalette palette) {
    return StatisticsPdfDesign(palette);
  }

  static BoxDecoration screenPanel(
    BuildContext context, {
    bool emphasized = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: emphasized
          ? cs.primaryContainer.withOpacity(0.45)
          : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration screenTocPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static Widget screenPill({
    required BuildContext context,
    required IconData icon,
    required String text,
    bool strong = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: strong ? cs.primaryContainer : cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: strong ? cs.onPrimaryContainer : cs.primary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: strong ? cs.onPrimaryContainer : null,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
