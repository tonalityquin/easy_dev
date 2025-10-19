// lib/screens/head_package/labors/statement_form_page.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

// ✅ v7 호환 레이어(전역 세션에서 AuthClient 재사용)
import '../../../utils/google_auth_v7.dart';
// ✅ 수신자(To)만 저장소에서 로드
import '../../../utils/email_config.dart';

class StatementFormPage extends StatefulWidget {
  const StatementFormPage({super.key});

  @override
  State<StatementFormPage> createState() => _StatementFormPageState();
}

class _StatementFormPageState extends State<StatementFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 본문 입력 컨트롤러들
  final _writerCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _peopleCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();
  final _preventionCtrl = TextEditingController();

  // ✉️ 메일 제목/본문(이 화면에서 직접 작성)
  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  DateTime? _eventDateTime;

  // FocusNodes
  final _writerNode = FocusNode();
  final _deptNode = FocusNode();
  final _contactNode = FocusNode();
  final _placeNode = FocusNode();
  final _peopleNode = FocusNode();
  final _detailNode = FocusNode();
  final _preventionNode = FocusNode();

  // 전자서명 상태
  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;
  String get _signerName => _writerCtrl.text.trim();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _writerCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _writerCtrl.dispose();
    _deptCtrl.dispose();
    _contactCtrl.dispose();
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    _peopleCtrl.dispose();
    _detailCtrl.dispose();
    _preventionCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _writerNode.dispose();
    _deptNode.dispose();
    _contactNode.dispose();
    _placeNode.dispose();
    _peopleNode.dispose();
    _detailNode.dispose();
    _preventionNode.dispose();
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

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _eventDateTime ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventDateTime ?? now),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || time == null) return;
    setState(() {
      _eventDateTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _reset() {
    _formKey.currentState?.reset();
    _writerCtrl.clear();
    _deptCtrl.clear();
    _contactCtrl.clear();
    _titleCtrl.clear();
    _placeCtrl.clear();
    _peopleCtrl.clear();
    _detailCtrl.clear();
    _preventionCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    setState(() {
      _eventDateTime = null;
      _signaturePngBytes = null;
      _signDateTime = null;
    });
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';
    return [
      '— 경위서 —',
      '',
      '제목: ${_titleCtrl.text}',
      '작성자: ${_writerCtrl.text}',
      '소속/직위: ${_deptCtrl.text}',
      '연락처: ${_contactCtrl.text}',
      '사건 발생 일시: ${_fmtDT(context, _eventDateTime)}',
      '장소: ${_placeCtrl.text}',
      '관련자: ${_peopleCtrl.text}',
      '',
      '[경위 상세]',
      _detailCtrl.text,
      '',
      '[재발 방지 대책]',
      _preventionCtrl.text,
      '',
      signInfo,
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showPreview() async {
    final text = _buildPreviewText(context);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('미리보기'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(text),
                const SizedBox(height: 12),
                if (_signaturePngBytes != null) ...[
                  const Text('서명 이미지'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.memory(
                      _signaturePngBytes!,
                      fit: BoxFit.contain,
                      height: 160,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('텍스트가 클립보드에 복사되었습니다.')),
              );
            },
            child: const Text('텍스트 복사'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _sending = true);
    try {
      // ① 저장된 수신자(To) 로드 및 검증
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.')),
        );
        return;
      }
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      // ② 이 화면에서 입력한 메일 제목/본문 확보(제목 필수)
      final subject = _mailSubjectCtrl.text.trim();
      final body = _mailBodyCtrl.text.trim();
      if (subject.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일 제목을 입력해 주세요.')),
        );
        return;
      }

      // ③ PDF 생성
      final pdfBytes = await _buildPdfBytes();
      final filename =
      _safeFileName(_titleCtrl.text.isEmpty ? '경위서' : _titleCtrl.text);

      // ④ Gmail API 전송
      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 전송 완료! (Gmail API)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '경위서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  // -------------------- PDF 생성 --------------------
  Future<Uint8List> _buildPdfBytes() async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final regData =
      await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(regData);
    } catch (_) {}

    try {
      final boldData =
      await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(boldData);
    } catch (_) {
      bold = regular;
    }

    final theme = (regular != null)
        ? pw.ThemeData.withFont(
        base: regular, bold: bold ?? regular, italic: regular, boldItalic: bold ?? regular)
        : pw.ThemeData.base();

    final doc = pw.Document();

    final now = DateTime.now();
    final fields = <MapEntry<String, String>>[
      MapEntry('제목', _titleCtrl.text),
      MapEntry('작성자', _writerCtrl.text),
      MapEntry('소속/직위', _deptCtrl.text),
      MapEntry('연락처', _contactCtrl.text),
      MapEntry('사건 발생 일시',
          _eventDateTime == null ? '미선택' : _fmtCompact(_eventDateTime!)),
      MapEntry('장소', _placeCtrl.text),
      MapEntry('관련자', _peopleCtrl.text),
      MapEntry('작성일', _fmtCompact(now)),
    ];

    pw.Widget buildFieldTable() => pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(7),
      },
      children: [
        for (final kv in fields)
          pw.TableRow(children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              color: PdfColors.grey200,
              child: pw.Text(kv.key, style: const pw.TextStyle(fontSize: 11)),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(kv.value, style: const pw.TextStyle(fontSize: 11)),
            ),
          ]),
      ],
    );

    pw.Widget buildSection(String title, String body) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(body.isEmpty ? '-' : body, style: const pw.TextStyle(fontSize: 11)),
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
          pw.Text('전자서명', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('서명자: $name', style: const pw.TextStyle(fontSize: 11))),
              pw.SizedBox(width: 8),
              pw.Text('서명 일시: $timeText', style: const pw.TextStyle(fontSize: 11)),
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
                child: pw.Text('서명 이미지 없음',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)))
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
            child: pw.Text('경위서',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),
          buildFieldTable(),
          buildSection('[경위 상세]', _detailCtrl.text),
          buildSection('[재발 방지 대책]', _preventionCtrl.text),
          buildSignature(),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('생성 시각: ${_fmtCompact(now)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
      ),
    );

    return doc.save();
  }

  // -------------------- Gmail API로 첨부 메일 전송 --------------------
  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    final api = gmail.GmailApi(client);

    final boundary =
        'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
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

    final raw =
    base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }

  Widget _gap(double h) => SizedBox(height: h);

  Future<void> _openSignatureDialog() async {
    final result = await showGeneralDialog<_SignatureResult>(
      context: context,
      barrierLabel: '서명',
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _SignatureFullScreenDialog(
          name: _signerName,
          initialDateTime: _signDateTime,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('경위서 작성'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: SizedBox(height: 1, child: ColoredBox(color: Colors.black12)),
        ),
        actions: [
          IconButton(
            tooltip: '미리보기',
            onPressed: _showPreview,
            icon: const Icon(Icons.visibility_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 상단 안내
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withOpacity(.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '사실에 근거해 간결하고 명확하게 작성해 주세요. 필요 시 관련 증빙(사진, 로그, 메일 등)을 첨부하여 제출합니다.',
                ),
              ),
              _gap(16),

              // 제목
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: '제목',
                  hintText: '예: 10월 18일 장비 파손 경위서',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _writerNode.requestFocus(),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? '제목을 입력하세요.' : null,
              ),
              _gap(12),

              // 작성자 / 소속
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _writerCtrl,
                      focusNode: _writerNode,
                      decoration: InputDecoration(
                        labelText: '작성자',
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(.35),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 12),
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _deptNode.requestFocus(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '작성자를 입력하세요.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deptCtrl,
                      focusNode: _deptNode,
                      decoration: InputDecoration(
                        labelText: '소속/직위',
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(.35),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 12),
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _contactNode.requestFocus(),
                    ),
                  ),
                ],
              ),
              _gap(12),

              // 연락처
              TextFormField(
                controller: _contactCtrl,
                focusNode: _contactNode,
                decoration: InputDecoration(
                  labelText: '연락처',
                  hintText: '예: 010-1234-5678',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))
                ],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _placeNode.requestFocus(),
              ),
              _gap(12),

              // 장소
              TextFormField(
                controller: _placeCtrl,
                focusNode: _placeNode,
                decoration: InputDecoration(
                  labelText: '장소',
                  hintText: '예: 본사 3층 서버실',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _peopleNode.requestFocus(),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? '장소를 입력하세요.' : null,
              ),
              _gap(12),

              // 관련자
              TextFormField(
                controller: _peopleCtrl,
                focusNode: _peopleNode,
                decoration: InputDecoration(
                  labelText: '관련자',
                  hintText: '예: 홍길동, 김노무',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _detailNode.requestFocus(),
              ),
              _gap(12),

              // 사건 일시
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                title: const Text('사건 발생 일시'),
                subtitle: Text(_fmtDT(context, _eventDateTime)),
                trailing: const Icon(Icons.event_outlined),
                onTap: _pickDateTime,
              ),
              _gap(12),

              // 경위 상세
              TextFormField(
                controller: _detailCtrl,
                focusNode: _detailNode,
                decoration: InputDecoration(
                  labelText: '경위 상세',
                  hintText: '사실 관계를 시간 순으로 상세히 기술',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                keyboardType: TextInputType.multiline,
                minLines: 6,
                maxLines: 12,
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? '경위 상세를 입력하세요.' : null,
              ),
              _gap(12),

              // 재발 방지 대책
              TextFormField(
                controller: _preventionCtrl,
                focusNode: _preventionNode,
                decoration: InputDecoration(
                  labelText: '재발 방지 대책',
                  hintText: '개선 방안 및 일정',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 10,
              ),

              _gap(20),

              // ✉️ 메일 전송 내용 (이 화면에서 작성)
              Text(
                '메일 전송 내용',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _mailSubjectCtrl,
                decoration: InputDecoration(
                  labelText: '메일 제목(필수)',
                  hintText: '예: 경위서 – 10월 18일 장비 파손 건',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? '메일 제목을 입력하세요.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _mailBodyCtrl,
                decoration: InputDecoration(
                  labelText: '메일 본문',
                  hintText: '메일 본문을 입력하세요. (선택)',
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.35),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
                minLines: 3,
                maxLines: 8,
              ),

              _gap(20),

              // 전자서명 섹션
              Text(
                '전자서명',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(.35),
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
                        Text('서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}'),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time, size: 18),
                        const SizedBox(width: 6),
                        Text('서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}'),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _openSignatureDialog,
                      icon: const Icon(Icons.border_color),
                      label: const Text('서명하기'),
                    ),
                    if (_signaturePngBytes != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _signaturePngBytes = null;
                            _signDateTime = null;
                          });
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('서명 삭제'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              if (_signaturePngBytes != null)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
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

              _gap(20),

              // 액션 버튼들
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sending ? null : _reset,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('초기화'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _showPreview,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('미리보기'),
                    ),
                  ),
                ],
              ),
              _gap(12),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.send_outlined),
                label: Text(_sending ? '전송 중…' : '제출'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────────────────────────
 * 풀스크린 서명 다이얼로그
 * ──────────────────────────────────────────────────────────────────────────── */
class _SignatureFullScreenDialog extends StatefulWidget {
  const _SignatureFullScreenDialog({
    required this.name,
    required this.initialDateTime,
  });

  final String name;
  final DateTime? initialDateTime;

  @override
  State<_SignatureFullScreenDialog> createState() =>
      _SignatureFullScreenDialogState();
}

class _SignatureFullScreenDialogState
    extends State<_SignatureFullScreenDialog> {
  final GlobalKey _boundaryKey = GlobalKey(); // 캡처용
  final List<Offset?> _points = <Offset?>[];
  DateTime? _signDateTime;

  static const double _strokeWidth = 2.2;

  @override
  void initState() {
    super.initState();
    _signDateTime = widget.initialDateTime;
  }

  bool get _hasAny => _points.any((p) => p != null);

  void _clear() => setState(() => _points.clear());

  void _undo() {
    if (_points.isEmpty) return;
    int i = _points.length - 1;
    if (_points[i] == null) {
      _points.removeAt(i);
      i--;
    }
    while (i >= 0 && _points[i] != null) {
      _points.removeAt(i);
      i--;
    }
    if (i >= 0 && _points[i] == null) {
      _points.removeAt(i);
    }
    setState(() {});
  }

  Future<void> _save() async {
    try {
      setState(() {
        _signDateTime = DateTime.now(); // 저장 시각 자동
      });
      await Future.delayed(const Duration(milliseconds: 16)); // 프레임 반영

      final boundary =
      _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('캡처 영역을 찾을 수 없습니다.')),
        );
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PNG 변환에 실패했습니다.')),
        );
        return;
      }
      final png = byteData.buffer.asUint8List();
      Navigator.of(context)
          .pop(_SignatureResult(pngBytes: png, signDateTime: _signDateTime!));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서명 저장 오류: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.name.isEmpty ? '이름 미입력' : widget.name;
    final timeText =
    _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: cs.surface,
            title: const Text('전자서명'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '닫기',
            ),
            actions: [
              IconButton(
                tooltip: '지우기',
                onPressed: _clear,
                icon: const Icon(Icons.layers_clear),
              ),
              IconButton(
                tooltip: '되돌리기',
                onPressed: _undo,
                icon: const Icon(Icons.undo),
              ),
              const SizedBox(width: 4),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: SizedBox(height: 1, child: ColoredBox(color: Colors.black12)),
            ),
          ),
          body: Column(
            children: [
              // 상단 정보 바
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(color: cs.surfaceVariant.withOpacity(.35)),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '서명자: $name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '서명 일시: $timeText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _signDateTime = DateTime.now()),
                      icon: const Icon(Icons.schedule),
                      label: const Text('지금'),
                    ),
                  ],
                ),
              ),

              // 서명 영역
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (d) => setState(() => _points.add(d.localPosition)),
                            onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
                            onPanEnd: (_) => setState(() => _points.add(null)),
                            child: CustomPaint(
                              painter: _SignaturePainter(
                                points: _points,
                                strokeWidth: _strokeWidth,
                                color: Colors.black87,
                                background: Colors.white,
                                overlayName: name,
                                overlayDateText: timeText,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              // 하단 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _hasAny ? _save : null,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('저장'),
                      ),
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

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _SignatureResult {
  _SignatureResult({required this.pngBytes, required this.signDateTime});
  final Uint8List pngBytes;
  final DateTime signDateTime;
}

/* ────────────────────────────────────────────────────────────────────────────
 * 커스텀 페인터: 선 그리기 + 이름/일시 오버레이
 * ──────────────────────────────────────────────────────────────────────────── */
class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.points,
    required this.strokeWidth,
    required this.color,
    required this.background,
    required this.overlayName,
    required this.overlayDateText,
  });

  final List<Offset?> points;
  final double strokeWidth;
  final Color color;
  final Color background;
  final String overlayName;
  final String overlayDateText;

  @override
  void paint(Canvas canvas, Size size) {
    // 배경
    final bg = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bg);

    // 기준선
    final guide = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(8, size.height - 40),
      Offset(size.width - 8, size.height - 40),
      guide,
    );

    // 서명 스트로크
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, p);
      }
    }

    // 힌트
    final hasAny = points.any((e) => e != null);
    if (!hasAny) {
      const hint = TextSpan(
        text: '화면 전체가 서명 영역입니다. 서명을 시작해 주세요.',
        style: TextStyle(color: Colors.black38, fontSize: 14),
      );
      final tp = TextPainter(text: hint, textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 16);
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
    }

    // 오버레이(우측 하단)
    final overlayTP = TextPainter(
      text: TextSpan(
        text: '서명자: $overlayName   서명일시: $overlayDateText',
        style: const TextStyle(color: Colors.black45, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);

    final pad = 8.0;
    final dx = size.width - overlayTP.width - pad;
    final dy = size.height - overlayTP.height - pad;
    overlayTP.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_SignaturePainter old) {
    return old.points != points ||
        old.strokeWidth != strokeWidth ||
        old.color != color ||
        old.background != background ||
        old.overlayName != overlayName ||
        old.overlayDateText != overlayDateText;
  }
}
