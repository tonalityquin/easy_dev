import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

// ✅ 프로젝트 경로에 맞게 수정하세요.
import '../../../../../utils/google_auth_v7.dart';
import '../../../../../utils/api/email_config.dart';

class StatisticsChartPage extends StatefulWidget {
  final Map<DateTime, Map<String, int>> reportDataMap;

  const StatisticsChartPage({
    super.key,
    required this.reportDataMap,
  });

  @override
  State<StatisticsChartPage> createState() => _StatisticsChartPageState();
}

class _StatisticsChartPageState extends State<StatisticsChartPage> {
  bool showInput = true;
  bool showOutput = true;
  bool showLockedFeeChart = false;

  bool get _hasVehicleSeries => showInput || showOutput;

  // ✅ 메일 전송 UI
  final TextEditingController _mailSubjectCtrl = TextEditingController();
  final TextEditingController _mailBodyCtrl = TextEditingController();
  bool _sending = false;

  // ✅ 차트도 좌우 스크롤 지원을 위한 컨트롤러
  final ScrollController _chartHCtrl = ScrollController();

  // ✅ 포인트 1개당 차트 폭(픽셀)
  static const double _chartPointWidth = 56.0;

  // ✅ PDF에 넣을 차트 캡처(렌더 → PNG 추출)
  final GlobalKey _vehicleExportChartKey = GlobalKey();
  final GlobalKey _feeExportChartKey = GlobalKey();

  @override
  void dispose() {
    _chartHCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();
    super.dispose();
  }

