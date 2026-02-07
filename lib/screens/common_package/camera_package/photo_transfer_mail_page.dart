import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:mime/mime.dart';

import '../../../utils/api/email_config.dart';
import '../../../utils/google_auth_v7.dart';
import '../../hubs_mode/dev_package/debug_package/debug_api_logger.dart';
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

  // RFC 2045 base64 line length
  static const int _mimeB64LineLength = 76;

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

  String _fmtYmdHms(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
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

        final name = (f.name.trim().isEmpty) ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : f.name.trim();

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
      // ✅ API 디버그 로직: 예외를 통합 에러 로그(api_log.txt)에 기록
      await _logApiError(
        tag: 'PhotoTransferMailPage._pickPhotos',
        message: '사진 선택 실패',
        error: e,
        extra: <String, dynamic>{
          'attachmentsCount': _attachments.length,
          'totalRawBytes': _totalRawBytes,
        },
        tags: const <String>['photo_transfer', 'file_picker'],
      );

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

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직(통합): 에러 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {
      // 로깅 실패는 사용자 UX에 영향 주지 않도록 무시
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직(UI): 에러 로그 BottomSheet 오픈
  // ─────────────────────────────────────────────────────────────
  Future<void> _openApiDebugSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ApiDebugBottomSheet(
          fmtYmdHms: _fmtYmdHms,
          onSendEmail: ({
            required String to,
            required String subject,
            required String body,
            required List<_PickedAttachment> attachments,
          }) =>
              _sendEmailViaGmail(
                to: to,
                subject: subject,
                body: body,
                attachments: attachments,
              ),
        );
      },
    );
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

      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

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
      // ✅ API 디버그 로직: 전송 실패를 통합 에러 로그로 남김
      await _logApiError(
        tag: 'PhotoTransferMailPage._send',
        message: '메일 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'attachmentsCount': _attachments.length,
          'totalRawBytes': _totalRawBytes,
          // 개인정보/민감정보 가능성이 있어 subject/body 원문은 기본 로깅에서 제외(필요 시 마스킹 후 추가 권장)
          'subjectLength': _subjectCtrl.text.trim().length,
          'bodyLength': _bodyCtrl.text.trim().length,
        },
        tags: const <String>['photo_transfer', 'gmail', 'send'],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // MIME helpers (CRLF + Subject RFC2047)
  // ─────────────────────────────────────────────────────────────
  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _encodeSubjectRfc2047(String subject) {
    // UTF-8 base64 형태로 RFC 2047 인코딩 (한글/비ASCII 안전)
    final b64 = base64.encode(utf8.encode(subject));
    return '=?utf-8?B?$b64?=';
  }

  String _base64Lines(Uint8List bytes, {int lineLength = _mimeB64LineLength}) {
    final b64 = base64.encode(bytes);
    return _wrapBase64Lines(b64, lineLength: lineLength);
  }

  String _buildMimeMessage({
    required String to,
    required String subject,
    required String body,
    required List<_PickedAttachment> attachments,
  }) {
    const crlf = '\r\n';
    final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
    final subjectEncoded = _encodeSubjectRfc2047(subject);

    final sb = StringBuffer()
      ..write('To: $to$crlf')
      ..write('Subject: $subjectEncoded$crlf')
      ..write('MIME-Version: 1.0$crlf')
      ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
      ..write(crlf)
      ..write('--$boundary$crlf')
      ..write('Content-Type: text/plain; charset="utf-8"$crlf')
      ..write('Content-Transfer-Encoding: 7bit$crlf')
      ..write(crlf)
      ..write(body)
      ..write(crlf);

    for (final a in attachments) {
      sb
        ..write('--$boundary$crlf')
        ..write('Content-Type: ${a.mimeType}; name="${a.filename}"$crlf')
        ..write('Content-Disposition: attachment; filename="${a.filename}"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(_base64Lines(a.bytes))
        ..write(crlf);
    }

    sb.write('--$boundary--$crlf');
    return sb.toString();
  }

  Future<void> _sendRawViaGmail(String mime) async {
    // GoogleAuthV7이 내부적으로 Gmail send에 필요한 scope를 세팅하는 구조라면 empty scopes 유지 가능.
    // 필요 시 Gmail scope를 명시하세요.
    // 예: const scopes = <String>['https://www.googleapis.com/auth/gmail.send'];
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    try {
      final api = gmail.GmailApi(client);

      // Gmail API raw는 base64url 인코딩 + padding 제거가 일반적으로 호환성이 좋습니다.
      final raw = base64UrlEncode(utf8.encode(mime)).replaceAll('=', '');

      final msg = gmail.Message()..raw = raw;
      await api.users.messages.send(msg, 'me');
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  /// ✅ 여러 첨부파일 지원: attachment 파트를 반복 추가
  Future<void> _sendEmailViaGmail({
    required String to,
    required String subject,
    required String body,
    required List<_PickedAttachment> attachments,
  }) async {
    try {
      final mime = _buildMimeMessage(
        to: to,
        subject: subject,
        body: body,
        attachments: attachments,
      );
      await _sendRawViaGmail(mime);
    } catch (e) {
      // ✅ API 디버그 로직: Gmail 전송 계층에서의 실패도 별도 로깅
      await _logApiError(
        tag: 'PhotoTransferMailPage._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'to': to,
          'attachmentsCount': attachments.length,
          'totalRawBytes': attachments.fold<int>(0, (s, a) => s + a.bytes.length),
        },
        tags: const <String>['photo_transfer', 'gmail', 'api'],
      );
      rethrow;
    }
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
        actions: [
          IconButton(
            tooltip: 'API 디버그 로그',
            onPressed: _openApiDebugSheet,
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
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
                                      '휴대폰 갤러리/파일 선택기에서 사진을 여러 장 선택한 뒤, 제목과 본문을 입력하여 Gmail로 전송합니다.\n'
                                          '우측 상단 “벌레” 아이콘에서 전송 오류(API 에러 로그)를 확인/복사/삭제/메일 전송할 수 있습니다.',
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

/// ─────────────────────────────────────────────────────────────
/// ✅ API 디버그 UI (API 에러 로그 조회/검색/태그/복사/삭제/메일전송)
/// ─────────────────────────────────────────────────────────────

enum _ApiDebugMenuAction {
  toggleMasking,
  showConfigInfo,
}

class _ApiDebugBottomSheet extends StatefulWidget {
  const _ApiDebugBottomSheet({
    required this.fmtYmdHms,
    required this.onSendEmail,
  });

  final String Function(DateTime dt) fmtYmdHms;

  final Future<void> Function({
  required String to,
  required String subject,
  required String body,
  required List<_PickedAttachment> attachments,
  }) onSendEmail;

  @override
  State<_ApiDebugBottomSheet> createState() => _ApiDebugBottomSheetState();
}

class _ApiDebugBottomSheetState extends State<_ApiDebugBottomSheet> {
  // Tags
  static const String _tagAll = '__ALL__';
  static const String _tagUntagged = '__UNTAGGED__';

  final _searchCtrl = TextEditingController();
  final _listCtrl = ScrollController();

  bool _loading = true;
  bool _sending = false;

  bool _maskSensitiveInEmail = true;

  List<_ApiLogEntry> _all = <_ApiLogEntry>[];
  List<_ApiLogEntry> _filtered = <_ApiLogEntry>[];

  String _selectedTag = _tagAll;
  List<String> _availableTags = <String>[_tagAll];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final logger = DebugApiLogger();
      final lines = await logger.readAllLinesCombined();

      final entries = <_ApiLogEntry>[];
      for (final line in lines) {
        final e = _parseLine(line);
        if (e != null) entries.add(e);
      }

      // 최신순 정렬
      entries.sort((a, b) {
        final at = a.ts?.millisecondsSinceEpoch ?? 0;
        final bt = b.ts?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      // tags 집계
      final tagSet = <String>{};
      var hasUntagged = false;
      for (final e in entries) {
        if (e.tags.isEmpty) {
          hasUntagged = true;
        } else {
          tagSet.addAll(e.tags);
        }
      }

      final tags = tagSet.toList()..sort();
      final available = <String>[_tagAll];
      if (hasUntagged) available.add(_tagUntagged);
      available.addAll(tags);

      var selected = _selectedTag;
      if (!available.contains(selected)) selected = _tagAll;

      setState(() {
        _all = entries;
        _availableTags = available;
        _selectedTag = selected;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _all = <_ApiLogEntry>[];
        _filtered = <_ApiLogEntry>[];
        _availableTags = <String>[_tagAll];
        _selectedTag = _tagAll;
        _loading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그 로딩 실패: $e')));
    }
  }

  _ApiLogEntry? _parseLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;

    // JSON 라인 우선
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map<String, dynamic>) {
        final ts = (decoded['ts'] is String) ? DateTime.tryParse(decoded['ts'] as String) : null;
        final level = (decoded['level'] as String?)?.toLowerCase();
        final msg = (decoded['message'] as String?) ?? '';

        final tagsAny = decoded['tags'];
        final tags = <String>[];
        if (tagsAny is List) {
          for (final x in tagsAny) {
            final s = x?.toString().trim();
            if (s != null && s.isNotEmpty) tags.add(s);
          }
        }

        return _ApiLogEntry(
          ts: ts,
          level: (level ?? 'error'),
          message: msg,
          original: t,
          tags: tags,
        );
      }
    } catch (_) {
      // ignore
    }

    // fallback (혹시라도)
    DateTime? ts;
    String msg = t;
    final idx = t.indexOf(': ');
    if (idx > 0) {
      ts = DateTime.tryParse(t.substring(0, idx));
      msg = t.substring(idx + 2);
    }

    return _ApiLogEntry(
      ts: ts,
      level: 'error',
      message: msg,
      original: t,
      tags: const <String>[],
    );
  }

  bool _isError(_ApiLogEntry e) => (e.level ?? '').toLowerCase() == 'error';

  bool _tagMatches(_ApiLogEntry e) {
    if (_selectedTag == _tagAll) return true;
    if (_selectedTag == _tagUntagged) return e.tags.isEmpty;
    return e.tags.contains(_selectedTag);
  }

  bool _searchMatches(_ApiLogEntry e, String keyLower) {
    if (keyLower.isEmpty) return true;
    final sb = StringBuffer();
    if ((e.message ?? '').isNotEmpty) {
      sb.write(e.message);
      sb.write(' ');
    }
    if (e.ts != null) sb.write(widget.fmtYmdHms(e.ts!));
    return sb.toString().toLowerCase().contains(keyLower);
  }

  void _applyFilter() {
    final keyLower = _searchCtrl.text.trim().toLowerCase();
    _filtered = _all
        .where((e) => _isError(e) && _tagMatches(e) && _searchMatches(e, keyLower))
        .toList(growable: false);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(_applyFilter);
  }

  Future<void> _copyFiltered() async {
    if (_filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('복사할 로그가 없습니다.')));
      return;
    }

    final text = _filtered.reversed.map((e) => e.original ?? e.message ?? '').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('클립보드에 복사되었습니다.')));
  }

  Future<void> _clearAll() async {
    setState(() => _loading = true);
    try {
      final logger = DebugApiLogger();
      await logger.init();
      await logger.clearLog();
      _searchCtrl.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 로그가 삭제되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      setState(() => _loading = false);
    }
  }

  String _sanitizeForEmail(String input) {
    var out = input;

    // 1) Bearer 토큰
    out = out.replaceAllMapped(
      RegExp(r'(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***',
    );

    // 2) JSON 형태 토큰 값
    out = out.replaceAllMapped(
      RegExp(r'("access_token"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("refresh_token"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("id_token"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("authorization"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("x-api-key"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );

    // 3) 쿼리스트링/키=값 형태 토큰
    out = out.replaceAllMapped(
      RegExp(r'((?:access_token|refresh_token|id_token)=)[^&\s]+', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***',
    );
    out = out.replaceAllMapped(
      RegExp(r'((?:x-api-key|api_key|apikey)=)[^&\s]+', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***',
    );

    // 4) 이메일 주소
    out = out.replaceAllMapped(
      RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
          (_) => '***@***',
    );

    // 5) 한국 휴대폰 번호(단순 패턴)
    out = out.replaceAllMapped(
      RegExp(r'\b01[016789]-?\d{3,4}-?\d{4}\b'),
          (_) => '***-****-****',
    );

    // 6) 주민등록번호(단순 패턴)
    out = out.replaceAllMapped(
      RegExp(r'\b\d{6}-?\d{7}\b'),
          (_) => '******-*******',
    );

    return out;
  }

  Future<void> _sendLogsByEmail() async {
    if (_sending) return;

    setState(() => _sending = true);
    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.')),
        );
        return;
      }

      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
      if (toCsv.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('수신자(To)가 비어 있습니다.')));
        return;
      }

      final now = DateTime.now();
      final subjectTag = (_selectedTag == _tagAll)
          ? 'ALL'
          : (_selectedTag == _tagUntagged)
          ? 'UNTAGGED'
          : _selectedTag;

      final subject = 'PhotoTransfer API Debug Logs($subjectTag) (${widget.fmtYmdHms(now)})';
      final filename = 'photo_transfer_api_logs_${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.md';

      // 필터 적용된 “에러” 로그를 보냄
      final keyLower = _searchCtrl.text.trim().toLowerCase();
      final toSend = _all.where((e) => _isError(e) && _tagMatches(e) && _searchMatches(e, keyLower)).toList();

      if (toSend.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('보낼 에러 로그가 없습니다.')));
        return;
      }

      final sb = StringBuffer()
        ..writeln('# PhotoTransfer 디버그 에러 로그(API)')
        ..writeln()
        ..writeln('- 생성 시각: ${widget.fmtYmdHms(now)}')
        ..writeln('- 필터(tag): $subjectTag')
        ..writeln('- 검색어: ${_searchCtrl.text.trim().isEmpty ? '-' : _searchCtrl.text.trim()}')
        ..writeln('- 총 에러 로그 수: ${toSend.length}')
        ..writeln('- 민감정보 마스킹: ${_maskSensitiveInEmail ? "ON" : "OFF"}')
        ..writeln()
        ..writeln('```json');

      for (final e in toSend.reversed) {
        final raw = e.original ?? e.message ?? '';
        sb.writeln(_maskSensitiveInEmail ? _sanitizeForEmail(raw) : raw);
      }
      sb.writeln('```');

      final attachmentBytes = Uint8List.fromList(utf8.encode(sb.toString()));

      await widget.onSendEmail(
        to: toCsv,
        subject: subject,
        body: '첨부된 Markdown 파일(API 에러 로그)을 확인해 주세요.',
        attachments: <_PickedAttachment>[
          _PickedAttachment(
            bytes: attachmentBytes,
            filename: filename,
            mimeType: 'text/markdown',
          ),
        ],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('디버그 로그를 이메일로 전송했습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그 전송 실패: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openDetail(_ApiLogEntry entry) async {
    final raw = (entry.original ?? entry.message ?? '').trim();
    final pretty = _prettyJsonIfPossible(raw);
    final insight = _inferInsight(entry);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.74,
              widthFactor: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '로그 상세',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              tooltip: '원문 복사',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: raw));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('원문이 복사되었습니다.')));
                              },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6)),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          children: [
                            _DetailCard(
                              title: '요약',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    insight.headline,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _Chip(text: entry.ts == null ? '-' : widget.fmtYmdHms(entry.ts!)),
                                      _Chip(text: insight.categoryLabel),
                                      _Chip(text: entry.tags.isEmpty ? 'untagged' : entry.tags.join(', ')),
                                    ],
                                  ),
                                  if (insight.primaryMessage.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    _MonoBox(text: insight.primaryMessage),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _DetailCard(
                              title: '권장 조치',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final a in insight.actions)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('• ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w900)),
                                          Expanded(child: Text(a)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _DetailCard(
                              title: '원문',
                              child: _MonoSelectableBox(text: pretty),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _prettyJsonIfPossible(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    try {
      final decoded = jsonDecode(t);
      const enc = JsonEncoder.withIndent('  ');
      return enc.convert(decoded);
    } catch (_) {
      return t;
    }
  }

  _ApiInsight _inferInsight(_ApiLogEntry e) {
    final raw = (e.original ?? e.message ?? '').trim();
    final msg = (e.message ?? '').trim();

    final hay = '${e.tags.join(' ')}\n$msg\n$raw'.toLowerCase();

    _ApiIssueCategory cat;
    if (hay.contains('timeoutexception') || hay.contains('timed out') || hay.contains('timeout')) {
      cat = _ApiIssueCategory.timeout;
    } else if (hay.contains('socketexception') ||
        hay.contains('failed host lookup') ||
        hay.contains('network is unreachable') ||
        hay.contains('connection refused') ||
        hay.contains('connection reset') ||
        hay.contains('dns') ||
        hay.contains('handshakeexception') ||
        hay.contains('certificate') ||
        hay.contains('tls')) {
      cat = _ApiIssueCategory.network;
    } else if (hay.contains('401') ||
        hay.contains('unauthorized') ||
        hay.contains('invalid_grant') ||
        (hay.contains('token') && (hay.contains('expired') || hay.contains('invalid'))) ||
        hay.contains('authentication')) {
      cat = _ApiIssueCategory.auth;
    } else if (hay.contains('403') || hay.contains('permission') || hay.contains('forbidden') || hay.contains('denied')) {
      cat = _ApiIssueCategory.permission;
    } else if (hay.contains('formatexception') ||
        (hay.contains('json') && hay.contains('decode')) ||
        hay.contains('unexpected character') ||
        (hay.contains('type') && hay.contains('is not a subtype'))) {
      cat = _ApiIssueCategory.parsing;
    } else if (hay.contains('nosuchmethoderror') ||
        hay.contains('null check operator used on a null value') ||
        hay.contains('type \'null\' is not a subtype')) {
      cat = _ApiIssueCategory.appLogic;
    } else {
      cat = _ApiIssueCategory.unknown;
    }

    final headline = _buildHeadline(cat, e);
    final primary = _oneLine(msg.isNotEmpty ? msg : raw, max: 280);

    final actions = _actionsFor(cat);

    return _ApiInsight(
      category: cat,
      headline: headline,
      actions: actions,
      primaryMessage: primary,
    );
  }

  String _buildHeadline(_ApiIssueCategory cat, _ApiLogEntry e) {
    switch (cat) {
      case _ApiIssueCategory.timeout:
        return '요청 시간 초과(Timeout) 가능성';
      case _ApiIssueCategory.network:
        return '네트워크/연결 오류 가능성';
      case _ApiIssueCategory.auth:
        return '인증 오류(토큰/세션) 가능성';
      case _ApiIssueCategory.permission:
        return '권한 오류(Forbidden/Denied) 가능성';
      case _ApiIssueCategory.parsing:
        return '파싱/타입 오류(응답 처리) 가능성';
      case _ApiIssueCategory.appLogic:
        return '앱 로직 예외(Null/NoSuchMethod) 가능성';
      case _ApiIssueCategory.unknown:
        return '분류 불가(원문 확인 필요)';
    }
  }

  List<String> _actionsFor(_ApiIssueCategory cat) {
    switch (cat) {
      case _ApiIssueCategory.timeout:
        return const [
          '네트워크 상태 확인 후 재시도(와이파이/데이터 전환)',
          '서버 처리 지연 여부 확인(동일 시각 서버 로그/모니터링)',
          '클라이언트 타임아웃/재시도 정책 점검',
        ];
      case _ApiIssueCategory.network:
        return const [
          '오프라인 여부/네트워크 전환 후 재시도',
          'DNS/프록시/방화벽 환경 확인',
          'TLS/인증서 오류 시 기기 시간 및 인증서 체인 확인',
        ];
      case _ApiIssueCategory.auth:
        return const [
          '로그아웃→로그인으로 토큰 재발급 유도',
          'OAuth 스코프/클라이언트 설정 점검',
          '401 발생 시점의 요청/응답(에러 코드) 확인',
        ];
      case _ApiIssueCategory.permission:
        return const [
          '403/Denied 발생 시 계정 권한(Role/ACL/Rules) 확인',
          '조직/계정 변경 후 동일 요청 재현',
          '권한 정책 변경 이력 확인',
        ];
      case _ApiIssueCategory.parsing:
        return const [
          '서버 응답 JSON 스키마와 파서/DTO 불일치 확인',
          'null/타입 변동에 대한 방어 코드 추가',
          '에러 응답(비정상 케이스) 파싱 경로 점검',
        ];
      case _ApiIssueCategory.appLogic:
        return const [
          '스택트레이스로 예외 발생 지점 확인',
          'nullable 처리 및 guard clause 강화',
          '실패 케이스 재현 후 테스트 추가',
        ];
      case _ApiIssueCategory.unknown:
        return const [
          '원문(stack/error/extra)을 확인하여 패턴을 추가하세요.',
          '로깅 payload에 status/url/method 등 구조화 필드를 포함시키는 것을 권장합니다.',
        ];
    }
  }

  String _oneLine(String s, {int max = 180}) {
    final t = s.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final totalCount = _filtered.length;
    final newestTs = _filtered.isNotEmpty ? _filtered.first.ts : null;
    final newestLabel = newestTs != null ? widget.fmtYmdHms(newestTs) : '-';

    return SafeArea(
      top: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Material(
              color: cs.surface,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.bug_report_rounded, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'API 디버그 로그',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '에러 로그(tag/검색) · 복사 · 삭제 · 메일 전송',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<_ApiDebugMenuAction>(
                          tooltip: '더보기',
                          onSelected: (action) async {
                            switch (action) {
                              case _ApiDebugMenuAction.toggleMasking:
                                setState(() => _maskSensitiveInEmail = !_maskSensitiveInEmail);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(_maskSensitiveInEmail ? '이메일 마스킹: ON' : '이메일 마스킹: OFF')),
                                );
                                break;

                              case _ApiDebugMenuAction.showConfigInfo:
                                try {
                                  final cfg = await EmailConfig.load();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('현재 To 설정: ${cfg.to.isEmpty ? '(비어있음)' : cfg.to}')),
                                  );
                                } catch (_) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('설정 정보를 불러오지 못했습니다.')));
                                }
                                break;
                            }
                          },
                          itemBuilder: (ctx) => <PopupMenuEntry<_ApiDebugMenuAction>>[
                            CheckedPopupMenuItem<_ApiDebugMenuAction>(
                              value: _ApiDebugMenuAction.toggleMasking,
                              checked: _maskSensitiveInEmail,
                              child: const Text('이메일 전송 시 민감정보 마스킹'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem<_ApiDebugMenuAction>(
                              value: _ApiDebugMenuAction.showConfigInfo,
                              child: Text('수신자(To) 설정 상태 보기'),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedTag,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest.withOpacity(0.55),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    prefixIcon: const Icon(Icons.sell_outlined),
                                    labelText: 'tag 선택',
                                  ),
                                  items: _availableTags.map((t) {
                                    final label = (t == _tagAll) ? '전체' : (t == _tagUntagged ? '(미지정)' : t);
                                    return DropdownMenuItem<String>(
                                      value: t,
                                      child: Text(label, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(growable: false),
                                  onChanged: _loading
                                      ? null
                                      : (v) {
                                    if (v == null) return;
                                    setState(() {
                                      _selectedTag = v;
                                      _applyFilter();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: '새로고침',
                                onPressed: _loading ? null : _load,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: '검색 (메시지 또는 시간: yyyy-MM-dd HH:mm:ss)',
                                    isDense: true,
                                    filled: true,
                                    fillColor: cs.surfaceContainerHighest.withOpacity(0.55),
                                    prefixIcon: const Icon(Icons.search_rounded),
                                    suffixIcon: _searchCtrl.text.isEmpty
                                        ? null
                                        : IconButton(
                                      tooltip: '검색어 지우기',
                                      onPressed: () => _searchCtrl.clear(),
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: '복사',
                                onPressed: (_loading || totalCount == 0) ? null : _copyFiltered,
                                icon: const Icon(Icons.copy_rounded),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: Row(
                            children: [
                              _Chip(text: '에러 $totalCount'),
                              const SizedBox(width: 8),
                              _Chip(text: '최신 $newestLabel'),
                              const Spacer(),
                              IconButton(
                                tooltip: _sending ? '전송 중...' : '이메일로 전송(필터 적용)',
                                onPressed: (_loading || _sending) ? null : _sendLogsByEmail,
                                icon: _sending
                                    ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : const Icon(Icons.send_rounded),
                              ),
                              IconButton(
                                tooltip: '전체 삭제',
                                onPressed: _loading ? null : _clearAll,
                                icon: Icon(Icons.delete_forever_rounded, color: cs.error),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _filtered.isEmpty
                              ? _EmptyList()
                              : RefreshIndicator(
                            onRefresh: _load,
                            child: Scrollbar(
                              controller: _listCtrl,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _listCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final e = _filtered[i];
                                  return _LogCard(
                                    entry: e,
                                    fmt: widget.fmtYmdHms,
                                    onTap: () => _openDetail(e),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ApiIssueCategory { timeout, network, auth, permission, parsing, appLogic, unknown }

class _ApiInsight {
  final _ApiIssueCategory category;
  final String headline;
  final List<String> actions;
  final String primaryMessage;

  _ApiInsight({
    required this.category,
    required this.headline,
    required this.actions,
    required this.primaryMessage,
  });

  String get categoryLabel {
    switch (category) {
      case _ApiIssueCategory.timeout:
        return 'Timeout';
      case _ApiIssueCategory.network:
        return 'Network';
      case _ApiIssueCategory.auth:
        return 'Auth';
      case _ApiIssueCategory.permission:
        return 'Permission';
      case _ApiIssueCategory.parsing:
        return 'Parsing';
      case _ApiIssueCategory.appLogic:
        return 'App';
      case _ApiIssueCategory.unknown:
        return 'Unknown';
    }
  }
}

class _ApiLogEntry {
  final DateTime? ts;
  final String? level;
  final String? message;
  final String? original;
  final List<String> tags;

  _ApiLogEntry({
    required this.ts,
    required this.level,
    required this.message,
    required this.original,
    required this.tags,
  });
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.entry,
    required this.fmt,
    required this.onTap,
  });

  final _ApiLogEntry entry;
  final String Function(DateTime dt) fmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = entry.ts != null ? fmt(entry.ts!) : '';
    final msg = (entry.message ?? '').trim();
    final tagLabel = entry.tags.isEmpty ? 'untagged' : entry.tags.join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.error_rounded, color: cs.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ts.isEmpty ? '시간 정보 없음' : ts,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        msg.isEmpty ? '(메시지 없음)' : msg,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          color: cs.onSurface,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tagLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 44, color: cs.onSurfaceVariant.withOpacity(0.7)),
            const SizedBox(height: 10),
            Text(
              '표시할 에러 로그가 없습니다.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '전송 실패 후 다시 열어보거나, 태그/검색 조건을 확인하세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MonoBox extends StatelessWidget {
  const _MonoBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(fontFamily: 'monospace', color: cs.onSurface, height: 1.25),
      ),
    );
  }
}

class _MonoSelectableBox extends StatelessWidget {
  const _MonoSelectableBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontFamily: 'monospace', color: cs.onSurface, height: 1.25, fontSize: 12.5),
      ),
    );
  }
}
