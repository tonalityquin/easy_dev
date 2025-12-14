// lib/utils/calendar_excel_mailer.dart
import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../../utils/api/email_config.dart';
import '../../../../../utils/google_auth_session.dart';

class CalendarExcelMailer {
  CalendarExcelMailer._();

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
      throw StateError('메일 수신자(To) 설정이 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 먼저 등록하세요.');
    }

    final bytes = _buildAttendanceExcelBytes(
      year: year,
      month: month,
      userId: userId,
      userName: userName,
      clockInByDay: clockInByDay,
      clockOutByDay: clockOutByDay,
    );

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
      throw StateError('메일 수신자(To) 설정이 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 먼저 등록하세요.');
    }

    final bytes = _buildBreakExcelBytes(
      year: year,
      month: month,
      userId: userId,
      userName: userName,
      breakByDay: breakByDay,
    );

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

    // 고정 규격: 1~31일까지 헤더를 항상 만듦
    const headerDays = 31;

    // Row indices (0-based)
    // 1행(A1) -> rowIndex 0
    // 2행(날짜헤더) -> rowIndex 1
    // 3행(출근) -> rowIndex 2
    // 4행(퇴근) -> rowIndex 3
    const rowUser = 0;
    const rowHeader = 1;
    const rowIn = 2;
    const rowOut = 3;

    // A1: 사용자명
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowUser)).value =
        TextCellValue(userName);

    // 2행: 1~31일 헤더 (B2..AF2)
    for (var day = 1; day <= headerDays; day++) {
      final col = day; // 1일 -> B(1)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowHeader)).value =
          IntCellValue(day);
    }

    // A3/A4: 출근/퇴근 라벨
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIn)).value =
        TextCellValue('출근');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowOut)).value =
        TextCellValue('퇴근');

    final lastDay = DateTime(year, month + 1, 0).day;
    final maxFillDay = lastDay > headerDays ? headerDays : lastDay;

    // B열부터(=columnIndex 1) 1일~말일까지 가로 채움 (3~4행)
    for (var day = 1; day <= maxFillDay; day++) {
      final col = day; // 1일 -> B(1), 2일 -> C(2) ...
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

    // A1
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('휴게');

    final lastDay = DateTime(year, month + 1, 0).day;

    // B열부터 가로 채움
    for (var day = 1; day <= lastDay; day++) {
      final col = day; // 1일 -> B
      final t = (breakByDay[day] ?? '').trim();
      if (t.isNotEmpty) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
            .value = TextCellValue(t);
      }
    }

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
        .value = TextCellValue('user');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
        .value = TextCellValue('$userName ($userId)');

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
  }) async {
    final client = await GoogleAuthSession.instance.safeClient();
    final api = gmail.GmailApi(client);

    final boundary = '----easydev_${DateTime.now().millisecondsSinceEpoch}';

    final attachmentB64 = _wrapBase64(base64.encode(attachmentBytes));

    final mime = StringBuffer()
      ..writeln('To: $toCsv')
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
      ..writeln('Content-Type: $mimeType; name="$filename"')
      ..writeln('Content-Disposition: attachment; filename="$filename"')
      ..writeln('Content-Transfer-Encoding: base64')
      ..writeln()
      ..writeln(attachmentB64)
      ..writeln('--$boundary--');

    final raw = _base64UrlNoPad(utf8.encode(mime.toString()));

    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }

  static String _base64UrlNoPad(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// base64 첨부는 76자 줄바꿈이 가장 호환이 좋음
  static String _wrapBase64(String input, {int lineLength = 76}) {
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i += lineLength) {
      final end = (i + lineLength < input.length) ? i + lineLength : input.length;
      sb.writeln(input.substring(i, end));
    }
    return sb.toString().trimRight();
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
