// lib/utils/calendar_excel_mailer.dart
import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../../utils/api/email_config.dart';
import '../../../../../utils/google_auth_session.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

class CalendarExcelMailer {
  CalendarExcelMailer._();

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tCal = 'calendar';
  static const String _tMailer = 'calendar/excel_mailer';
  static const String _tExcel = 'calendar/excel';
  static const String _tEmail = 'calendar/email';
  static const String _tGmail = 'gmail/send';
  static const String _tConfig = 'email_config';

  static Future<void> _logApiError({
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
      // 로깅 실패는 기능에 영향 없도록 무시
    }
  }

  /// 출석(출근/퇴근) 월간 데이터를 엑셀로 생성해 메일 발송
  ///
  /// 엑셀 포맷(요구사항 반영):
  /// - A1: 사용자명
  /// - B2..AF2: 1일~31일 (가로)
  /// - A3: 출근
  /// - A4: 퇴근
  /// - B3..AF3: 1일~말일 출근 시간(가로)
  /// - B4..AF4: 1일~말일 퇴근 시간(가로)
  ///
  /// 주의:
  /// - 2행의 날짜 헤더는 항상 1~31까지 고정으로 채웁니다.
  /// - 실제 월의 말일(lastDay) 이후(예: 2월의 29~31)는 값이 비어있습니다.
  static Future<void> sendAttendanceMonthExcel({
    required int year,
    required int month,
    required String userId,
    required String userName,
    required Map<int, String> clockInByDay,
    required Map<int, String> clockOutByDay,
    String? subject,
    String? body,
  }) async {
    final cfg = await EmailConfig.load();
    final to = cfg.to.trim();

    if (!EmailConfig.isValidToList(to)) {
      await _logApiError(
        tag: 'CalendarExcelMailer.sendAttendanceMonthExcel',
        message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
        error: StateError('invalid_to'),
        extra: <String, dynamic>{'toRaw': cfg.to},
        tags: const <String>[_tCal, _tMailer, _tEmail, _tConfig],
      );
      throw StateError('메일 수신자(To) 설정이 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 먼저 등록하세요.');
    }

    // 세션 차단 상태면 전송 불가(디버그 안전)
    if (GoogleAuthSession.instance.isSessionBlocked) {
      await _logApiError(
        tag: 'CalendarExcelMailer.sendAttendanceMonthExcel',
        message: '구글 세션 차단(ON) 상태로 이메일 전송 차단됨',
        error: StateError('google_session_blocked'),
        extra: <String, dynamic>{'year': year, 'month': month},
        tags: const <String>[_tCal, _tMailer, _tEmail],
      );
      throw StateError('구글 세션 차단(ON) 상태입니다. 전송을 위해 OFF로 변경해 주세요.');
    }

    List<int> bytes;
    try {
      bytes = _buildAttendanceExcelBytes(
        year: year,
        month: month,
        userId: userId,
        userName: userName,
        clockInByDay: clockInByDay,
        clockOutByDay: clockOutByDay,
      );
    } catch (e) {
      await _logApiError(
        tag: 'CalendarExcelMailer.sendAttendanceMonthExcel',
        message: '출석 엑셀 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'year': year,
          'month': month,
          'userIdLen': userId.length,
          'userNameLen': userName.length,
          'inDays': clockInByDay.length,
          'outDays': clockOutByDay.length,
        },
        tags: const <String>[_tCal, _tMailer, _tExcel],
      );
      rethrow;
    }

    final ym = '${year}${month.toString().padLeft(2, '0')}';
    final safeUserId = _sanitizeFilePart(userId);
    final filename = 'attendance_${safeUserId}_$ym.xlsx';

    final finalSubject = subject ?? '[출석] $userName ($userId) $ym';
    final finalBody = body ??
        '첨부된 엑셀 파일에 $year-${month.toString().padLeft(2, '0')} 출근/퇴근 데이터가 포함되어 있습니다.\n'
            '- A1: 사용자명\n'
            '- 2행: 1일~31일 헤더(B2~AF2)\n'
            '- A3: 출근, A4: 퇴근\n'
            '- 3~4행에 B열부터(=1일) 가로로 시간 값이 입력됩니다.\n';

