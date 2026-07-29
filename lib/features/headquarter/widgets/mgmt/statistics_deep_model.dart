import 'dart:math' as math;

enum StatisticsSectorState {
  assigned,
  unassigned,
  invalid,
  unavailable,
}

enum StatisticsDepartureTimeSource {
  completedAt,
  departureLog,
  lastLogFallback,
  missing,
}

class StatisticsDeepDiagnostics {
  final int sourceObjectCount;
  final int sourceCsvRowCount;
  final int mergedVehicleCount;
  final int duplicateMergedCount;
  final int sectorConflictCount;
  final int sectorIdentityConflictCount;
  final int sectorFieldPresentCount;
  final int sectorFieldMissingCount;

  const StatisticsDeepDiagnostics({
    required this.sourceObjectCount,
    required this.sourceCsvRowCount,
    required this.mergedVehicleCount,
    required this.duplicateMergedCount,
    required this.sectorConflictCount,
    required this.sectorIdentityConflictCount,
    required this.sectorFieldPresentCount,
    required this.sectorFieldMissingCount,
  });

  const StatisticsDeepDiagnostics.empty()
      : sourceObjectCount = 0,
        sourceCsvRowCount = 0,
        mergedVehicleCount = 0,
        duplicateMergedCount = 0,
        sectorConflictCount = 0,
        sectorIdentityConflictCount = 0,
        sectorFieldPresentCount = 0,
        sectorFieldMissingCount = 0;

