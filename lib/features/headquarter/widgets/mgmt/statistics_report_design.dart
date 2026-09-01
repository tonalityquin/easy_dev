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

enum StatisticsPdfMetricDensity { standard, compact }

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
      lineSpacing: 1.08,
    );
  }

  pw.TextStyle body({double size = 10, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? palette.ink,
      lineSpacing: 1.2,
    );
  }

  pw.TextStyle label({double size = 9, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? palette.muted,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: .12,
    );
  }

  pw.Widget divider({double top = 0, double bottom = 0, double width = .45}) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: top, bottom: bottom),
      child: pw.Container(height: width, color: palette.line),
    );
  }

  pw.Widget tag(StatisticsPdfTagData data) {
    final color = toneColor(data.tone);
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(width: 5, height: 5, color: color),
        pw.SizedBox(width: 5),
        pw.Text(data.label, style: label(size: 7.8, color: palette.muted)),
      ],
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
    final info = <MapEntry<String, String>>[
      if ((division ?? '').trim().isNotEmpty)
        MapEntry('사업부', division!.trim()),
      if ((area ?? '').trim().isNotEmpty) MapEntry('Area', area!.trim()),
      if ((rangeLabel ?? '').trim().isNotEmpty)
        MapEntry('조회 범위', rangeLabel!.trim()),
      MapEntry('생성 시각', _fmtDateTime(createdAt)),
    ];
    return pw.Container(
      color: palette.paper,
      padding: const pw.EdgeInsets.fromLTRB(38, 34, 38, 34),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('PARKINWORKIN', style: label(size: 8.6, color: palette.ink)),
              pw.Text(reportCode, style: label(size: 7.8, color: palette.muted)),
            ],
          ),
          divider(top: 13, bottom: 32, width: .7),
          pw.Text(titleText, style: title(size: 27)),
          pw.SizedBox(height: 9),
          pw.Text(subtitle, style: body(size: 10.6, color: palette.muted)),
          if ((description ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.only(left: 11),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(color: palette.primary, width: 2.2),
                ),
              ),
              child: pw.Text(
                description!.trim(),
                style: body(size: 9.2, color: palette.muted),
              ),
            ),
          ],
          if (tags.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Wrap(
              spacing: 13,
              runSpacing: 7,
              children: [for (final item in tags) tag(item)],
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Text('핵심 지표', style: label(size: 8, color: palette.muted)),
          pw.SizedBox(height: 7),
          divider(bottom: 1),
          metricGrid(metrics),
          pw.Spacer(),
          divider(bottom: 10),
          for (final entry in info)
            _keyValueRow(
              labelText: entry.key,
              valueText: entry.value,
              dense: true,
            ),
        ],
      ),
    );
  }

  pw.Widget metricGrid(
    List<StatisticsPdfMetricData> metrics, {
    StatisticsPdfMetricDensity density = StatisticsPdfMetricDensity.standard,
  }) {
    final compact = density == StatisticsPdfMetricDensity.compact;
    return pw.Column(
      children: [
        for (int index = 0; index < metrics.length; index++) ...[
          metricCard(metrics[index], density: density),
          if (index < metrics.length - 1)
            divider(width: compact ? .28 : .38),
        ],
      ],
    );
  }

  pw.Widget metricCard(
    StatisticsPdfMetricData data, {
    StatisticsPdfMetricDensity density = StatisticsPdfMetricDensity.standard,
  }) {
    final compact = density == StatisticsPdfMetricDensity.compact;
    final accent = toneColor(data.tone);
    final caption = (data.caption ?? '').trim();
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.symmetric(
        vertical: compact ? 6.2 : 8.5,
        horizontal: 1,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(width: 2.4, height: compact ? 26 : 32, color: accent),
          pw.SizedBox(width: compact ? 8 : 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.label,
                  style: label(size: compact ? 7.5 : 8.1, color: palette.muted),
                ),
                if (caption.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    caption,
                    style: body(size: compact ? 6.8 : 7.5, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            data.value,
            textAlign: pw.TextAlign.right,
            style: title(size: compact ? 12.5 : 16),
          ),
        ],
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
      padding: const pw.EdgeInsets.only(bottom: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.line, width: .45),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(reportTitle, style: label(size: 7.8, color: palette.ink)),
          if (meta.isNotEmpty)
            pw.Text(meta, style: body(size: 7.2, color: palette.muted)),
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
      padding: const pw.EdgeInsets.fromLTRB(0, 5, 0, 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.line, width: .6),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if ((sectionNumber ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(
              width: 34,
              child: pw.Text(
                sectionNumber!.trim(),
                style: title(size: 12, color: accent),
              ),
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if ((eyebrow ?? '').trim().isNotEmpty) ...[
                  pw.Text(
                    eyebrow!.trim(),
                    style: label(size: 7.2, color: accent),
                  ),
                  pw.SizedBox(height: 5),
                ],
                pw.Text(titleText, style: title(size: 18)),
                if ((subtitle ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    subtitle!.trim(),
                    style: body(size: 9, color: palette.muted),
                  ),
                ],
              ],
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
    final accent = toneColor(tone);
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.symmetric(vertical: padding * .45),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(width: 2.2, height: 28, color: accent),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(titleText, style: title(size: 11.8)),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2.5),
                      pw.Text(
                        subtitle!.trim(),
                        style: body(size: 8, color: palette.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if ((badge ?? '').trim().isNotEmpty)
                pw.Text(
                  badge!.trim(),
                  style: label(size: 7.3, color: palette.muted),
                ),
            ],
          ),
          pw.SizedBox(height: 9),
          child,
          divider(top: 8),
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
      padding: const pw.EdgeInsets.symmetric(vertical: 9),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.line, width: .38),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 2.6, height: details.isEmpty ? 34 : 48, color: accent),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(titleText, style: title(size: 10.8, color: accent)),
                pw.SizedBox(height: 3),
                pw.Text(message, style: body(size: 8.6)),
                for (final detail in details) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(detail, style: body(size: 7.5, color: palette.muted)),
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

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: palette.line, width: .28),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: palette.surfaceAlt),
          children: [
            for (int column = 0; column < headers.length; column++)
              cell(headers[column], column, header: true),
          ],
        ),
        for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
          pw.TableRow(
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
    );
  }

  pw.Widget listRow({
    required String titleText,
    String? subtitle,
    String? trailing,
    String? supporting,
    StatisticsPdfTone tone = StatisticsPdfTone.neutral,
    bool strong = false,
  }) {
    final accent = toneColor(tone);
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: palette.line, width: .36),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 2.2, height: strong ? 34 : 28, color: accent),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(titleText, style: title(size: strong ? 11 : 9.8)),
                if ((subtitle ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    subtitle!.trim(),
                    style: body(size: 7.8, color: palette.muted),
                  ),
                ],
                if ((supporting ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(supporting!.trim(), style: body(size: 8.2)),
                ],
              ],
            ),
          ),
          if ((trailing ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(width: 12),
            pw.Text(
              trailing!.trim(),
              textAlign: pw.TextAlign.right,
              style: title(size: strong ? 11.5 : 9.6),
            ),
          ],
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
      padding: const pw.EdgeInsets.only(top: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: palette.line, width: .45),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(labelText, style: label(size: 7)),
          pw.Text(
            '${_fmtDateTime(createdAt)}  ·  ${context.pageNumber} / ${context.pagesCount}',
            style: body(size: 7, color: palette.muted),
          ),
        ],
      ),
    );
  }

  pw.Widget _keyValueRow({
    required String labelText,
    required String valueText,
    bool dense = false,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: dense ? 3.2 : 5.5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 82,
            child: pw.Text(labelText, style: label(size: dense ? 7.4 : 8)),
          ),
          pw.Expanded(
            child: pw.Text(
              valueText,
              style: body(size: dense ? 8.3 : 9),
            ),
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
