import 'dart:math' as math;

class StatisticsDeepReport {
  final String division;
  final String area;
  final String scopeLabel;
  final List<String> dateStrs;
  final List<StatisticsDeepVehicleRow> rows;
  final List<String> objectNames;
  final StatisticsDeepSection overallSection;
  final List<StatisticsDeepSection> dailySections;
  final List<StatisticsDeepSection> weekdaySections;
  final List<StatisticsDeepTocItem> tocItems;

  const StatisticsDeepReport({
    required this.division,
    required this.area,
    required this.scopeLabel,
    required this.dateStrs,
    required this.rows,
    required this.objectNames,
    required this.overallSection,
    required this.dailySections,
    required this.weekdaySections,
    required this.tocItems,
  });

  factory StatisticsDeepReport.fromRows({
    required String division,
    required String area,
    required String scopeLabel,
    required List<StatisticsDeepVehicleRow> rows,
    required List<String> objectNames,
    List<String>? dateStrs,
  }) {
    final sortedRows = rows.toList()
      ..sort((a, b) {
        final dateCmp = a.dateStr.compareTo(b.dateStr);
        if (dateCmp != 0) return dateCmp;
        final at = a.departureAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.departureAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final timeCmp = at.compareTo(bt);
        if (timeCmp != 0) return timeCmp;
        return a.plateNumber.compareTo(b.plateNumber);
      });

    final normalizedRows = <StatisticsDeepVehicleRow>[];
    for (int i = 0; i < sortedRows.length; i++) {
      normalizedRows.add(sortedRows[i].copyWith(no: i + 1));
    }

    final normalizedDateStrs = (dateStrs ?? normalizedRows.map((e) => e.dateStr))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toSet()
        .toList()
      ..sort();

    final overall = StatisticsDeepSection.fromRows(
      id: 'overall',
      title: '전체 심화 통계',
      subtitle: scopeLabel,
      type: StatisticsDeepSectionType.overall,
      rows: normalizedRows,
      dateStrs: normalizedDateStrs,
      showAverageCharts: true,
      sourceDateCount: normalizedDateStrs.length,
    );

    final daily = <StatisticsDeepSection>[];
    for (final dateStr in normalizedDateStrs) {
      final sectionRows = normalizedRows.where((row) => row.dateStr == dateStr).toList();
      daily.add(
        StatisticsDeepSection.fromRows(
          id: 'date_$dateStr',
          title: '$dateStr 심화 통계',
          subtitle: _weekdayName(_weekdayOfDateStr(dateStr)),
          type: StatisticsDeepSectionType.date,
          rows: sectionRows,
          dateStrs: <String>[dateStr],
          showAverageCharts: false,
          sourceDateCount: 1,
        ),
      );
    }

    final weekdaySections = <StatisticsDeepSection>[];
    final datesByWeekday = <int, List<String>>{};
    for (final dateStr in normalizedDateStrs) {
      final weekday = _weekdayOfDateStr(dateStr);
      if (weekday == 0) continue;
      datesByWeekday.putIfAbsent(weekday, () => <String>[]).add(dateStr);
    }

    final weekdayKeys = datesByWeekday.keys.toList()..sort();
    for (final weekday in weekdayKeys) {
      final weekdayDateStrs = datesByWeekday[weekday]!..sort();
      if (weekdayDateStrs.length < 2) continue;
      final set = weekdayDateStrs.toSet();
      final sectionRows = normalizedRows.where((row) => set.contains(row.dateStr)).toList();
      weekdaySections.add(
        StatisticsDeepSection.fromRows(
          id: 'weekday_$weekday',
          title: '${_weekdayName(weekday)}요일 심화 통계',
          subtitle: '${weekdayDateStrs.first} ~ ${weekdayDateStrs.last} / ${weekdayDateStrs.length}일',
          type: StatisticsDeepSectionType.weekday,
          rows: sectionRows,
          dateStrs: weekdayDateStrs,
          showAverageCharts: true,
          sourceDateCount: weekdayDateStrs.length,
        ),
      );
    }

    final toc = <StatisticsDeepTocItem>[
      const StatisticsDeepTocItem(id: 'cover', title: '표지', level: 0),
      const StatisticsDeepTocItem(id: 'summary', title: '요약', level: 0),
      StatisticsDeepTocItem(id: overall.id, title: overall.title, level: 0),
      const StatisticsDeepTocItem(id: 'daily_group', title: '날짜별 심화 통계', level: 0, isGroup: true),
      for (final section in daily)
        StatisticsDeepTocItem(id: section.id, title: section.title, level: 1),
      if (weekdaySections.isNotEmpty)
        const StatisticsDeepTocItem(id: 'weekday_group', title: '요일별 심화 통계', level: 0, isGroup: true),
      for (final section in weekdaySections)
        StatisticsDeepTocItem(id: section.id, title: section.title, level: 1),
    ];

    return StatisticsDeepReport(
      division: division,
      area: area,
      scopeLabel: scopeLabel,
      dateStrs: normalizedDateStrs,
      rows: normalizedRows,
      objectNames: objectNames,
      overallSection: overall,
      dailySections: daily,
      weekdaySections: weekdaySections,
      tocItems: toc,
    );
  }

  List<StatisticsDeepSection> get sections => <StatisticsDeepSection>[
        overallSection,
        ...dailySections,
        ...weekdaySections,
      ];