  StatisticsDeepDiagnostics copyWith({
    int? sourceObjectCount,
    int? sourceCsvRowCount,
    int? mergedVehicleCount,
    int? duplicateMergedCount,
    int? sectorConflictCount,
    int? sectorIdentityConflictCount,
    int? sectorFieldPresentCount,
    int? sectorFieldMissingCount,
  }) {
    return StatisticsDeepDiagnostics(
      sourceObjectCount: sourceObjectCount ?? this.sourceObjectCount,
      sourceCsvRowCount: sourceCsvRowCount ?? this.sourceCsvRowCount,
      mergedVehicleCount: mergedVehicleCount ?? this.mergedVehicleCount,
      duplicateMergedCount: duplicateMergedCount ?? this.duplicateMergedCount,
      sectorConflictCount: sectorConflictCount ?? this.sectorConflictCount,
      sectorIdentityConflictCount:
          sectorIdentityConflictCount ?? this.sectorIdentityConflictCount,
      sectorFieldPresentCount:
          sectorFieldPresentCount ?? this.sectorFieldPresentCount,
      sectorFieldMissingCount:
          sectorFieldMissingCount ?? this.sectorFieldMissingCount,
    );
  }
}

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
  final bool sectorEnabled;
  final StatisticsSectorReport? sectorReport;
  final StatisticsDeepDiagnostics diagnostics;

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
    required this.sectorEnabled,
    required this.sectorReport,
    required this.diagnostics,
  });

  factory StatisticsDeepReport.fromRows({
    required String division,
    required String area,
    required String scopeLabel,
    required List<StatisticsDeepVehicleRow> rows,
    required List<String> objectNames,
    List<String>? dateStrs,
    bool sectorEnabled = false,
    StatisticsDeepDiagnostics diagnostics = const StatisticsDeepDiagnostics.empty(),
  }) {
    final sortedRows = rows.toList()
      ..sort((a, b) {
        final dateCmp = a.dateStr.compareTo(b.dateStr);
        if (dateCmp != 0) return dateCmp;
        final at = a.departureAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.departureAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final timeCmp = at.compareTo(bt);
        if (timeCmp != 0) return timeCmp;
        return a.plateNumber.compareTo(b.plateNumber);
      });

    final conflictingSectorIds = _sectorIdsWithNameConflicts(sortedRows);
    final normalizedRows = <StatisticsDeepVehicleRow>[
      for (int i = 0; i < sortedRows.length; i++)
        sortedRows[i].copyWith(
          no: i + 1,
          sectorIdentityConflict: conflictingSectorIds.contains(
            sortedRows[i].normalizedSectorId,
          ),
        ),
    ];
    final effectiveDiagnostics = diagnostics.copyWith(
      sectorIdentityConflictCount: normalizedRows
          .where((row) => row.sectorIdentityConflict)
          .length,
      sectorFieldPresentCount:
          normalizedRows.where((row) => row.sectorFieldsPresent).length,
      sectorFieldMissingCount:
          normalizedRows.where((row) => !row.sectorFieldsPresent).length,
    );

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
      final sectionRows = normalizedRows
          .where((row) => row.dateStr == dateStr)
          .toList();
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
      final sectionRows = normalizedRows
          .where((row) => set.contains(row.dateStr))
          .toList();
      weekdaySections.add(
        StatisticsDeepSection.fromRows(
          id: 'weekday_$weekday',
          title: '${_weekdayName(weekday)}요일 심화 통계',
          subtitle:
              '${weekdayDateStrs.first} ~ ${weekdayDateStrs.last} / ${weekdayDateStrs.length}일',
          type: StatisticsDeepSectionType.weekday,
          rows: sectionRows,
          dateStrs: weekdayDateStrs,
          showAverageCharts: true,
          sourceDateCount: weekdayDateStrs.length,
        ),
      );
    }

    final sector = sectorEnabled
        ? StatisticsSectorReport.fromRows(
            rows: normalizedRows,
            dateStrs: normalizedDateStrs,
          )
        : null;

    final toc = <StatisticsDeepTocItem>[
      const StatisticsDeepTocItem(id: 'cover', title: '표지', level: 0),
      const StatisticsDeepTocItem(id: 'summary', title: '요약', level: 0),
      if (sectorEnabled)
        const StatisticsDeepTocItem(
          id: 'sector',
          title: '방문 구역 분석',
          level: 0,
        ),
      StatisticsDeepTocItem(
        id: overall.id,
        title: overall.title,
        level: 0,
      ),
      const StatisticsDeepTocItem(
        id: 'daily_group',
        title: '날짜별 심화 통계',
        level: 0,
        isGroup: true,
      ),
      for (final section in daily)
        StatisticsDeepTocItem(
          id: section.id,
          title: section.title,
          level: 1,
        ),
      if (weekdaySections.isNotEmpty)
        const StatisticsDeepTocItem(
          id: 'weekday_group',
          title: '요일별 심화 통계',
          level: 0,
          isGroup: true,
        ),
      for (final section in weekdaySections)
        StatisticsDeepTocItem(
          id: section.id,
          title: section.title,
          level: 1,
        ),
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
      sectorEnabled: sectorEnabled,
      sectorReport: sector,
      diagnostics: effectiveDiagnostics,
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

  Map<String, int> get feeByPaymentMethod =>
      _feeByPaymentMethodFromRows(rows);
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
    final normalizedRows = <StatisticsDeepVehicleRow>[
      for (int i = 0; i < rows.length; i++) rows[i].copyWith(no: i + 1),
    ];

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

  Map<String, int> get feeByPaymentMethod =>
      _feeByPaymentMethodFromRows(rows);
}