  void _setChartMode(bool isFee) {
    setState(() => showLockedFeeChart = isFee);

    // 모드 변경 시 스크롤 위치 UX 보정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chartHCtrl.hasClients) _chartHCtrl.jumpTo(0);
    });
  }

  double _calcChartAreaHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final value = h * 0.46;
    // fl_chart(축/타이틀) 렌더 안정화를 위한 최소 높이 + UX 상한
    return value.clamp(300.0, 440.0);
  }

  // ✅ 차트 가로 스크롤 래퍼
  Widget _buildScrollableChartArea({
    Key? key,
    required Widget child,
    required int pointCount,
  }) {
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth;

        final desiredWidth = (pointCount * _chartPointWidth) + 24.0;
        final contentWidth = desiredWidth < minWidth ? minWidth : desiredWidth;

        final canScroll = contentWidth > minWidth + 1;

        return Scrollbar(
          controller: _chartHCtrl,
          thumbVisibility: canScroll,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _chartHCtrl,
            scrollDirection: Axis.horizontal,
            physics: canScroll ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: contentWidth,
              child: child,
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // ✅ 메일 전송: 제목/본문 입력 → PDF 생성 → Gmail 발신
  // ─────────────────────────────────────────────

  Future<void> _openMailDialogAndSend(_ChartModel model) async {
    HapticFeedback.selectionClick();

    if (model.sortedDates.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('통계 데이터가 최소 2개 이상 있어야 PDF 리포트를 생성할 수 있습니다.'),
        ),
      );
      return;
    }

    final draft = await showDialog<_MailDraft>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _MailComposeDialog(
        initialSubject: _mailSubjectCtrl.text.trim().isEmpty
            ? '통계 리포트 (${model.labels.first} ~ ${model.labels.last})'
            : _mailSubjectCtrl.text.trim(),
        initialBody: _mailBodyCtrl.text,
      ),
    );

    if (draft == null) return;

    _mailSubjectCtrl.text = draft.subject;
    _mailBodyCtrl.text = draft.body;

    await _sendStatsReport(model);
  }

  Future<void> _sendStatsReport(_ChartModel model) async {
    final subject = _mailSubjectCtrl.text.trim();
    final body = _mailBodyCtrl.text.trim();

    if (subject.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 제목을 입력해 주세요.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.'),
          ),
        );
        return;
      }
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      // ✅ Export 차트가 최신 상태로 페인트되도록 한 프레임 대기(안전장치)
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 16));

      // ✅ 차트 캡처(PNG) - "숨김 Export 차트"를 캡처한다는 점이 핵심
      final vehiclePng = await _capturePng(_vehicleExportChartKey);
      final feePng = await _capturePng(_feeExportChartKey);

      // ✅ PDF 생성
      final pdfBytes = await _buildStatsPdfBytes(
        model: model,
        vehicleChartPng: vehiclePng,
        feeChartPng: feePng,
      );

      // ✅ 파일명
      final now = DateTime.now();
      final filenameBase = _safeFileName('통계리포트_${_dateTag(now)}');
      final filename = '$filenameBase.pdf';

      // ✅ Gmail 발신
      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: filename,
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 전송 완료')),
      );
    } catch (e, st) {
      // ✅ 원인 추적용: 콘솔 스택 출력
      debugPrint('메일 전송 실패: $e');
      debugPrint('$st');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Uint8List> _capturePng(GlobalKey key, {double pixelRatio = 2.5}) async {
    // 페인트 완료 보장
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 16));

    final ctx = key.currentContext;
    if (ctx == null) {
      throw StateError('차트 캡처 실패: currentContext가 null 입니다.');
    }
    final ro = ctx.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw StateError('차트 캡처 실패: RenderRepaintBoundary를 찾지 못했습니다.');
    }

    final img = await ro.toImage(pixelRatio: pixelRatio);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose(); // 메모리 정리(가능한 Flutter 버전에서)

    if (byteData == null) {
      throw StateError('차트 캡처 실패: byteData가 null 입니다.');
    }
    return byteData.buffer.asUint8List();
  }

  // ─────────────────────────────────────────────
  // ✅ PDF 생성(통계표/설정/차트: 섹션별 새 페이지 시작)
  // ─────────────────────────────────────────────

  Future<Uint8List> _buildStatsPdfBytes({
    required _ChartModel model,
    required Uint8List vehicleChartPng,
    required Uint8List feeChartPng,
  }) async {
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

    final createdAt = DateTime.now();
    final doc = pw.Document();

    pw.Widget header(String title, {String? subtitle}) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Divider(color: PdfColors.grey400, thickness: 0.7),
        ],
      );
    }

    pw.Widget footer(pw.Context ctx) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '생성 시각: ${_fmtCompact(createdAt)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      );
    }

    // ✅ 커버/요약 페이지
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        footer: footer,
        build: (ctx) {
          final sumIn = model.dailyStats.fold<int>(0, (p, e) => p + e.input);
          final sumOut = model.dailyStats.fold<int>(0, (p, e) => p + e.output);
          final sumFee = model.dailyStats.fold<int>(0, (p, e) => p + e.fee);

          final avgIn = model.dailyStats.isEmpty ? 0 : (sumIn / model.dailyStats.length).round();
          final avgOut = model.dailyStats.isEmpty ? 0 : (sumOut / model.dailyStats.length).round();
          final avgFee = model.dailyStats.isEmpty ? 0 : (sumFee / model.dailyStats.length).round();

          final range = '${model.labels.first} ~ ${model.labels.last}';
          final modeText = showLockedFeeChart ? '정산금' : '입·출차';

          return [
            pw.Center(
              child: pw.Text(
                '통계 리포트',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                range,
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey800),
              ),
            ),
            pw.SizedBox(height: 18),
            header('요약'),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('데이터 일수: ${model.dailyStats.length}일', style: const pw.TextStyle(fontSize: 11)),
                  pw.SizedBox(height: 6),
                  pw.Text('입차 합계: ${_fmt(sumIn)} / 평균: ${_fmt(avgIn)}', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('출차 합계: ${_fmt(sumOut)} / 평균: ${_fmt(avgOut)}', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('정산금 합계: ₩${_fmt(sumFee)} / 평균: ₩${_fmt(avgFee)}', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            header('내보내기 설정(현재 화면 기준)'),
            pw.Bullet(text: '차트 모드: $modeText'),
            pw.Bullet(text: '입차 표시: ${showInput ? "ON" : "OFF"}'),
            pw.Bullet(text: '출차 표시: ${showOutput ? "ON" : "OFF"}'),
            pw.SizedBox(height: 10),
            pw.Text(
              '다음 페이지부터: 입차 통계표 / 출차 통계표 / 정산금 통계표 / 차트 설정 / 입·출차 그래프 / 정산금 그래프 순으로 구성됩니다.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
            ),
          ];
        },
      ),
    );

    void addTableSection({
      required String title,
      required String valueHeader,
      required List<List<String>> rows,
    }) {
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
          footer: footer,
          build: (ctx) => [
            header(title),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['날짜', valueHeader],
              data: rows,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(6),
                1: pw.FlexColumnWidth(4),
              },
              cellAlignments: const {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
            ),
          ],
        ),
      );
    }

    addTableSection(
      title: '입차 통계표',
      valueHeader: '대수',
      rows: [
        for (final d in model.dailyStats) [_dateOnly(d.date), _fmt(d.input)],
      ],
    );

    addTableSection(
      title: '출차 통계표',
      valueHeader: '대수',
      rows: [
        for (final d in model.dailyStats) [_dateOnly(d.date), _fmt(d.output)],
      ],
    );

    addTableSection(
      title: '정산금 통계표',
      valueHeader: '정산금',
      rows: [
        for (final d in model.dailyStats) [_dateOnly(d.date), '₩${_fmt(d.fee)}'],
      ],
    );

    // ✅ 차트 설정 1페이지
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        footer: footer,
        build: (ctx) {
          final modeText = showLockedFeeChart ? '정산금' : '입·출차';
          return [
            header('차트 설정(현재 화면 상태)'),
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('차트 모드: $modeText', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 6),
                  pw.Text('입차 표시: ${showInput ? "ON" : "OFF"}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('출차 표시: ${showOutput ? "ON" : "OFF"}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    '참고: 아래 그래프 페이지는 PDF 내보내기용으로 렌더링된 결과(툴팁/스크롤 제외)입니다.',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    // ✅ 차트(입·출차) 1페이지
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        footer: footer,
        build: (ctx) => [
          header('입·출차 그래프'),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Image(
              pw.MemoryImage(vehicleChartPng),
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
      ),
    );

    // ✅ 차트(정산금) 1페이지
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        footer: footer,
        build: (ctx) => [
          header('정산금 그래프'),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Image(
              pw.MemoryImage(feeChartPng),
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
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

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '통계리포트' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _dateTag(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  // ─────────────────────────────────────────────
  // ✅ PDF Export 차트 레이어(“숨김 but painted”)
  // ─────────────────────────────────────────────

  Widget _buildExportPlaceholder(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildHiddenExportCharts(_ChartModel model) {
    const double w = 920;
    const double h = 420;

    Widget frame({required Widget child}) {
      return Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      );
    }

    // ✅ (중요) 입/출차 둘 다 OFF면 Export 차트에서 lineBarsData가 빈 리스트가 될 수 있어
    // fl_chart 내부에서 null 단언 크래시가 날 수 있으므로 플레이스홀더를 렌더링한다.
    final vehicleExportChild = _hasVehicleSeries
        ? LineChart(
      _buildVehicleExportChartData(
        model.inSpots,
        model.outSpots,
        model.labels,
      ),
    )
        : _buildExportPlaceholder('입·출차 그래프\n표시할 항목이 없습니다.\n(입차/출차 중 하나 이상 선택)');

    return IgnorePointer(
      child: Opacity(
        // ✅ (중요) 0.0이면 paint 자체가 스킵될 수 있어 RepaintBoundary.toImage()에서 크래시가 날 수 있음
        opacity: 0.01,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: UnconstrainedBox(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _vehicleExportChartKey,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: frame(child: vehicleExportChild),
                  ),
                ),
                const SizedBox(height: 24),
                RepaintBoundary(
                  key: _feeExportChartKey,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: frame(
                      child: LineChart(
                        _buildFeeExportChartData(
                          model.feeSpots,
                          model.labels,
                        ),
                      ),
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

  // ─────────────────────────────────────────────
  // ✅ AppBar: 겹침 방지 + 뒤로가기 제거 + 제목 검정
  // ─────────────────────────────────────────────

  Widget _buildSendActionButton({
    required BuildContext context,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;

    final bg = _sending ? cs.surfaceContainerHighest : cs.primaryContainer;
    final fg = _sending ? cs.onSurfaceVariant : cs.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: _sending ? null : onPressed,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sending)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              else
                Icon(Icons.send_outlined, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                'PDF 발신',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBarBottom({
    required BuildContext context,
    required _ChartModel model,
    required String rangeText,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasRange = model.sortedDates.length >= 2;

    final chips = <Widget>[
      _HeaderChip(
        icon: Icons.date_range_rounded,
        text: rangeText,
      ),
      _HeaderChip(
        icon: Icons.dataset_rounded,
        text: '${model.dailyStats.length}일',
      ),
    ];

    // ✅ Wrap 대신 가로 스크롤(Row)로 고정 높이 유지
    return PreferredSize(
      preferredSize: const Size.fromHeight(54),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: hasRange
              ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                ...List.generate(chips.length, (i) {
                  return Padding(
                    padding: EdgeInsets.only(right: i == chips.length - 1 ? 0 : 8),
                    child: chips[i],
                  );
                }),
              ],
            ),
          )
              : Text(
            '데이터 부족',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar({
    required BuildContext context,
    required _ChartModel model,
    required String rangeText,
  }) {
    final cs = Theme.of(context).colorScheme;

    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: false, // ✅ 뒤로가기 제거
      backgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      elevation: 0,
      foregroundColor: Colors.black, // ✅ AppBar 글자/아이콘 검정
      title: const Text(
        '통계 그래프',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
      actions: [
        _buildSendActionButton(
          context: context,
          onPressed: () => _openMailDialogAndSend(model),
        ),
      ],
      bottom: _buildAppBarBottom(
        context: context,
        model: model,
        rangeText: rangeText,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final model = _ChartModel.from(widget.reportDataMap);

    final hasEnoughData = model.sortedDates.length >= 2;
    final rangeText = hasEnoughData ? '${model.labels.first} ~ ${model.labels.last}' : '데이터 부족';

    final chartHeight = _calcChartAreaHeight(context);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(
                context: context,
                model: model,
                rangeText: rangeText,
              ),

              if (!hasEnoughData)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: const _ModernEmptyState(
                          title: '그래프를 만들 데이터가 부족합니다.',
                          message: '통계 데이터가 최소 2개 이상 있어야 추이를 그래프로 표시할 수 있습니다.',
                          icon: Icons.show_chart_rounded,
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                // ✅ 상단 패널(통계표 + 차트 설정)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: _TopPanel(
                          dailyStats: model.dailyStats,
                          showLockedFeeChart: showLockedFeeChart,
                          onToggleMode: _setChartMode,
                          showInput: showInput,
                          showOutput: showOutput,
                          onToggleInput: (v) => setState(() => showInput = v),
                          onToggleOutput: (v) => setState(() => showOutput = v),
                        ),
                      ),
                    ),
                  ),
                ),

                // ✅ 하단: 그래프 (고정 높이로 최소 크기 보장)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: SizedBox(
                          height: chartHeight,
                          child: _ChartCard(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeOut,
                                  child: showLockedFeeChart
                                      ? _buildScrollableChartArea(
                                    key: const ValueKey('scrollFee'),
                                    pointCount: model.labels.length,
                                    child: LineChart(
                                      _buildFeeChartData(model.feeSpots, model.labels),
                                      key: const ValueKey('feeChart'),
                                    ),
                                  )
                                      : _buildScrollableChartArea(
                                    key: const ValueKey('scrollVehicle'),
                                    pointCount: model.labels.length,
                                    child: _buildVehicleChartOrEmpty(
                                      model.inSpots,
                                      model.outSpots,
                                      model.labels,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ✅ PDF Export용 “숨김 but painted” 차트(항상 렌더링)
          _buildHiddenExportCharts(model),
        ],
      ),
    );
  }

  Widget _buildVehicleChartOrEmpty(
      List<FlSpot> inSpots,
      List<FlSpot> outSpots,
      List<String> labels,
      ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!showInput && !showOutput) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_off_rounded, color: cs.outline, size: 40),
              const SizedBox(height: 10),
              Text(
                '표시할 항목이 없습니다.',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '상단에서 입차/출차 항목을 하나 이상 선택해 주세요.',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LineChart(
      _buildInputOutputChartData(inSpots, outSpots, labels),
      key: const ValueKey('vehicleChart'),
    );
  }

  // ===== ChartData 구성 (화면용) =====

  LineChartData _buildInputOutputChartData(
      List<FlSpot> inSpots,
      List<FlSpot> outSpots,
      List<String> labels,
      ) {
    return LineChartData(
      titlesData: _buildTitlesData(labels),
      gridData: _buildGrid(),
      borderData: _buildBorder(),
      minY: 0,
      maxY: _calculateMaxY([
        if (showInput) ...inSpots,
        if (showOutput) ...outSpots,
      ]),
      lineBarsData: [
        if (showInput)
          LineChartBarData(
            spots: inSpots,
            isCurved: true,
            color: Colors.blue,
            dotData: FlDotData(show: true),
            barWidth: 3,
            belowBarData: BarAreaData(show: false),
          ),
        if (showOutput)
          LineChartBarData(
            spots: outSpots,
            isCurved: true,
            color: Colors.red,
            dotData: FlDotData(show: true),
            barWidth: 3,
            belowBarData: BarAreaData(show: false),
          ),
      ],
      lineTouchData: _buildTouchData(labels, type: 'vehicle'),
    );
  }

  LineChartData _buildFeeChartData(List<FlSpot> feeSpots, List<String> labels) {
    return LineChartData(
      titlesData: _buildTitlesData(labels),
      gridData: _buildGrid(),
      borderData: _buildBorder(),
      minY: 0,
      maxY: _calculateMaxY(feeSpots),
      lineBarsData: [
        LineChartBarData(
          spots: feeSpots,
          isCurved: true,
          color: Colors.green,
          dotData: FlDotData(show: true),
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      ],
      lineTouchData: _buildTouchData(labels, type: 'fee'),
    );
  }

  /// ✅ PDF Export용 차트(툴팁/스크롤/토글 영향 최소화)
  LineChartData _buildVehicleExportChartData(
      List<FlSpot> inSpots,
      List<FlSpot> outSpots,
      List<String> labels,
      ) {
    final bars = <LineChartBarData>[];

    if (showInput) {
      bars.add(
        LineChartBarData(
          spots: inSpots,
          isCurved: true,
          color: Colors.blue,
          dotData: FlDotData(show: false),
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      );
    }
    if (showOutput) {
      bars.add(
        LineChartBarData(
          spots: outSpots,
          isCurved: true,
          color: Colors.red,
          dotData: FlDotData(show: false),
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    return LineChartData(
      titlesData: _buildTitlesData(labels),
      gridData: _buildGrid(),
      borderData: _buildBorder(),
      minY: 0,
      maxY: _calculateMaxY([
        if (showInput) ...inSpots,
        if (showOutput) ...outSpots,
      ]),
      lineBarsData: bars,
      lineTouchData: LineTouchData(enabled: false),
    );
  }

  LineChartData _buildFeeExportChartData(
      List<FlSpot> feeSpots,
      List<String> labels,
      ) {
    return LineChartData(
      titlesData: _buildTitlesData(labels),
      gridData: _buildGrid(),
      borderData: _buildBorder(),
      minY: 0,
      maxY: _calculateMaxY(feeSpots),
      lineBarsData: [
        LineChartBarData(
          spots: feeSpots,
          isCurved: true,
          color: Colors.green,
          dotData: FlDotData(show: false),
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      ],
      lineTouchData: LineTouchData(enabled: false),
    );
  }

  /// ✅ 하단 날짜 겹침 방지(샘플링)
  FlTitlesData _buildTitlesData(List<String> labels) {
    final step = _axisLabelStep(labels.length, maxLabels: 7);

    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: null,
          getTitlesWidget: (value, _) => Text(
            value.toInt().toString(),
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 34,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= labels.length) {
              return const SizedBox.shrink();
            }

            final isFirst = index == 0;
            final isLast = index == labels.length - 1;
            final shouldShow = isFirst || isLast || (index % step == 0);

            if (!shouldShow) return const SizedBox.shrink();

            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 6,
              child: Text(
                labels[index].substring(5), // MM-DD
                style: const TextStyle(fontSize: 10),
              ),
            );
          },
        ),
      ),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  FlGridData _buildGrid() => FlGridData(
    show: true,
    drawVerticalLine: true,
    drawHorizontalLine: true,
    getDrawingHorizontalLine: (value) => FlLine(
      color: Colors.grey.withOpacity(0.2),
      strokeWidth: 1,
    ),
    getDrawingVerticalLine: (value) => FlLine(
      color: Colors.grey.withOpacity(0.2),
      strokeWidth: 1,
    ),
  );

  FlBorderData _buildBorder() => FlBorderData(
    show: true,
    border: const Border(
      left: BorderSide(color: Colors.black),
      bottom: BorderSide(color: Colors.black),
    ),
  );

  /// ✅ Tooltip 잘림 방지
  LineTouchData _buildTouchData(List<String> labels, {required String type}) {
    return LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        tooltipBgColor: Colors.black87,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        tooltipMargin: 10,
        getTooltipItems: (spots) {
          return spots.map((spot) {
            final x = spot.x.toInt();
            final label = (x >= 0 && x < labels.length) ? labels[x] : '';
            final value = spot.y.toInt();
            final series = (type == 'fee') ? '정산금' : (spot.bar.color == Colors.blue ? '입차' : '출차');

            return LineTooltipItem(
              '$label\n$series: ${type == 'fee' ? '₩' : ''}$value',
              const TextStyle(color: Colors.white),
            );
          }).toList();
        },
      ),
    );
  }

  double _calculateMaxY(List<FlSpot> spots) {
    if (spots.isEmpty) return 10;
    final maxY = spots.map((e) => e.y).fold<double>(0, (prev, e) => e > prev ? e : prev);
    final v = (maxY * 1.3).ceilToDouble();
    return v <= 0 ? 10 : v;
  }
}

// ─────────────────────────────────────────────
// ✅ 상단 패널: 통계표(카드 3개) + 차트 설정
// ─────────────────────────────────────────────

class _TopPanel extends StatelessWidget {
  final List<_DailyStat> dailyStats;

  final bool showLockedFeeChart;
  final ValueChanged<bool> onToggleMode;

  final bool showInput;
  final bool showOutput;
  final ValueChanged<bool> onToggleInput;
  final ValueChanged<bool> onToggleOutput;

  const _TopPanel({
    required this.dailyStats,
    required this.showLockedFeeChart,
    required this.onToggleMode,
    required this.showInput,
    required this.showOutput,
    required this.onToggleInput,
    required this.onToggleOutput,
  });

  double _calcTopTablesHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final value = h * 0.42;
    if (value < 320) return 320;
    if (value > 440) return 440;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tablesHeight = _calcTopTablesHeight(context);

    return Column(
      children: [
        SizedBox(
          height: tablesHeight,
          child: _StatsTableCarousel(dailyStats: dailyStats),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '차트 설정',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('입·출차'),
                      icon: Icon(Icons.directions_car_filled_rounded),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('정산금'),
                      icon: Icon(Icons.payments_rounded),
                    ),
                  ],
                  selected: <bool>{showLockedFeeChart},
                  showSelectedIcon: false,
                  onSelectionChanged: (set) {
                    if (set.isEmpty) return;
                    onToggleMode(set.first);
                  },
                ),
                const SizedBox(height: 12),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: showLockedFeeChart ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilterChip(
                          selected: showInput,
                          onSelected: onToggleInput,
                          label: const Text('입차'),
                          avatar: const Icon(Icons.directions_car_rounded, color: Colors.blue),
                          showCheckmark: false,
                        ),
                        FilterChip(
                          selected: showOutput,
                          onSelected: onToggleOutput,
                          label: const Text('출차'),
                          avatar: const Icon(Icons.exit_to_app_rounded, color: Colors.red),
                          showCheckmark: false,
                        ),
                      ],
                    ),
                  ),
                  secondChild: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '정산금 모드에서는 단일 그래프만 표시됩니다.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _StatTableKind { input, output, fee }

class _StatsTableCarousel extends StatefulWidget {
  final List<_DailyStat> dailyStats;

  const _StatsTableCarousel({
    required this.dailyStats,
  });

  @override
  State<_StatsTableCarousel> createState() => _StatsTableCarouselState();
}

class _StatsTableCarouselState extends State<_StatsTableCarousel> {
  late final PageController _pageCtrl;
  int _index = 0;

  static const _items = <_StatTableKind>[
    _StatTableKind.input,
    _StatTableKind.output,
    _StatTableKind.fee,
  ];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final kind = _items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _ChartCard(
                  child: _StatisticsTableView(
                    kind: kind,
                    dailyStats: widget.dailyStats,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_items.length, (i) {
            final active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 8,
              width: active ? 18 : 8,
              decoration: BoxDecoration(
                color: active ? cs.primary : cs.outlineVariant.withOpacity(0.9),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ✅ 통계표(카드) 뷰
// ─────────────────────────────────────────────

enum _TableSortField { date, value }

class _StatisticsTableView extends StatefulWidget {
  final _StatTableKind kind;
  final List<_DailyStat> dailyStats;

  const _StatisticsTableView({
    required this.kind,
    required this.dailyStats,
  });

  @override
  State<_StatisticsTableView> createState() => _StatisticsTableViewState();
}

class _StatisticsTableViewState extends State<_StatisticsTableView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _vCtrl = ScrollController();

  String _query = '';
  int _quickDays = 0;

  _TableSortField _sortField = _TableSortField.date;
  bool _ascending = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  String _title() {
    switch (widget.kind) {
      case _StatTableKind.input:
        return '입차 통계표';
      case _StatTableKind.output:
        return '출차 통계표';
      case _StatTableKind.fee:
        return '정산금 통계표';
    }
  }

  IconData _icon() {
    switch (widget.kind) {
      case _StatTableKind.input:
        return Icons.directions_car_rounded;
      case _StatTableKind.output:
        return Icons.exit_to_app_rounded;
      case _StatTableKind.fee:
        return Icons.payments_rounded;
    }
  }

  Color _accentColor() {
    switch (widget.kind) {
      case _StatTableKind.input:
        return Colors.blue;
      case _StatTableKind.output:
        return Colors.red;
      case _StatTableKind.fee:
        return Colors.green;
    }
  }

  int _valueOf(_DailyStat d) {
    switch (widget.kind) {
      case _StatTableKind.input:
        return d.input;
      case _StatTableKind.output:
        return d.output;
      case _StatTableKind.fee:
        return d.fee;
    }
  }

  String _valueText(int v) {
    switch (widget.kind) {
      case _StatTableKind.fee:
        return '₩${_fmt(v)}';
      case _StatTableKind.input:
      case _StatTableKind.output:
        return _fmt(v);
    }
  }

  List<_DailyStat> _filtered() {
    final all = widget.dailyStats;
    if (all.isEmpty) return [];

    Iterable<_DailyStat> it = all;

    // 최근 N일: "데이터 마지막 날짜" 기준
    if (_quickDays > 0) {
      final last = all.last.date;
      final cutoff = last.subtract(Duration(days: _quickDays - 1));
      it = it.where((e) => !e.date.isBefore(cutoff));
    }

    // 검색: yyyy-mm / yyyy-mm-dd 부분검색
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((e) => _dateOnly(e.date).toLowerCase().contains(q));
    }

    final list = it.toList();

    // 정렬
    list.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _TableSortField.date:
          cmp = a.date.compareTo(b.date);
          break;
        case _TableSortField.value:
          cmp = _valueOf(a).compareTo(_valueOf(b));
          break;
      }
      return _ascending ? cmp : -cmp;
    });

    return list;
  }

  void _toggleSort(_TableSortField field) {
    setState(() {
      if (_sortField == field) {
        _ascending = !_ascending;
      } else {
        _sortField = field;
        _ascending = false;
      }
    });
  }

  _MinMax<_DailyStat> _computeMinMax(List<_DailyStat> items) {
    if (items.isEmpty) return const _MinMax(null, null);

    _DailyStat minD = items.first;
    _DailyStat maxD = items.first;

    for (final d in items) {
      final v = _valueOf(d);
      if (v < _valueOf(minD)) minD = d;
      if (v > _valueOf(maxD)) maxD = d;
    }
    return _MinMax(minD, maxD);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final items = _filtered();
    final mm = _computeMinMax(items);

    int sum = 0;
    for (final d in items) {
      sum += _valueOf(d);
    }
    final avg = items.isEmpty ? 0 : (sum / items.length).round();

    return CustomScrollView(
      controller: _vCtrl,
      primary: false,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(_icon(), color: _accentColor()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _title(),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _Pill(
                      text: _quickDays == 0 ? '전체' : '최근 $_quickDays일',
                      icon: Icons.calendar_month_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '날짜 검색 (예: 2025-12 / 2025-12-13)',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(Icons.clear_rounded),
                          ),
                          filled: true,
                          fillColor: cs.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: cs.primary.withOpacity(0.9),
                              width: 1.2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<int>(
                      tooltip: '빠른 필터',
                      onSelected: (v) => setState(() => _quickDays = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 0, child: Text('전체')),
                        PopupMenuItem(value: 7, child: Text('최근 7일')),
                        PopupMenuItem(value: 30, child: Text('최근 30일')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 18),
                            SizedBox(width: 8),
                            Icon(Icons.expand_more_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Pill(
                        text: '${items.length}일',
                        icon: Icons.event_note_rounded,
                      ),
                      _MiniPill(
                        label: '합계',
                        value: _valueText(sum),
                        icon: _icon(),
                        color: _accentColor(),
                      ),
                      _MiniPill(
                        label: '평균',
                        value: _valueText(avg),
                        icon: Icons.functions_rounded,
                        color: cs.primary,
                      ),
                      if (mm.max != null)
                        _MiniPill(
                          label: 'MAX',
                          value: _valueText(_valueOf(mm.max!)),
                          icon: Icons.trending_up_rounded,
                          color: _accentColor(),
                        ),
                      if (mm.min != null)
                        _MiniPill(
                          label: 'MIN',
                          value: _valueText(_valueOf(mm.min!)),
                          icon: Icons.trending_down_rounded,
                          color: _accentColor(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _MetricTableHeader(
                  kind: widget.kind,
                  sortField: _sortField,
                  ascending: _ascending,
                  onTapDate: () => _toggleSort(_TableSortField.date),
                  onTapValue: () => _toggleSort(_TableSortField.value),
                  valueTitle: widget.kind == _StatTableKind.fee ? '정산금' : '대수',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_rounded, color: cs.outline, size: 44),
                    const SizedBox(height: 10),
                    Text(
                      '표시할 데이터가 없습니다.',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '검색어 또는 필터 조건을 변경해 보세요.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final d = items[index];
                  final isMax = mm.max != null && identical(d, mm.max);
                  final isMin = mm.min != null && identical(d, mm.min);

                  return Padding(
                    padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 8),
                    child: _MetricTableRowCard(
                      kind: widget.kind,
                      daily: d,
                      value: _valueOf(d),
                      valueText: _valueText(_valueOf(d)),
                      isMax: isMax,
                      isMin: isMin,
                      accent: _accentColor(),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricTableHeader extends StatelessWidget {
  final _StatTableKind kind;
  final _TableSortField sortField;
  final bool ascending;

  final VoidCallback onTapDate;
  final VoidCallback onTapValue;

  final String valueTitle;

  const _MetricTableHeader({
    required this.kind,
    required this.sortField,
    required this.ascending,
    required this.onTapDate,
    required this.onTapValue,
    required this.valueTitle,
  });

  Widget _title(
      BuildContext context, {
        required String text,
        required bool active,
        required VoidCallback onTap,
        TextAlign align = TextAlign.left,
        int flex = 1,
      }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Expanded(
      flex: flex,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  text,
                  textAlign: align,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: active ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 16,
                  color: cs.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          _title(
            context,
            text: '날짜',
            active: sortField == _TableSortField.date,
            onTap: onTapDate,
            align: TextAlign.left,
            flex: 6,
          ),
          _title(
            context,
            text: valueTitle,
            active: sortField == _TableSortField.value,
            onTap: onTapValue,
            align: TextAlign.right,
            flex: 4,
          ),
        ],
      ),
    );
  }
}

class _MetricTableRowCard extends StatelessWidget {
  final _StatTableKind kind;
  final _DailyStat daily;
  final int value;
  final String valueText;
  final bool isMax;
  final bool isMin;
  final Color accent;

  const _MetricTableRowCard({
    required this.kind,
    required this.daily,
    required this.value,
    required this.valueText,
    required this.isMax,
    required this.isMin,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateOnly(daily.date),
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isMax) _BadgePill(text: 'MAX', color: accent),
                    if (isMin) _BadgePill(text: 'MIN', color: accent),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                valueText,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공용 카드 / 빈 상태 / 헤더 칩
// ─────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final Widget child;

  const _ChartCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ModernEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _ModernEmptyState({
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Pill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  final Color color;

  const _BadgePill({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Models + Helpers
// ─────────────────────────────────────────────

class _DailyStat {
  final DateTime date;
  final int input;
  final int output;
  final int fee;

  const _DailyStat({
    required this.date,
    required this.input,
    required this.output,
    required this.fee,
  });
}

class _MinMax<T> {
  final T? min;
  final T? max;
  const _MinMax(this.min, this.max);
}

class _ChartModel {
  final List<DateTime> sortedDates;
  final List<String> labels;
  final List<FlSpot> inSpots;
  final List<FlSpot> outSpots;
  final List<FlSpot> feeSpots;
  final List<_DailyStat> dailyStats;

  const _ChartModel({
    required this.sortedDates,
    required this.labels,
    required this.inSpots,
    required this.outSpots,
    required this.feeSpots,
    required this.dailyStats,
  });

  factory _ChartModel.from(Map<DateTime, Map<String, int>> reportDataMap) {
    final sortedDates = reportDataMap.keys.toList()..sort();
    final labels = sortedDates.map((d) => _dateOnly(d)).toList();

    final inSpots = <FlSpot>[];
    final outSpots = <FlSpot>[];
    final feeSpots = <FlSpot>[];
    final dailyStats = <_DailyStat>[];

    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final counts = reportDataMap[date] ?? {};

      final inCount = counts['vehicleInput'] ?? counts['입차'] ?? 0;
      final outCount = counts['vehicleOutput'] ?? counts['출차'] ?? 0;
      final fee = counts['totalLockedFee'] ?? counts['정산금'] ?? 0;

      inSpots.add(FlSpot(i.toDouble(), (inCount as num).toDouble()));
      outSpots.add(FlSpot(i.toDouble(), (outCount as num).toDouble()));
      feeSpots.add(FlSpot(i.toDouble(), (fee as num).toDouble()));

      dailyStats.add(_DailyStat(date: date, input: inCount, output: outCount, fee: fee));
    }

    return _ChartModel(
      sortedDates: sortedDates,
      labels: labels,
      inSpots: inSpots,
      outSpots: outSpots,
      feeSpots: feeSpots,
      dailyStats: dailyStats,
    );
  }
}

String _dateOnly(DateTime dt) => dt.toIso8601String().split('T').first;

/// ✅ 천 단위 콤마(음수 대응 포함)
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

/// ✅ 라벨 샘플링 스텝 계산(최대 maxLabels개 수준으로 표시)
int _axisLabelStep(int len, {int maxLabels = 7}) {
  if (len <= 0) return 1;
  if (len <= maxLabels) return 1;
  final step = (len / maxLabels).ceil();
  return step < 1 ? 1 : step;
}

// ─────────────────────────────────────────────
// ✅ 메일 작성 다이얼로그(제목/본문)
// ─────────────────────────────────────────────

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
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
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
            final subject = _subjectCtrl.text.trim();
            final body = _bodyCtrl.text;
            Navigator.of(context).pop(_MailDraft(subject: subject, body: body));
          },
          icon: const Icon(Icons.send_outlined),
          label: const Text('발신'),
        ),
      ],
    );
  }
}
