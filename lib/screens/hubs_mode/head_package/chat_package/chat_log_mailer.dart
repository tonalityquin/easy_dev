import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../services/sheet_chat_service.dart';
import '../../../../utils/google_auth_v7.dart';
import '../../../../utils/api/email_config.dart';

import 'chat_runtime.dart';
import 'chat_sheet_registry.dart';

class ChatLogMailer {
  ChatLogMailer._();

  static Future<void> open(BuildContext context) async {
    HapticFeedback.selectionClick();

    await ChatRuntime.instance.ensureInitialized();
    await ChatSheetRegistry.instance.ensureInitialized();

    final cfg = await EmailConfig.load();
    if (!EmailConfig.isValidToList(cfg.to)) {
      if (!context.mounted) return;
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

    final st = ChatRuntime.instance.state.value;
    final messages = st.messages;

    if (messages.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내보낼 채팅 로그가 없습니다.')),
      );
      return;
    }

    final apiOn = ChatRuntime.instance.useSheetsApi.value;
    final scopeKey = ChatRuntime.instance.scopeKey;
    final sel = ChatSheetRegistry.instance.selectedEntry;

    final alias = (apiOn ? (sel?.alias.trim().isNotEmpty == true ? sel!.alias.trim() : '미지정') : 'LOCAL');
    final now = DateTime.now();

    final defaultSubject = apiOn
        ? '[채팅로그] $alias ($scopeKey) ${_dateTag(now)}'
        : '[채팅로그-로컬] ($scopeKey) ${_dateTag(now)}';

    final defaultBody = [
      '첨부된 PDF에 채팅 로그가 포함되어 있습니다.',
      '',
      '- scopeKey: $scopeKey',
      '- 모드: ${apiOn ? 'Sheets API ON' : 'Sheets API OFF(로컬)'}',
      if (apiOn) '- 시트: ${sel?.alias ?? '미지정'} / ${sel?.id ?? '-'}',
      '- 생성 시각: ${_fmtCompact(now)}',
      '',
      '※ 전송 성공 후, (Sheets API ON인 경우) chat 시트의 내용은 자동 삭제됩니다.',
    ].join('\n');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _ChatLogMailDialog(
          toCsv: toCsv,
          defaultSubject: defaultSubject,
          defaultBody: defaultBody,
          snapshotState: st,
          scopeKey: scopeKey,
          apiOn: apiOn,
          sheetAlias: sel?.alias,
          spreadsheetId: sel?.id,
        );
      },
    );
  }

  static String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  static String _dateTag(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y$m$d-$hh$mm';
  }

  static String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? 'chat_log' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static String _wrapBase64(String input, {int lineLength = 76}) {
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i += lineLength) {
      final end = (i + lineLength < input.length) ? i + lineLength : input.length;
      sb.writeln(input.substring(i, end));
    }
    return sb.toString().trimRight();
  }

  static String _encodeHeaderIfNeeded(String s) {
    final hasNonAscii = s.codeUnits.any((c) => c > 127);
    if (!hasNonAscii) return s;
    final b64 = base64.encode(utf8.encode(s));
    return '=?UTF-8?B?$b64?=';
  }

  static String _base64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Future<Uint8List> buildChatLogPdfBytes({
    required List<SheetChatMessage> messages,
    required String scopeKey,
    required bool apiOn,
    required String? sheetAlias,
    required String? spreadsheetId,
    required DateTime createdAt,
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

    DateTime? firstTime;
    DateTime? lastTime;
    for (final m in messages) {
      final t = m.time;
      if (t == null) continue;
      final lt = t.toLocal();
      firstTime = (firstTime == null) ? lt : (lt.isBefore(firstTime) ? lt : firstTime);
      lastTime = (lastTime == null) ? lt : (lt.isAfter(lastTime) ? lt : lastTime);
    }

    final doc = pw.Document();

    pw.Widget metaLine(String k, String v) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              k,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(v, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      );
    }

    pw.Widget messageBlock(SheetChatMessage m, int idx) {
      final t = m.time?.toLocal();
      final timeText = (t == null) ? '-' : _fmtCompact(t);
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          borderRadius: pw.BorderRadius.circular(6),
          color: PdfColors.grey100,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '#${idx + 1}  $timeText',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(m.text, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      );
    }

    final modeText = apiOn ? 'Sheets API ON' : 'Sheets API OFF(로컬)';
    final sheetText = apiOn
        ? '${(sheetAlias?.trim().isNotEmpty == true) ? sheetAlias!.trim() : '미지정'} / ${spreadsheetId ?? '-'}'
        : 'LOCAL';

    final rangeText = (firstTime != null && lastTime != null)
        ? '${_fmtCompact(firstTime)} ~ ${_fmtCompact(lastTime)}'
        : '-';

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              '채팅 로그',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                metaLine('scopeKey', scopeKey),
                metaLine('모드', modeText),
                metaLine('시트', sheetText),
                metaLine('기간', rangeText),
                metaLine('메시지 수', '${messages.length}'),
                metaLine('생성 시각', _fmtCompact(createdAt)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '메시지',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          ...List.generate(messages.length, (i) => messageBlock(messages[i], i)),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ),
    );

    return doc.save();
  }

  static Future<void> sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    final api = gmail.GmailApi(client);

    final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
    final attachmentB64 = _wrapBase64(base64.encode(pdfBytes));

    final mime = StringBuffer()
      ..writeln('To: $to')
      ..writeln('Subject: ${_encodeHeaderIfNeeded(subject)}')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: text/plain; charset="UTF-8"')
      ..writeln('Content-Transfer-Encoding: 7bit')
      ..writeln()
      ..writeln(body)
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: application/pdf; name="$filename"')
      ..writeln('Content-Disposition: attachment; filename="$filename"')
      ..writeln('Content-Transfer-Encoding: base64')
      ..writeln()
      ..writeln(attachmentB64)
      ..writeln('--$boundary--');

    final raw = _base64UrlNoPad(utf8.encode(mime.toString()));
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }
}