enum StatisticsDeepSectionType {
  overall,
  date,
  weekday,
}

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

  double get inputAverageSum =>
      inputAverageCounts.fold<double>(0, (p, e) => p + e);

  double get outputAverageSum =>
      outputAverageCounts.fold<double>(0, (p, e) => p + e);
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
  final StatisticsDepartureTimeSource departureTimeSource;
  final int? fee;
  final String paymentMethod;
  final String docId;
  final String? sectorId;
  final String? sectorName;
  final bool sectorConflict;
  final bool sectorIdentityConflict;
  final bool sectorFieldsPresent;

  const StatisticsDeepVehicleRow({
    required this.no,
    required this.dateStr,
    required this.plateNumber,
    required this.createdAt,
    required this.departureAt,
    required this.departureTimeSource,
    required this.fee,
    required this.paymentMethod,
    required this.docId,
    required this.sectorId,
    required this.sectorName,
    required this.sectorConflict,
    required this.sectorIdentityConflict,
    required this.sectorFieldsPresent,
  });

  StatisticsDeepVehicleRow copyWith({
    int? no,
    String? dateStr,
    String? plateNumber,
    DateTime? createdAt,
    DateTime? departureAt,
    StatisticsDepartureTimeSource? departureTimeSource,
    int? fee,
    String? paymentMethod,
    String? docId,
    String? sectorId,
    String? sectorName,
    bool? sectorConflict,
    bool? sectorIdentityConflict,
    bool? sectorFieldsPresent,
  }) {
    return StatisticsDeepVehicleRow(
      no: no ?? this.no,
      dateStr: dateStr ?? this.dateStr,
      plateNumber: plateNumber ?? this.plateNumber,
      createdAt: createdAt ?? this.createdAt,
      departureAt: departureAt ?? this.departureAt,
      departureTimeSource: departureTimeSource ?? this.departureTimeSource,
      fee: fee ?? this.fee,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      docId: docId ?? this.docId,
      sectorId: sectorId ?? this.sectorId,
      sectorName: sectorName ?? this.sectorName,
      sectorConflict: sectorConflict ?? this.sectorConflict,
      sectorIdentityConflict:
          sectorIdentityConflict ?? this.sectorIdentityConflict,
      sectorFieldsPresent: sectorFieldsPresent ?? this.sectorFieldsPresent,
    );
  }

  String get paymentMethodLabel {
    final value = paymentMethod.trim();
    return value.isEmpty ? '미분류' : value;
  }

  String get normalizedSectorId => (sectorId ?? '').trim();

  String get normalizedSectorName => (sectorName ?? '').trim();

  StatisticsSectorState get sectorState {
    if (!sectorFieldsPresent) {
      return StatisticsSectorState.unavailable;
    }
    final hasId = normalizedSectorId.isNotEmpty;
    final hasName = normalizedSectorName.isNotEmpty;
    if (hasId && hasName && !sectorConflict && !sectorIdentityConflict) {
      return StatisticsSectorState.assigned;
    }
    if (!hasId && !hasName && !sectorConflict && !sectorIdentityConflict) {
      return StatisticsSectorState.unassigned;
    }
    return StatisticsSectorState.invalid;
  }

  String get sectorKey {
    switch (sectorState) {
      case StatisticsSectorState.assigned:
        return 'assigned:$normalizedSectorId';
      case StatisticsSectorState.unassigned:
        return 'unassigned';
      case StatisticsSectorState.invalid:
        return 'invalid';
      case StatisticsSectorState.unavailable:
        return 'unavailable';
    }
  }

  String get sectorLabel {
    switch (sectorState) {
      case StatisticsSectorState.assigned:
        return normalizedSectorName;
      case StatisticsSectorState.unassigned:
        return '미지정';
      case StatisticsSectorState.invalid:
        return '데이터 확인 필요';
      case StatisticsSectorState.unavailable:
        return '원천 데이터 없음';
    }
  }

  bool get departureTimeEstimated =>
      departureTimeSource == StatisticsDepartureTimeSource.lastLogFallback;
}

class StatisticsSectorReport {
  final List<StatisticsSectorGroup> groups;
  final StatisticsSectorIntegrity integrity;
  final List<String> dateStrs;
  final List<String> selectableSectorKeys;
  final List<String> defaultSelectedSectorKeys;
  final bool sourceFieldAvailable;
  final bool sourceFieldComplete;

  const StatisticsSectorReport({
    required this.groups,
    required this.integrity,
    required this.dateStrs,
    required this.selectableSectorKeys,
    required this.defaultSelectedSectorKeys,
    required this.sourceFieldAvailable,
    required this.sourceFieldComplete,
  });