    await _sendGmailWithAttachment(
      toCsv: to,
      subject: finalSubject,
      body: finalBody,
      filename: filename,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      attachmentBytes: bytes,
      debugExtra: <String, dynamic>{
        'kind': 'attendance',
        'year': year,
        'month': month,
        'userIdLen': userId.length,
        'userNameLen': userName.length,
        'bytes': bytes.length,
      },
    );
  }

  /// 휴게 월간 데이터를 엑셀로 생성해 메일 발송
  ///
  /// 엑셀 포맷:
  /// - A1: 휴게
  /// - B1..: 1일~말일 휴게 시간(가로)
  static Future<void> sendBreakMonthExcel({
    required int year,
    required int month,
    required String userId,
    required String userName,
    required Map<int, String> breakByDay,
    String? subject,
    String? body,
  }) async {
    final cfg = await EmailConfig.load();
    final to = cfg.to.trim();

    if (!EmailConfig.isValidToList(to)) {
      await _logApiError(
        tag: 'CalendarExcelMailer.sendBreakMonthExcel',
        message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
        error: StateError('invalid_to'),
        extra: <String, dynamic>{'toRaw': cfg.to},
        tags: const <String>[_tCal, _tMailer, _tEmail, _tConfig],
      );
      throw StateError('메일 수신자(To) 설정이 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 먼저 등록하세요.');
    }

    if (GoogleAuthSession.instance.isSessionBlocked) {
      await _logApiError(
        tag: 'CalendarExcelMailer.sendBreakMonthExcel',
        message: '구글 세션 차단(ON) 상태로 이메일 전송 차단됨',
        error: StateError('google_session_blocked'),
        extra: <String, dynamic>{'year': year, 'month': month},
        tags: const <String>[_tCal, _tMailer, _tEmail],
      );
      throw StateError('구글 세션 차단(ON) 상태입니다. 전송을 위해 OFF로 변경해 주세요.');
    }

    List<int> bytes;
    try {
      bytes = _buildBreakExcelBytes(
        year: year,
        month: month,
        userId: userId,
        userName: userName,
        breakByDay: breakByDay,
      );
    } catch (e) {
      await _logApiError(
        tag: 'CalendarExcelMailer.sendBreakMonthExcel',
        message: '휴게 엑셀 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'year': year,
          'month': month,
          'userIdLen': userId.length,
          'userNameLen': userName.length,
          'breakDays': breakByDay.length,
        },
        tags: const <String>[_tCal, _tMailer, _tExcel],
      );
      rethrow;
    }

    final ym = '${year}${month.toString().padLeft(2, '0')}';
    final safeUserId = _sanitizeFilePart(userId);
    final filename = 'break_${safeUserId}_$ym.xlsx';

    final finalSubject = subject ?? '[휴게] $userName ($userId) $ym';
    final finalBody = body ??
        '첨부된 엑셀 파일에 $year-${month.toString().padLeft(2, '0')} 휴게 데이터가 포함되어 있습니다.\n'
            '- A1: 휴게\n'
            '- B열부터 1일~말일까지 가로로 시간 값이 입력됩니다.\n';

    await _sendGmailWithAttachment(
      toCsv: to,
      subject: finalSubject,
      body: finalBody,
      filename: filename,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      attachmentBytes: bytes,
      debugExtra: <String, dynamic>{
        'kind': 'break',
        'year': year,
        'month': month,
        'userIdLen': userId.length,
        'userNameLen': userName.length,
        'bytes': bytes.length,
      },
    );
  }

  static List<int> _buildAttendanceExcelBytes({
    required int year,
    required int month,
    required String userId,
    required String userName,
    required Map<int, String> clockInByDay,
    required Map<int, String> clockOutByDay,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['attendance'];

    const headerDays = 31;

    const rowUser = 0;
    const rowHeader = 1;
    const rowIn = 2;
    const rowOut = 3;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowUser)).value =
        TextCellValue(userName);

    for (var day = 1; day <= headerDays; day++) {
      final col = day; // 1일 -> B(1)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowHeader)).value =
          IntCellValue(day);
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIn)).value =
        TextCellValue('출근');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowOut)).value =
        TextCellValue('퇴근');

    final lastDay = DateTime(year, month + 1, 0).day;
    final maxFillDay = lastDay > headerDays ? headerDays : lastDay;

    for (var day = 1; day <= maxFillDay; day++) {
      final col = day;
      final inT = (clockInByDay[day] ?? '').trim();
      final outT = (clockOutByDay[day] ?? '').trim();

      if (inT.isNotEmpty) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIn)).value =
            TextCellValue(inT);
      }
      if (outT.isNotEmpty) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowOut)).value =
            TextCellValue(outT);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) throw StateError('엑셀 인코딩 실패');
    return bytes;
  }

  static List<int> _buildBreakExcelBytes({
    required int year,
    required int month,
    required String userId,
    required String userName,
    required Map<int, String> breakByDay,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['break'];

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('휴게');

    final lastDay = DateTime(year, month + 1, 0).day;

    for (var day = 1; day <= lastDay; day++) {
      final col = day; // 1일 -> B
      final t = (breakByDay[day] ?? '').trim();
      if (t.isNotEmpty) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).value = TextCellValue(t);
      }
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('user');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('$userName ($userId)');

    final bytes = excel.encode();
    if (bytes == null) throw StateError('엑셀 인코딩 실패');
    return bytes;
  }

  static Future<void> _sendGmailWithAttachment({
    required String toCsv,
    required String subject,
    required String body,
    required String filename,
    required String mimeType,
    required List<int> attachmentBytes,
    Map<String, dynamic>? debugExtra,
  }) async {
    try {
      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);

      final boundary = '----easydev_${DateTime.now().millisecondsSinceEpoch}';

      // ✅ base64는 76자 wrap + CRLF
      final attachmentB64 = _wrapBase64(base64.encode(attachmentBytes));

      // ✅ MIME는 CRLF가 더 호환이 좋음
      const crlf = '\r\n';
      final mime = StringBuffer()
        ..write('MIME-Version: 1.0$crlf')
        ..write('To: $toCsv$crlf')
        ..write('Subject: ${_encodeHeaderIfNeeded(subject)}$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="UTF-8"$crlf')
        ..write('Content-Transfer-Encoding: 7bit$crlf')
        ..write(crlf)
        ..write(body)
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: $mimeType; name="$filename"$crlf')
        ..write('Content-Disposition: attachment; filename="$filename"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(attachmentB64)
        ..write('--$boundary--$crlf');

      final raw = _base64UrlNoPad(utf8.encode(mime.toString()));

      final msg = gmail.Message()..raw = raw;
      await api.users.messages.send(msg, 'me');
    } catch (e) {
      await _logApiError(
        tag: 'CalendarExcelMailer._sendGmailWithAttachment',
        message: 'Gmail 첨부 메일 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': toCsv.trim().length,
          'subjectLen': subject.trim().length,
          'filename': filename,
          'mimeType': mimeType,
          'bytes': attachmentBytes.length,
          if (debugExtra != null) ...debugExtra,
        },
        tags: const <String>[_tCal, _tMailer, _tEmail, _tGmail],
      );
      rethrow;
    }
  }

  static String _base64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// base64 첨부는 76자 줄바꿈이 가장 호환이 좋음
  static String _wrapBase64(String input, {int lineLength = 76}) {
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i += lineLength) {
      final end = (i + lineLength < input.length) ? i + lineLength : input.length;
      sb.write(input.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  /// 제목에 한글이 들어갈 수 있으므로 최소한의 RFC 2047 인코딩(UTF-8 Base64)
  static String _encodeHeaderIfNeeded(String s) {
    final hasNonAscii = s.codeUnits.any((c) => c > 127);
    if (!hasNonAscii) return s;
    final b64 = base64.encode(utf8.encode(s));
    return '=?UTF-8?B?$b64?=';
  }

  static String _sanitizeFilePart(String s) {
    return s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }
}
