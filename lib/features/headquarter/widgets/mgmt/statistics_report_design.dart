import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class StatisticsReportDesign {
  static const double radius = 28;
  static const double cardPadding = 18;
  static const PdfColor pdfInk = PdfColor.fromInt(0xff111827);
  static const PdfColor pdfMuted = PdfColor.fromInt(0xff6b7280);
  static const PdfColor pdfLine = PdfColor.fromInt(0xffd1d5db);
  static const PdfColor pdfSoft = PdfColor.fromInt(0xfff3f4f6);
  static const PdfColor pdfAccent = PdfColor.fromInt(0xff1d4ed8);
  static const PdfColor pdfAccentSoft = PdfColor.fromInt(0xffdbeafe);

  static BoxDecoration screenPanel(BuildContext context, {bool emphasized = false}) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: emphasized ? cs.primaryContainer.withOpacity(0.45) : cs.surfaceContainerHighest,
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
          Icon(icon, size: 16, color: strong ? cs.onPrimaryContainer : cs.primary),
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

  static pw.TextStyle pdfTitle({double size = 22}) {
    return pw.TextStyle(
      fontSize: size,
      color: pdfInk,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static pw.TextStyle pdfBody({double size = 10, PdfColor color = pdfInk}) {
    return pw.TextStyle(fontSize: size, color: color);
  }

  static pw.TextStyle pdfLabel({double size = 9}) {
    return pw.TextStyle(
      fontSize: size,
      color: pdfMuted,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static pw.BoxDecoration pdfCard({PdfColor fill = PdfColors.white}) {
    return pw.BoxDecoration(
      color: fill,
      border: pw.Border.all(color: pdfLine, width: 0.7),
      borderRadius: pw.BorderRadius.circular(12),
    );
  }

  static pw.Widget pdfSectionHeader({
    required String title,
    String? subtitle,
    String? eyebrow,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(0, 0, 0, 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: pdfLine, width: 0.8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (eyebrow != null && eyebrow.trim().isNotEmpty) ...[
            pw.Text(eyebrow, style: pdfLabel(size: 8.5)),
            pw.SizedBox(height: 4),
          ],
          pw.Text(title, style: pdfTitle(size: 18)),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: pdfBody(size: 10, color: pdfMuted)),
          ],
        ],
      ),
    );
  }

  static pw.Widget pdfMetricCard({
    required String label,
    required String value,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pdfCard(fill: pdfSoft),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pdfLabel()),
            pw.SizedBox(height: 5),
            pw.Text(value, style: pdfTitle(size: 13)),
          ],
        ),
      ),
    );
  }

  static pw.Widget pdfFooter({
    required pw.Context context,
    required DateTime createdAt,
    required String label,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: pdfLine, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pdfBody(size: 8, color: pdfMuted)),
          pw.Text(
            '${_fmtDateTime(createdAt)} · ${context.pageNumber} / ${context.pagesCount}',
            style: pdfBody(size: 8, color: pdfMuted),
          ),
        ],
      ),
    );
  }

  static String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