  factory StatisticsSectorReport.fromRows({
    required List<StatisticsDeepVehicleRow> rows,
    required List<String> dateStrs,
  }) {
    final analyzableRows = rows
        .where((row) => row.sectorState != StatisticsSectorState.unavailable)
        .toList(growable: false);
    final builders = <String, _MutableStatisticsSectorGroup>{};
    for (final row in analyzableRows) {
      final key = row.sectorKey;
      final builder = builders.putIfAbsent(
        key,
        () => _MutableStatisticsSectorGroup(
          key: key,
          sectorId: row.sectorState == StatisticsSectorState.assigned
              ? row.normalizedSectorId
              : null,
          sectorLabel: row.sectorLabel,
          state: row.sectorState,
          dateStrs: dateStrs,
        ),
      );
      builder.add(row);
    }

    final groups = builders.values.map((e) => e.build()).toList()
      ..sort((a, b) {
        final stateCmp = _sectorStateRank(a.state)
            .compareTo(_sectorStateRank(b.state));
        if (stateCmp != 0) return stateCmp;
        final countCmp = b.vehicleCount.compareTo(a.vehicleCount);
        if (countCmp != 0) return countCmp;
        return a.sectorLabel.compareTo(b.sectorLabel);
      });

    final integrity = StatisticsSectorIntegrity.fromRowsAndGroups(
      rows: rows,
      groups: groups,
    );
    final selectable = groups.map((e) => e.key).toList();
    final normalKeys = groups
        .where((e) => e.state == StatisticsSectorState.assigned)
        .map((e) => e.key)
        .take(3)
        .toList();
    final defaults = normalKeys.isNotEmpty
        ? normalKeys
        : selectable.take(3).toList();

    return StatisticsSectorReport(
      groups: groups,
      integrity: integrity,
      dateStrs: List<String>.unmodifiable(dateStrs),
      selectableSectorKeys: List<String>.unmodifiable(selectable),
      defaultSelectedSectorKeys: List<String>.unmodifiable(defaults),
      sourceFieldAvailable: integrity.analyzableVehicleCount > 0,
      sourceFieldComplete: integrity.unavailableVehicleCount == 0,
    );
  }

  int get sectorCount => groups
      .where((e) => e.state == StatisticsSectorState.assigned)
      .length;

  int get totalVehicleCount => integrity.totalVehicleCount;

  int get analyzableVehicleCount => integrity.analyzableVehicleCount;

  int get unavailableVehicleCount => integrity.unavailableVehicleCount;

  double get analyzableRatio => totalVehicleCount == 0
      ? 0
      : analyzableVehicleCount / totalVehicleCount;

  bool get hasAnalyzableData => analyzableVehicleCount > 0;

  bool get hasUnavailableData => unavailableVehicleCount > 0;

  int get assignedVehicleCount => integrity.assignedVehicleCount;

  int get unassignedVehicleCount => integrity.unassignedVehicleCount;

  int get invalidVehicleCount => integrity.invalidVehicleCount;

  int get totalInputCount => groups.fold<int>(0, (p, e) => p + e.inputCount);

  int get totalOutputCount =>
      groups.fold<int>(0, (p, e) => p + e.outputCount);

  int get totalLockedFee =>
      groups.fold<int>(0, (p, e) => p + e.totalLockedFee);

  List<StatisticsSectorGroup> groupsForKeys(Set<String> keys) {
    if (keys.isEmpty) return groups;
    return groups.where((e) => keys.contains(e.key)).toList();
  }

  StatisticsSectorGroup combinedGroup({
    Set<String>? keys,
    String label = '전체',
  }) {
    final selected = keys == null || keys.isEmpty
        ? groups
        : groups.where((group) => keys.contains(group.key)).toList();
    final builder = _MutableStatisticsSectorGroup(
      key: 'combined:${selected.map((group) => group.key).join('|')}',
      sectorId: null,
      sectorLabel: label,
      state: StatisticsSectorState.assigned,
      dateStrs: dateStrs,
    );
    for (final group in selected) {
      for (final row in group.rows) {
        builder.add(row);
      }
    }
    return builder.build();
  }

  List<StatisticsDeepVehicleRow> rowsForKeys(Set<String> keys) {
    final selected = groupsForKeys(keys);
    final rows = selected.expand((e) => e.rows).toList()
      ..sort((a, b) {
        final dateCmp = a.dateStr.compareTo(b.dateStr);
        if (dateCmp != 0) return dateCmp;
        final timeA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final timeB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final timeCmp = timeA.compareTo(timeB);
        if (timeCmp != 0) return timeCmp;
        return a.plateNumber.compareTo(b.plateNumber);
      });
    return <StatisticsDeepVehicleRow>[
      for (int i = 0; i < rows.length; i++) rows[i].copyWith(no: i + 1),
    ];
  }
}

