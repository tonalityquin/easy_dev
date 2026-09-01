import 'dart:convert';
import 'dart:typed_data';

import 'statistics_deep_model.dart';

class StatisticsVehicleLogCsvResult {
  final Uint8List bytes;
  final int rowCount;

  const StatisticsVehicleLogCsvResult({
    required this.bytes,
    required this.rowCount,
  });
}

class StatisticsVehicleLogCsv {
  static StatisticsVehicleLogCsvResult build(StatisticsDeepReport report) {
    final buffer = StringBuffer();
    buffer.writeln(
      <String>[
        'No',
        '날짜',
        '차량 번호',
        '방문 구역',
        '방문 구역 상태',
        '입차 시간',
        '출차 시간',
        '출차 시간 상태',
        '정산 금액',
        '결제수단',
        '문서 ID',
      ].map(_csvCell).join(','),
    );

    for (final row in report.rows) {
      buffer.writeln(
        <String>[
          row.no.toString(),
          row.dateStr,
          _safeSpreadsheetText(row.plateNumber),
          _safeSpreadsheetText(row.sectorLabel),
          _sectorStateLabel(row.sectorState),
          _time(row.createdAt),
          _time(row.departureAt),
          _departureStateLabel(row.departureTimeSource),
          row.fee?.toString() ?? '',
          _safeSpreadsheetText(row.paymentMethodLabel),
          _safeSpreadsheetText(row.docId),
        ].map(_csvCell).join(','),
      );
    }

    final contentBytes = utf8.encode(buffer.toString());
    final bytes = Uint8List(3 + contentBytes.length)
      ..setRange(0, 3, const <int>[0xEF, 0xBB, 0xBF])
      ..setRange(3, 3 + contentBytes.length, contentBytes);
    return StatisticsVehicleLogCsvResult(
      bytes: bytes,
      rowCount: report.rows.length,
    );
  }

  static String _csvCell(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.contains(',') ||
        normalized.contains('"') ||
        normalized.contains('\n')) {
      final escaped = normalized.replaceAll('"', '""');
      return '"$escaped"';
    }
    return normalized;
  }

  static String _safeSpreadsheetText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    final first = normalized.codeUnitAt(0);
    if (first == 0x3D || first == 0x2B || first == 0x2D || first == 0x40) {
      return "'$normalized";
    }
    return normalized;
  }

  static String _time(DateTime? value) {
    if (value == null) return '';
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String _sectorStateLabel(StatisticsSectorState state) {
    switch (state) {
      case StatisticsSectorState.assigned:
        return '정상';
      case StatisticsSectorState.unassigned:
        return '미지정';
      case StatisticsSectorState.invalid:
        return '확인 필요';
      case StatisticsSectorState.unavailable:
        return '원천 없음';
    }
  }

  static String _departureStateLabel(StatisticsDepartureTimeSource source) {
    switch (source) {
      case StatisticsDepartureTimeSource.completedAt:
        return '출차 완료';
      case StatisticsDepartureTimeSource.departureLog:
        return '출차 로그';
      case StatisticsDepartureTimeSource.lastLogFallback:
        return '추정';
      case StatisticsDepartureTimeSource.missing:
        return '없음';
    }
  }
}
