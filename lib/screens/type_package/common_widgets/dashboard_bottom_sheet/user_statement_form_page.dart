// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/statement_form_page.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../utils/google_auth_v7.dart';
import '../../../../utils/email_config.dart';

class UserStatementFormPage extends StatefulWidget {
  const UserStatementFormPage({super.key});

  @override
  State<UserStatementFormPage> createState() => _UserStatementFormPageState();
}

/// 앱 공통 버튼 스타일(참고: HomeBreakButtonWidget)
class _AppButtonStyles {
  static const _radius = 8.0;

  /// AppBar 등 가로 제약이 있는 곳에서도 안전하게 동작하도록
  /// minWidth=0, minHeight만 지정 (⚠️ Size.fromHeight 사용 금지)
  static ButtonStyle primary({double minHeight = 55}) {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      minimumSize: Size(0, minHeight), // ✅ 가로 무한 너비 방지
      padding: EdgeInsets.zero,
      side: const BorderSide(color: Colors.grey, width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      elevation: 0,
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed) ? Colors.black12 : null,
      ),
    );
  }

  static ButtonStyle outlined({double minHeight = 55}) {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.black,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Colors.grey, width: 1.0),
      minimumSize: Size(0, minHeight), // ✅ 가로 무한 너비 방지
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    );
  }

  static ButtonStyle smallPrimary() => primary(minHeight: 44);
  static ButtonStyle smallOutlined() => outlined(minHeight: 44);
}

class _UserStatementFormPageState extends State<UserStatementFormPage> {
  final _formKey = GlobalKey<FormState>();

  // ── 입력 컨트롤러 ────────────────────────────────────────────────────────────
  final _deptCtrl = TextEditingController(); // 소속
  final _nameCtrl = TextEditingController(); // 성명
  final _positionCtrl = TextEditingController(); // 직책
  final _contentCtrl = TextEditingController(); // 내용(육하원칙 기반)

  // ✉️ 메일 제목/본문(이 화면에서 직접 작성)
  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  DateTime? _eventDateTime; // 일시