class StatisticsSectorGroup {
  final String key;
  final String? sectorId;
  final String sectorLabel;
  final StatisticsSectorState state;
  final List<StatisticsDeepVehicleRow> rows;
  final int vehicleCount;
  final int inputCount;
  final int outputCount;
  final int totalLockedFee;
  final int feeVehicleCount;
  final int missingFeeVehicleCount;
  final List<int> hourlyInputCounts;
  final List<int> hourlyOutputCounts;
  final Map<String, int> dailyInputCounts;
  final Map<String, int> dailyOutputCounts;
  final Map<int, int> weekdayInputCounts;
  final Map<int, int> weekdayDateCounts;
  final Map<String, int> feeByPaymentMethod;
  final Map<String, int> vehicleCountByPaymentMethod;
  final int confirmedDepartureCount;
  final int estimatedDepartureCount;
  final double? averageLockedFee;
  final double? medianLockedFee;
  final int? minLockedFee;
  final int? maxLockedFee;
  final double? lowerQuartileLockedFee;
  final double? upperQuartileLockedFee;

  const StatisticsSectorGroup({
    required this.key,
    required this.sectorId,
    required this.sectorLabel,
    required this.state,
    required this.rows,
    required this.vehicleCount,
    required this.inputCount,
    required this.outputCount,
    required this.totalLockedFee,
    required this.feeVehicleCount,
    required this.missingFeeVehicleCount,
    required this.hourlyInputCounts,
    required this.hourlyOutputCounts,
    required this.dailyInputCounts,
    required this.dailyOutputCounts,
    required this.weekdayInputCounts,
    required this.weekdayDateCounts,
    required this.feeByPaymentMethod,
    required this.vehicleCountByPaymentMethod,
    required this.confirmedDepartureCount,
    required this.estimatedDepartureCount,
    required this.averageLockedFee,
    required this.medianLockedFee,
    required this.minLockedFee,
    required this.maxLockedFee,
    required this.lowerQuartileLockedFee,
    required this.upperQuartileLockedFee,
  });

  int? get peakInputHour => _peakHour(hourlyInputCounts);

  int? get peakOutputHour => _peakHour(hourlyOutputCounts);

  double inputAverageForWeekday(int weekday) {
    final count = weekdayInputCounts[weekday] ?? 0;
    final days = weekdayDateCounts[weekday] ?? 0;
    if (days <= 0) return 0;
    return count / days;
  }
}

class StatisticsSectorIntegrity {
  final int totalVehicleCount;
  final int analyzableVehicleCount;
  final int unavailableVehicleCount;
  final int assignedVehicleCount;
  final int unassignedVehicleCount;
  final int invalidVehicleCount;
  final int groupedVehicleCount;
  final int inputTimestampVehicleCount;
  final int groupedInputCount;
  final int totalLockedFee;
  final int groupedLockedFee;
  final int unavailableInputTimestampCount;
  final int unavailableLockedFee;
  final int missingInputTimeCount;
  final int missingOutputTimeCount;
  final int estimatedOutputTimeCount;
  final int sectorConflictCount;
  final int sectorIdentityConflictCount;
  final bool vehicleCountMatched;
  final bool inputCountMatched;
  final bool lockedFeeMatched;

  const StatisticsSectorIntegrity({
    required this.totalVehicleCount,
    required this.analyzableVehicleCount,
    required this.unavailableVehicleCount,
    required this.assignedVehicleCount,
    required this.unassignedVehicleCount,
    required this.invalidVehicleCount,
    required this.groupedVehicleCount,
    required this.inputTimestampVehicleCount,
    required this.groupedInputCount,
    required this.totalLockedFee,
    required this.groupedLockedFee,
    required this.unavailableInputTimestampCount,
    required this.unavailableLockedFee,
    required this.missingInputTimeCount,
    required this.missingOutputTimeCount,
    required this.estimatedOutputTimeCount,
    required this.sectorConflictCount,
    required this.sectorIdentityConflictCount,
    required this.vehicleCountMatched,
    required this.inputCountMatched,
    required this.lockedFeeMatched,
  });

