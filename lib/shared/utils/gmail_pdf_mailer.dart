import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../app/auth/google_auth_session.dart';
import '../../app/auth/google_auth_v7.dart';

class GmailPdfMailer {
  GmailPdfMailer._();

  static const int _base64LineLength = 76;
  static Future<void> sendPdf({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
    String fromName = 'ParkinWorkin',
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);

    try {
      final fromEmail = GoogleAuthSession.instance.currentUser?.email.trim();

      if (fromEmail == null || fromEmail.isEmpty) {
        throw StateError('Gmail 발신 계정 이메일을 확인할 수 없습니다.');
      }

      final api = gmail.GmailApi(client);
      final boundary = _createBoundary();
      final bodyBase64 = _wrapBase64Lines(base64.encode(utf8.encode(body)));
      final pdfBase64 = _wrapBase64Lines(base64.encode(pdfBytes));
      final encodedFilename = Uri.encodeComponent(_cleanHeaderValue(filename));
      final fallbackFilename = _asciiFallbackFilename(filename);
      const crlf = '\r\n';

      final mime = StringBuffer()
        ..write(
          'From: ${_formatMailbox(name: fromName, email: fromEmail)}$crlf',
        )
        ..write('To: ${_cleanAddressHeader(to)}$crlf')
        ..write('Subject: ${_encodeHeaderRfc2047(subject)}$crlf')
        ..write('MIME-Version: 1.0$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(bodyBase64)
        ..write('--$boundary$crlf')
        ..write(
          'Content-Type: application/pdf; name="$fallbackFilename"; name*=UTF-8\'\'$encodedFilename$crlf',
        )
        ..write(
          'Content-Disposition: attachment; filename="$fallbackFilename"; filename*=UTF-8\'\'$encodedFilename$crlf',
        )
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(pdfBase64)
        ..write('--$boundary--$crlf');

      final raw = base64UrlEncode(utf8.encode(mime.toString())).replaceAll(
        '=',
        '',
      );

      await api.users.messages.send(gmail.Message()..raw = raw, 'me');
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  static String _createBoundary() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'dart-mail-boundary-$now';
  }

  static String _wrapBase64Lines(String base64Text) {
    if (base64Text.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < base64Text.length; i += _base64LineLength) {
      final end = i + _base64LineLength < base64Text.length
          ? i + _base64LineLength
          : base64Text.length;
      buffer.write(base64Text.substring(i, end));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  static String _encodeHeaderRfc2047(String value) {
    final cleaned = _cleanHeaderValue(value);
    final encoded = base64.encode(utf8.encode(cleaned));
    return '=?UTF-8?B?$encoded?=';
  }

  static String _formatMailbox({
    required String name,
    required String email,
  }) {
    final safeEmail = email.replaceAll(RegExp(r'[\r\n<>]'), '').trim();
    return '${_encodeHeaderRfc2047(name)} <$safeEmail>';
  }

  static String _cleanAddressHeader(String value) {
    return value.replaceAll(RegExp(r'[\r\n]'), ', ').trim();
  }

  static String _cleanHeaderValue(String value) {
    return value.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
  }

  static String _asciiFallbackFilename(String filename) {
    final cleaned = _cleanHeaderValue(filename).replaceAll('"', '');
    final safe = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final compact = safe.replaceAll(RegExp(r'_+'), '_').trim();

    if (compact.isEmpty) return 'attachment.pdf';
    if (compact.toLowerCase().endsWith('.pdf')) return compact;
    return '$compact.pdf';
  }
}