  // ── 포커스 ─────────────────────────────────────────────────────────────────
  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  // ── 전자서명 상태 ─────────────────────────────────────────────────────────
  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;
  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {})); // 서명자 라벨 갱신용
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _contentCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _deptNode.dispose();
    _nameNode.dispose();
    _positionNode.dispose();
    _contentNode.dispose();
    super.dispose();
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────────
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

  String _dateTag(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _pickDateTime() async {
    HapticFeedback.selectionClick();
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
    HapticFeedback.lightImpact();
    _formKey.currentState?.reset();
    _deptCtrl.clear();
    _nameCtrl.clear();
    _positionCtrl.clear();
    _contentCtrl.clear();
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
      '소속: ${(_deptCtrl.text).trim()}',
      '성명: ${(_nameCtrl.text).trim()}',
      '직책: ${(_positionCtrl.text).trim()}',
      '일시: ${_fmtDT(context, _eventDateTime)}',
      '',
      '[내용(육하원칙 기반)]',
      _contentCtrl.text,
      '',
      signInfo,
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showPreview() async {
    HapticFeedback.lightImpact();
    final text = _buildPreviewText(context);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('미리보기'),
        content: SizedBox(
          width: 520,
          child: Scrollbar(
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
        ),
        actions: [
          TextButton(
            onPressed: () async {
              HapticFeedback.selectionClick();
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

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      // ① 저장된 수신자(To) 로드 및 검증
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

      // ② 화면에서 입력한 메일 제목/본문 확보(제목 필수)
      final subject = _mailSubjectCtrl.text.trim();
      final body = _mailBodyCtrl.text.trim();
      if (subject.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일 제목을 입력해 주세요.')),
        );
        return;
      }

      // ③ 필수 항목 재검증 (일시 포함)
      if (_eventDateTime == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('일시를 선택해 주세요.')),
        );
        return;
      }

      // ④ PDF 생성
      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile = _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('경위서_${nameForFile}_${_dateTag(now)}');

      // ⑤ Gmail API 전송
      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 전송 완료')),
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

  // ── PDF 생성 ────────────────────────────────────────────────────────────────
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
      base: regular,
      bold: bold ?? regular,
      italic: regular,
      boldItalic: bold ?? regular,
    )
        : pw.ThemeData.base();

    final doc = pw.Document();
    final fields = <MapEntry<String, String>>[
      MapEntry('소속', _deptCtrl.text),
      MapEntry('성명', _nameCtrl.text),
      MapEntry('직책', _positionCtrl.text),
      MapEntry('일시', _fmtCompact(_eventDateTime!)),
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
        pw.Text(title,
            style:
            pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            body.isEmpty ? '-' : body,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );

    pw.Widget buildSignature() {
      final name = _signerName.isEmpty ? '이름 미입력' : _signerName;
      final timeText =
      _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text('전자서명',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text('서명자: $name',
                    style: const pw.TextStyle(fontSize: 11)),
              ),
              pw.SizedBox(width: 8),
              pw.Text('서명 일시: $timeText',
                  style: const pw.TextStyle(fontSize: 11)),
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
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey)),
            )
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
            child: pw.Text(
              '경위서',
              style:
              pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 12),
          buildFieldTable(),
          buildSection('[내용(육하원칙 기반)]', _contentCtrl.text),
          buildSignature(),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '생성 시각: ${_fmtCompact(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ),
    );

    return doc.save();
  }

  // ── Gmail API로 첨부 메일 전송 ──────────────────────────────────────────────
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

    // Gmail API는 base64url(raw) 요구(= URL-safe + padding 제거)
    final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  InputDecoration _inputDec({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      color: Colors.white,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  Future<void> _openSignatureDialog() async {
    HapticFeedback.selectionClick();
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
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('경위서 작성'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: _AppButtonStyles.smallPrimary(), // ✅ AppBar 안전 스타일
            ),
          ),
        ],
      ),

      /// ✅ 키패드가 올라와도 제출 버튼이 자동으로 위로 올라오도록 bottomNavigationBar 사용
      bottomNavigationBar: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            // 키보드 높이만큼 추가로 올림
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.black12, width: 1),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending ? '전송 중…' : '제출',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: _AppButtonStyles.primary(),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Scrollbar(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 안내 배너
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.info_outline, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '사실에 근거해 간결하고 명확하게 작성해 주세요. (육하원칙: 누가/언제/어디서/무엇을/왜/어떻게)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _gap(12),

                // 기본 정보
                _sectionCard(
                  title: '기본 정보',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _deptCtrl,
                              focusNode: _deptNode,
                              decoration: _inputDec(
                                labelText: '소속 (필수)',
                                hintText: '예: 본사 IT본부',
                              ),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _nameNode.requestFocus(),
                              validator: (v) =>
                              (v == null || v.trim().isEmpty) ? '소속을 입력하세요.' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _nameCtrl,
                              focusNode: _nameNode,
                              decoration: _inputDec(
                                labelText: '성명 (필수)',
                                hintText: '예: 홍길동',
                              ),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _positionNode.requestFocus(),
                              validator: (v) =>
                              (v == null || v.trim().isEmpty) ? '성명을 입력하세요.' : null,
                            ),
                          ),
                        ],
                      ),
                      _gap(12),
                      TextFormField(
                        controller: _positionCtrl,
                        focusNode: _positionNode,
                        decoration: _inputDec(
                          labelText: '직책 (필수)',
                          hintText: '예: 매니저 / 대리 / 주임 등',
                        ),
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '직책을 입력하세요.' : null,
                      ),
                      _gap(12),
                      // 일시 선택
                      InkWell(
                        onTap: _pickDateTime,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.event_outlined),
                              const SizedBox(width: 10),
                              const Text('일시 (필수)',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text(
                                _fmtDT(context, _eventDateTime),
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 내용 섹션
                _sectionCard(
                  title: '내용 (육하원칙 기반, 필수)',
                  child: TextFormField(
                    controller: _contentCtrl,
                    focusNode: _contentNode,
                    decoration: _inputDec(
                      labelText: '내용',
                      hintText:
                      '누가/언제/어디서/무엇을/왜/어떻게 순으로 구체적으로 작성해 주세요.',
                    ),
                    keyboardType: TextInputType.multiline,
                    minLines: 8,
                    maxLines: 16,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '내용을 입력하세요.' : null,
                  ),
                ),

                // 메일 전송 내용
                _sectionCard(
                  title: '메일 전송 내용',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _mailSubjectCtrl,
                        decoration: _inputDec(
                          labelText: '메일 제목(필수)',
                          hintText:
                          '예: 경위서 – ${DateTime.now().month}월 ${DateTime.now().day}일 건',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '메일 제목을 입력하세요.' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _mailBodyCtrl,
                        decoration: _inputDec(
                          labelText: '메일 본문',
                          hintText: '메일 본문을 입력하세요. (선택)',
                        ),
                        minLines: 3,
                        maxLines: 8,
                      ),
                    ],
                  ),
                ),

                // 전자서명
                _sectionCard(
                  title: '전자서명',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black12),
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
                                Text(
                                  '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                                  style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: _openSignatureDialog,
                              icon: const Icon(Icons.border_color),
                              label: const Text('서명하기'),
                              style: _AppButtonStyles.smallPrimary(),
                            ),
                            if (_signaturePngBytes != null)
                              OutlinedButton.icon(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _signaturePngBytes = null;
                                    _signDateTime = null;
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('서명 삭제'),
                                style: _AppButtonStyles.smallOutlined(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_signaturePngBytes != null)
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
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
                    ],
                  ),
                ),

                _gap(8),

                // 액션 버튼들 (미리보기/초기화)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sending ? null : _reset,
                        icon: const Icon(Icons.refresh_outlined),
                        label: const Text('초기화'),
                        style: _AppButtonStyles.outlined(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sending ? null : _showPreview,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('미리보기'),
                        style: _AppButtonStyles.primary(),
                      ),
                    ),
                  ],
                ),

                // 리스트 끝부분에 여유를 둬서 스크롤 막힘/가림 방지
                const SizedBox(height: 20),
              ],
            ),
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

  void _clear() {
    HapticFeedback.selectionClick();
    setState(() => _points.clear());
  }

  void _undo() {
    HapticFeedback.selectionClick();
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
      HapticFeedback.lightImpact();
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
    final name = widget.name.isEmpty ? '이름 미입력' : widget.name;
    final timeText =
    _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: const Text('전자서명'),
            centerTitle: true,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shape: const Border(
              bottom: BorderSide(color: Colors.black12, width: 1),
            ),
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
          ),
          body: Column(
            children: [
              // 상단 정보 바
              Container(
                padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: const BoxDecoration(color: Colors.white),
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
                      onPressed: () =>
                          setState(() => _signDateTime = DateTime.now()),
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
                            onPanStart: (d) =>
                                setState(() => _points.add(d.localPosition)),
                            onPanUpdate: (d) =>
                                setState(() => _points.add(d.localPosition)),
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
                        style: _AppButtonStyles.outlined(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _hasAny ? _save : null,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('저장'),
                        style: _AppButtonStyles.primary(),
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
      const Offset(8, 40), // 상단 가이드가 좋으면 이 값을 바꾸세요
      Offset(size.width - 8, 40),
      guide,
    );
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

    const pad = 8.0;
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