  factory StatisticsSectorIntegrity.fromRowsAndGroups({
    required List<StatisticsDeepVehicleRow> rows,
    required List<StatisticsSectorGroup> groups,
  }) {
    final analyzableRows = rows
        .where((e) => e.sectorState != StatisticsSectorState.unavailable)
        .toList(growable: false);
    final unavailableRows = rows
        .where((e) => e.sectorState == StatisticsSectorState.unavailable)
        .toList(growable: false);
    final assigned = analyzableRows
        .where((e) => e.sectorState == StatisticsSectorState.assigned)
        .length;
    final unassigned = analyzableRows
        .where((e) => e.sectorState == StatisticsSectorState.unassigned)
        .length;
    final invalid = analyzableRows
        .where((e) => e.sectorState == StatisticsSectorState.invalid)
        .length;
    final groupedVehicleCount =
        groups.fold<int>(0, (sum, group) => sum + group.vehicleCount);
    final inputCount = analyzableRows.where((e) => e.createdAt != null).length;
    final groupedInputCount =
        groups.fold<int>(0, (sum, group) => sum + group.inputCount);
    final totalFee =
        analyzableRows.fold<int>(0, (sum, row) => sum + (row.fee ?? 0));
    final groupedFee =
        groups.fold<int>(0, (sum, group) => sum + group.totalLockedFee);
    final classifiedVehicleCount =
        assigned + unassigned + invalid + unavailableRows.length;

    return StatisticsSectorIntegrity(
      totalVehicleCount: rows.length,
      analyzableVehicleCount: analyzableRows.length,
      unavailableVehicleCount: unavailableRows.length,
      assignedVehicleCount: assigned,
      unassignedVehicleCount: unassigned,
      invalidVehicleCount: invalid,
      groupedVehicleCount: groupedVehicleCount,
      inputTimestampVehicleCount: inputCount,
      groupedInputCount: groupedInputCount,
      totalLockedFee: totalFee,
      groupedLockedFee: groupedFee,
      unavailableInputTimestampCount:
          unavailableRows.where((e) => e.createdAt != null).length,
      unavailableLockedFee:
          unavailableRows.fold<int>(0, (sum, row) => sum + (row.fee ?? 0)),
      missingInputTimeCount:
          analyzableRows.where((e) => e.createdAt == null).length,
      missingOutputTimeCount:
          analyzableRows.where((e) => e.departureAt == null).length,
      estimatedOutputTimeCount:
          analyzableRows.where((e) => e.departureTimeEstimated).length,
      sectorConflictCount:
          analyzableRows.where((e) => e.sectorConflict).length,
      sectorIdentityConflictCount:
          analyzableRows.where((e) => e.sectorIdentityConflict).length,
      vehicleCountMatched: groupedVehicleCount == analyzableRows.length &&
          classifiedVehicleCount == rows.length,
      inputCountMatched: groupedInputCount == inputCount,
      lockedFeeMatched: groupedFee == totalFee,
    );
  }

  bool get isValid =>
      vehicleCountMatched && inputCountMatched && lockedFeeMatched;

  List<String> get debugLines => <String>[
        'integrity vehicles=$groupedVehicleCount/$analyzableVehicleCount analyzable matched=$vehicleCountMatched total=$totalVehicleCount unavailable=$unavailableVehicleCount',
        'integrity input=$groupedInputCount/$inputTimestampVehicleCount matched=$inputCountMatched unavailableInput=$unavailableInputTimestampCount',
        'integrity fee=$groupedLockedFee/$totalLockedFee matched=$lockedFeeMatched unavailableFee=$unavailableLockedFee',
        'sector assigned=$assignedVehicleCount unassigned=$unassignedVehicleCount invalid=$invalidVehicleCount unavailable=$unavailableVehicleCount conflicts=$sectorConflictCount identityConflicts=$sectorIdentityConflictCount',
        'time missingInput=$missingInputTimeCount missingOutput=$missingOutputTimeCount estimatedOutput=$estimatedOutputTimeCount',
      ];
}

