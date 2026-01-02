import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:mime/mime.dart';

import 'package:easydev/utils/api/email_config.dart';
import 'package:easydev/utils/google_auth_v7.dart';

import 'photo_transfer_styles.dart';
class PhotoTransferMailPage extends StatefulWidget {
  const PhotoTransferMailPage({super.key});

  @override
  State<PhotoTransferMailPage> createState() => _PhotoTransferMailPageState();
}

class _PhotoTransferMailPageState extends State<PhotoTransferMailPage> {
  final _formKey = GlobalKey<FormState>();

  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  bool _sending = false;

  final List<_PickedAttachment> _attachments = [];

  // Gmail 첨부 제한(일반적으로 25MB, base64 오버헤드 고려하여 raw 18MB 정도로 보수 적용)
  static const int _maxTotalRawBytes = 18 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _subjectCtrl.text = '사진 전송 – ${_fmtCompact(now)}';
    _bodyCtrl.text = '사진 첨부드립니다.\n\n(필요 시 내용을 수정해 주세요.)';
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(1)}MB';
  }

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
        borderSide: const BorderSide(
          color: PhotoTransferColors.base,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 12,
      ),
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
      margin: margin ?? const EdgeInsets.only(bottom: 16),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  int get _totalRawBytes => _attachments.fold<int>(0, (sum, a) => sum + a.bytes.length);

  Future<void> _pickPhotos({bool append = true}) async {
    HapticFeedback.selectionClick();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true, // ✅ 여러 장 선택
        withData: true, // 가능한 환경에서 bytes 제공
      );

      if (result == null || result.files.isEmpty) return;

      final List<_PickedAttachment> picked = [];
      for (final f in result.files) {
        Uint8List? bytes = f.bytes;

        if (bytes == null) {
          final path = f.path;
          if (path == null || path.trim().isEmpty) {
            throw Exception('선택한 파일의 bytes/path 정보를 가져올 수 없습니다.');
          }
          bytes = await File(path).readAsBytes();
        }

        final name = (f.name.trim().isEmpty)
            ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
            : f.name.trim();

        final mime = lookupMimeType(name, headerBytes: bytes) ?? 'application/octet-stream';

        picked.add(
          _PickedAttachment(
            bytes: bytes,
            filename: name,
            mimeType: mime,
          ),
        );
      }

      final int nextTotal = (append ? _totalRawBytes : 0) + picked.fold<int>(0, (s, a) => s + a.bytes.length);
      if (nextTotal > _maxTotalRawBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '첨부 용량이 너무 큽니다. (총 ${_fmtBytes(nextTotal)} / 제한 ${_fmtBytes(_maxTotalRawBytes)})\n'
                  '사진 수를 줄이거나 용량이 작은 사진으로 선택해 주세요.',
            ),
          ),
        );
        return;
      }

      setState(() {
        if (!append) _attachments.clear();

        for (final a in picked) {
          // 동일 파일명+크기 중복 방지(원치 않으면 제거 가능)
          final exists = _attachments.any(
                (e) => e.filename == a.filename && e.bytes.length == a.bytes.length,
          );
          if (!exists) _attachments.add(a);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진 선택 실패: $e')),
      );
    }
  }

  void _removeAttachmentAt(int index) {
    HapticFeedback.selectionClick();
    if (index < 0 || index >= _attachments.length) return;
    setState(() => _attachments.removeAt(index));
  }

  void _clearAllAttachments() {
    HapticFeedback.selectionClick();
    setState(() => _attachments.clear());
  }

  Future<void> _send() async {
    if (_attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전송할 사진을 먼저 선택해 주세요.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_totalRawBytes > _maxTotalRawBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '첨부 용량이 너무 큽니다. (총 ${_fmtBytes(_totalRawBytes)} / 제한 ${_fmtBytes(_maxTotalRawBytes)})',
          ),
        ),
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

      final subject = _subjectCtrl.text.trim();
      final body = _bodyCtrl.text.trim();

      await _sendEmailViaGmail(
        to: toCsv,
        subject: subject,
        body: body,
        attachments: List<_PickedAttachment>.from(_attachments),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 전송 완료')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _base64Lines(Uint8List bytes, {int lineLength = 76}) {
    final b64 = base64.encode(bytes);
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.writeln(b64.substring(i, end));
    }
    return sb.toString();
  }

  /// ✅ 여러 첨부파일 지원: attachment 파트를 반복 추가
  Future<void> _sendEmailViaGmail({
    required String to,
    required String subject,
    required String body,
    required List<_PickedAttachment> attachments,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    final api = gmail.GmailApi(client);

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
      ..writeln();

    for (final a in attachments) {
      sb
        ..writeln('--$boundary')
        ..writeln('Content-Type: ${a.mimeType}; name="${a.filename}"')
        ..writeln('Content-Disposition: attachment; filename="${a.filename}"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln()
        ..write(_base64Lines(a.bytes)); // ✅ 줄바꿈 포함 base64
    }

    sb.writeln('--$boundary--');

    final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = _fmtCompact(DateTime.now());

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFEFF3F6),
      appBar: AppBar(
        title: const Text('사진 전송'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
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
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending ? '전송 중…' : '전송',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: PhotoTransferButtonStyles.primary(),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Scrollbar(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '사진 전송',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PHOTO TRANSFER',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.black54,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: PhotoTransferColors.light.withOpacity(0.8),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.photo_outlined,
                                  size: 22,
                                  color: PhotoTransferColors.dark,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '메일로 사진 첨부 전송',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: PhotoTransferColors.dark,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '작성일 $createdAt',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 24),
                            const SizedBox(height: 4),
                            Container(
                              decoration: BoxDecoration(
                                color: PhotoTransferColors.light.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: PhotoTransferColors.light.withOpacity(0.8),
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: PhotoTransferColors.dark,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '휴대폰 갤러리/파일 선택기에서 사진을 여러 장 선택한 뒤, 제목과 본문을 입력하여 Gmail로 전송합니다.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            _sectionCard(
                              title: '1. 사진 선택 (필수, 여러 장 가능)',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _sending ? null : () => _pickPhotos(append: true),
                                          icon: const Icon(Icons.photo_library_outlined),
                                          label: const Text('사진 선택/추가'),
                                          style: PhotoTransferButtonStyles.primary(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      OutlinedButton.icon(
                                        onPressed: (_sending || _attachments.isEmpty) ? null : _clearAllAttachments,
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('전체 삭제'),
                                        style: PhotoTransferButtonStyles.outlined(minHeight: 55),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _attachments.isEmpty
                                              ? '선택된 사진이 없습니다.'
                                              : '선택: ${_attachments.length}장 · 총 ${_fmtBytes(_totalRawBytes)}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.black54,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  if (_attachments.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _attachments.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (ctx, i) {
                                        final a = _attachments[i];
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFAFAFA),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.black12),
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Image.memory(
                                                  a.bytes,
                                                  width: 64,
                                                  height: 64,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      a.filename,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '${a.mimeType} · ${_fmtBytes(a.bytes.length)}',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: _sending ? null : () => _removeAttachmentAt(i),
                                                icon: const Icon(Icons.close),
                                                tooltip: '삭제',
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            _sectionCard(
                              title: '2. 메일 제목 (필수)',
                              child: TextFormField(
                                controller: _subjectCtrl,
                                decoration: _inputDec(
                                  labelText: '제목',
                                  hintText: '예) 현장 사진 전달드립니다.',
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? '메일 제목을 입력해 주세요.' : null,
                              ),
                            ),

                            _sectionCard(
                              title: '3. 메일 본문 (선택)',
                              margin: const EdgeInsets.only(bottom: 0),
                              child: TextFormField(
                                controller: _bodyCtrl,
                                decoration: _inputDec(
                                  labelText: '본문',
                                  hintText: '필요한 내용을 입력하세요.',
                                ),
                                minLines: 4,
                                maxLines: 10,
                                keyboardType: TextInputType.multiline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedAttachment {
  _PickedAttachment({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}