  int get totalInput => overallSection.metrics.inputTotalSum;

  int get totalOutput => overallSection.metrics.outputTotalSum;

  int get totalFee => rows.fold<int>(0, (sum, row) => sum + (row.fee ?? 0));
}

class StatisticsDeepSection {
  final String id;
  final String title;
  final String subtitle;
  final StatisticsDeepSectionType type;
  final List<String> dateStrs;
  final int sourceDateCount;
  final bool showAverageCharts;
  final List<StatisticsDeepVehicleRow> rows;
  final StatisticsDeepHourlyMetrics metrics;

  const StatisticsDeepSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.dateStrs,
    required this.sourceDateCount,
    required this.showAverageCharts,
    required this.rows,
    required this.metrics,
  });

  factory StatisticsDeepSection.fromRows({
    required String id,
    required String title,
    required String subtitle,
    required StatisticsDeepSectionType type,
    required List<StatisticsDeepVehicleRow> rows,
    required List<String> dateStrs,
    required bool showAverageCharts,
    required int sourceDateCount,
  }) {
    final normalizedRows = <StatisticsDeepVehicleRow>[];
    for (int i = 0; i < rows.length; i++) {
      normalizedRows.add(rows[i].copyWith(no: i + 1));
    }

    return StatisticsDeepSection(
      id: id,
      title: title,
      subtitle: subtitle,
      type: type,
      dateStrs: dateStrs,
      sourceDateCount: math.max(sourceDateCount, 1),
      showAverageCharts: showAverageCharts,
      rows: normalizedRows,
      metrics: StatisticsDeepHourlyMetrics.fromRows(
        rows: normalizedRows,
        denominator: math.max(sourceDateCount, 1),
      ),
    );
  }

  int get totalFee => rows.fold<int>(0, (sum, row) => sum + (row.fee ?? 0));
}

enum StatisticsDeepSectionType { overall, date, weekday }

class StatisticsDeepHourlyMetrics {
  final List<int> inputTotalCounts;
  final List<int> outputTotalCounts;
  final List<double> inputAverageCounts;
  final List<double> outputAverageCounts;

  const StatisticsDeepHourlyMetrics({
    required this.inputTotalCounts,
    required this.outputTotalCounts,
    required this.inputAverageCounts,
    required this.outputAverageCounts,
  });

  factory StatisticsDeepHourlyMetrics.fromRows({
    required List<StatisticsDeepVehicleRow> rows,
    required int denominator,
  }) {
    final input = List<int>.filled(24, 0);
    final output = List<int>.filled(24, 0);

    for (final row in rows) {
      final createdAt = row.createdAt;
      final departureAt = row.departureAt;
      if (createdAt != null) input[createdAt.hour]++;
      if (departureAt != null) output[departureAt.hour]++;
    }

    final divisor = denominator <= 0 ? 1 : denominator;
    return StatisticsDeepHourlyMetrics(
      inputTotalCounts: input,
      outputTotalCounts: output,
      inputAverageCounts: input.map((value) => value / divisor).toList(),
      outputAverageCounts: output.map((value) => value / divisor).toList(),
    );
  }

  int get inputTotalSum => inputTotalCounts.fold<int>(0, (p, e) => p + e);

  int get outputTotalSum => outputTotalCounts.fold<int>(0, (p, e) => p + e);

  double get inputAverageSum => inputAverageCounts.fold<double>(0, (p, e) => p + e);

  double get outputAverageSum => outputAverageCounts.fold<double>(0, (p, e) => p + e);
}

class StatisticsDeepTocItem {
  final String id;
  final String title;
  final int level;
  final bool isGroup;

  const StatisticsDeepTocItem({
    required this.id,
    required this.title,
    required this.level,
    this.isGroup = false,
  });
}

class StatisticsDeepVehicleRow {
  final int no;
  final String dateStr;
  final String plateNumber;
  final DateTime? createdAt;
  final DateTime? departureAt;
  final int? fee;
  final String docId;

  const StatisticsDeepVehicleRow({
    required this.no,
    required this.dateStr,
    required this.plateNumber,
    required this.createdAt,
    required this.departureAt,
    required this.fee,
    required this.docId,
  });

  StatisticsDeepVehicleRow copyWith({
    int? no,
    String? dateStr,
    String? plateNumber,
    DateTime? createdAt,
    DateTime? departureAt,
    int? fee,
    String? docId,
  }) {
    return StatisticsDeepVehicleRow(
      no: no ?? this.no,
      dateStr: dateStr ?? this.dateStr,
      plateNumber: plateNumber ?? this.plateNumber,
      createdAt: createdAt ?? this.createdAt,
      departureAt: departureAt ?? this.departureAt,
      fee: fee ?? this.fee,
      docId: docId ?? this.docId,
    );
  }
}

int _weekdayOfDateStr(String dateStr) {
  final parsed = DateTime.tryParse(dateStr);
  return parsed?.weekday ?? 0;
}

String _weekdayName(int weekday) {
  switch (weekday) {
    case 1:
      return '월';
    case 2:
      return '화';
    case 3:
      return '수';
    case 4:
      return '목';
    case 5:
      return '금';
    case 6:
      return '토';
    case 7:
      return '일';
  }
  return '-';
}