class _MutableStatisticsSectorGroup {
  final String key;
  final String? sectorId;
  final String sectorLabel;
  final StatisticsSectorState state;
  final List<String> dateStrs;
  final List<StatisticsDeepVehicleRow> rows = <StatisticsDeepVehicleRow>[];
  final List<int> hourlyInputCounts = List<int>.filled(24, 0);
  final List<int> hourlyOutputCounts = List<int>.filled(24, 0);
  final Map<String, int> dailyInputCounts = <String, int>{};
  final Map<String, int> dailyOutputCounts = <String, int>{};
  final Map<int, int> weekdayInputCounts = <int, int>{};
  final Map<int, Set<String>> weekdayDates = <int, Set<String>>{};
  final Map<String, int> feeByPaymentMethod = <String, int>{};
  final Map<String, int> vehicleCountByPaymentMethod = <String, int>{};
  final List<int> fees = <int>[];
  int inputCount = 0;
  int outputCount = 0;
  int totalLockedFee = 0;
  int confirmedDepartureCount = 0;
  int estimatedDepartureCount = 0;

  _MutableStatisticsSectorGroup({
    required this.key,
    required this.sectorId,
    required this.sectorLabel,
    required this.state,
    required this.dateStrs,
  }) {
    for (final dateStr in dateStrs) {
      dailyInputCounts[dateStr] = 0;
      dailyOutputCounts[dateStr] = 0;
      final date = DateTime.tryParse(dateStr);
      if (date != null) {
        weekdayDates
            .putIfAbsent(date.weekday, () => <String>{})
            .add(_dateOnly(date));
      }
    }
  }

  void add(StatisticsDeepVehicleRow row) {
    rows.add(row);
    final createdAt = row.createdAt;
    if (createdAt != null) {
      inputCount++;
      hourlyInputCounts[createdAt.hour]++;
      final inputDate = _dateOnly(createdAt);
      dailyInputCounts[inputDate] = (dailyInputCounts[inputDate] ?? 0) + 1;
      weekdayInputCounts[createdAt.weekday] =
          (weekdayInputCounts[createdAt.weekday] ?? 0) + 1;
      weekdayDates
          .putIfAbsent(createdAt.weekday, () => <String>{})
          .add(inputDate);
    }

    final departureAt = row.departureAt;
    if (departureAt != null) {
      outputCount++;
      hourlyOutputCounts[departureAt.hour]++;
      final outputDate = _dateOnly(departureAt);
      dailyOutputCounts[outputDate] =
          (dailyOutputCounts[outputDate] ?? 0) + 1;
      if (row.departureTimeEstimated) {
        estimatedDepartureCount++;
      } else {
        confirmedDepartureCount++;
      }
    }

    final fee = row.fee;
    if (fee != null) {
      totalLockedFee += fee;
      fees.add(fee);
      final method = row.paymentMethodLabel;
      feeByPaymentMethod[method] = (feeByPaymentMethod[method] ?? 0) + fee;
      vehicleCountByPaymentMethod[method] =
          (vehicleCountByPaymentMethod[method] ?? 0) + 1;
    }
  }