class _ChatLogMailDialog extends StatefulWidget {
  final String toCsv;
  final String defaultSubject;
  final String defaultBody;
  final SheetChatState snapshotState;

  final String scopeKey;
  final bool apiOn;
  final String? sheetAlias;
  final String? spreadsheetId;

  const _ChatLogMailDialog({
    required this.toCsv,
    required this.defaultSubject,
    required this.defaultBody,
    required this.snapshotState,
    required this.scopeKey,
    required this.apiOn,
    required this.sheetAlias,
    required this.spreadsheetId,
  });

  @override
  State<_ChatLogMailDialog> createState() => _ChatLogMailDialogState();
}

class _ChatLogMailDialogState extends State<_ChatLogMailDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.defaultSubject);
    _bodyCtrl = TextEditingController(text: widget.defaultBody);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.lightImpact();
    setState(() => _sending = true);

    bool cleared = false;
    String? clearError;

    try {
      final createdAt = DateTime.now();
      final messages = widget.snapshotState.messages;

      final pdfBytes = await ChatLogMailer.buildChatLogPdfBytes(
        messages: messages,
        scopeKey: widget.scopeKey,
        apiOn: widget.apiOn,
        sheetAlias: widget.sheetAlias,
        spreadsheetId: widget.spreadsheetId,
        createdAt: createdAt,
      );

      final alias = widget.apiOn
          ? ((widget.sheetAlias?.trim().isNotEmpty == true) ? widget.sheetAlias!.trim() : '미지정')
          : 'LOCAL';
      final fileBase = ChatLogMailer._safeFileName(
        '채팅로그_${alias}_${ChatLogMailer._dateTag(createdAt)}',
      );

      // 1) 메일 전송
      await ChatLogMailer.sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$fileBase.pdf',
        to: widget.toCsv,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
      );

      // 2) ✅ 전송 성공 후 시트 내용 삭제 (Sheets API ON인 경우만)
      if (widget.apiOn) {
        try {
          await SheetChatService.instance.clearAllMessages(
            spreadsheetIdOverride: widget.spreadsheetId,
          );
          cleared = true;
        } catch (e) {
          clearError = e.toString();
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      final msg = widget.apiOn
          ? (cleared ? '채팅 로그 메일 전송 완료 (시트 내용 삭제됨)' : '채팅 로그 메일 전송 완료 (시트 삭제 실패)')
          : '채팅 로그 메일 전송 완료';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(clearError == null ? msg : '$msg: $clearError')),
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

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgCount = widget.snapshotState.messages.length;

    return AlertDialog(
      title: const Text('채팅 로그를 PDF로 메일 전송'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '수신자: ${widget.toCsv}\n메시지 수: $msgCount\n'
                        '${widget.apiOn ? "※ 전송 성공 후 chat 시트 내용이 자동 삭제됩니다." : ""}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subjectCtrl,
                  decoration: _dec('메일 제목(필수)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '메일 제목을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bodyCtrl,
                  minLines: 4,
                  maxLines: 10,
                  decoration: _dec('메일 본문', hint: '선택 사항'),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '※ 첨부 PDF에는 현재 로드된 채팅 메시지가 포함됩니다.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.send_outlined),
          label: Text(_sending ? '전송 중…' : '전송'),
        ),
      ],
    );
  }
}