  StatisticsSectorGroup build() {
    fees.sort();
    final normalizedRows = <StatisticsDeepVehicleRow>[
      for (int i = 0; i < rows.length; i++) rows[i].copyWith(no: i + 1),
    ];
    final weekdayDateCounts = <int, int>{
      for (final entry in weekdayDates.entries) entry.key: entry.value.length,
    };

    return StatisticsSectorGroup(
      key: key,
      sectorId: sectorId,
      sectorLabel: sectorLabel,
      state: state,
      rows: List<StatisticsDeepVehicleRow>.unmodifiable(normalizedRows),
      vehicleCount: rows.length,
      inputCount: inputCount,
      outputCount: outputCount,
      totalLockedFee: totalLockedFee,
      feeVehicleCount: fees.length,
      missingFeeVehicleCount: rows.length - fees.length,
      hourlyInputCounts: List<int>.unmodifiable(hourlyInputCounts),
      hourlyOutputCounts: List<int>.unmodifiable(hourlyOutputCounts),
      dailyInputCounts: Map<String, int>.unmodifiable(
        _sortedDateMap(dailyInputCounts),
      ),
      dailyOutputCounts: Map<String, int>.unmodifiable(
        _sortedDateMap(dailyOutputCounts),
      ),
      weekdayInputCounts: Map<int, int>.unmodifiable(weekdayInputCounts),
      weekdayDateCounts: Map<int, int>.unmodifiable(weekdayDateCounts),
      feeByPaymentMethod: Map<String, int>.unmodifiable(
        _sortedAmountMap(feeByPaymentMethod),
      ),
      vehicleCountByPaymentMethod: Map<String, int>.unmodifiable(
        _sortedAmountMap(vehicleCountByPaymentMethod),
      ),
      confirmedDepartureCount: confirmedDepartureCount,
      estimatedDepartureCount: estimatedDepartureCount,
      averageLockedFee: fees.isEmpty
          ? null
          : fees.fold<int>(0, (p, e) => p + e) / fees.length,
      medianLockedFee: _percentile(fees, 0.5),
      minLockedFee: fees.isEmpty ? null : fees.first,
      maxLockedFee: fees.isEmpty ? null : fees.last,
      lowerQuartileLockedFee: _percentile(fees, 0.25),
      upperQuartileLockedFee: _percentile(fees, 0.75),
    );
  }
}

Set<String> _sectorIdsWithNameConflicts(
  List<StatisticsDeepVehicleRow> rows,
) {
  final namesById = <String, Set<String>>{};
  for (final row in rows) {
    final id = row.normalizedSectorId;
    final name = row.normalizedSectorName;
    if (id.isEmpty || name.isEmpty) continue;
    namesById.putIfAbsent(id, () => <String>{}).add(name);
  }
  return namesById.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toSet();
}

Map<String, int> _feeByPaymentMethodFromRows(
  List<StatisticsDeepVehicleRow> rows,
) {
  final result = <String, int>{};
  for (final row in rows) {
    final fee = row.fee;
    if (fee == null) continue;
    final key = row.paymentMethodLabel;
    result[key] = (result[key] ?? 0) + fee;
  }
  return _sortedAmountMap(result);
}

Map<String, int> _sortedAmountMap(Map<String, int> input) {
  final entries = input.entries.toList()
    ..sort((a, b) {
      if (a.key == '미분류') return 1;
      if (b.key == '미분류') return -1;
      final valueCmp = b.value.compareTo(a.value);
      if (valueCmp != 0) return valueCmp;
      return a.key.compareTo(b.key);
    });
  return Map<String, int>.fromEntries(entries);
}

Map<String, int> _sortedDateMap(Map<String, int> input) {
  final keys = input.keys.toList()..sort();
  return <String, int>{for (final key in keys) key: input[key] ?? 0};
}

double? _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return null;
  if (values.length == 1) return values.first.toDouble();
  final position = (values.length - 1) * percentile;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return values[lower].toDouble();
  final weight = position - lower;
  return values[lower] * (1 - weight) + values[upper] * weight;
}

int? _peakHour(List<int> values) {
  if (values.isEmpty) return null;
  var peakIndex = 0;
  var peakValue = 0;
  for (int i = 0; i < values.length; i++) {
    if (values[i] > peakValue) {
      peakValue = values[i];
      peakIndex = i;
    }
  }
  return peakValue == 0 ? null : peakIndex;
}

int _sectorStateRank(StatisticsSectorState state) {
  switch (state) {
    case StatisticsSectorState.assigned:
      return 0;
    case StatisticsSectorState.unassigned:
      return 1;
    case StatisticsSectorState.invalid:
      return 2;
    case StatisticsSectorState.unavailable:
      return 3;
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

String _dateOnly(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
