class EndWorkSectorMetricItem {
  final String sectorId;
  final String sectorName;
  final int vehicleCount;
  final num totalLockedFee;

  const EndWorkSectorMetricItem({
    required this.sectorId,
    required this.sectorName,
    required this.vehicleCount,
    required this.totalLockedFee,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sectorId': sectorId,
      'sectorName': sectorName,
      'vehicleCount': vehicleCount,
      'totalLockedFee': totalLockedFee,
    };
  }

  factory EndWorkSectorMetricItem.fromMap(Map<String, dynamic> map) {
    return EndWorkSectorMetricItem(
      sectorId: _text(map['sectorId']),
      sectorName: _text(map['sectorName']),
      vehicleCount: _integer(map['vehicleCount']),
      totalLockedFee: _number(map['totalLockedFee']),
    );
  }
}

class EndWorkSectorMetrics {
  final bool enabled;
  final int sectorCount;
  final int assignedVehicleCount;
  final num assignedLockedFee;
  final int unassignedVehicleCount;
  final num unassignedLockedFee;
  final int invalidSectorVehicleCount;
  final num invalidSectorLockedFee;
  final bool legacyFeeClassification;
  final List<EndWorkSectorMetricItem> items;

  const EndWorkSectorMetrics({
    required this.enabled,
    required this.sectorCount,
    required this.assignedVehicleCount,
    required this.assignedLockedFee,
    required this.unassignedVehicleCount,
    required this.unassignedLockedFee,
    required this.invalidSectorVehicleCount,
    required this.invalidSectorLockedFee,
    required this.items,
    this.legacyFeeClassification = false,
  });

  int get totalVehicleCount =>
      assignedVehicleCount +
      unassignedVehicleCount +
      invalidSectorVehicleCount;

  num get totalLockedFee =>
      assignedLockedFee + unassignedLockedFee + invalidSectorLockedFee;

  bool get hasAssignedData => assignedVehicleCount > 0 || items.isNotEmpty;

  bool get isInternallyConsistent {
    final itemVehicleCount =
        items.fold<int>(0, (sum, item) => sum + item.vehicleCount);
    final itemLockedFee =
        items.fold<num>(0, (sum, item) => sum + item.totalLockedFee);
    return itemVehicleCount == assignedVehicleCount &&
        itemLockedFee == assignedLockedFee;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'sectorCount': sectorCount,
      'assignedVehicleCount': assignedVehicleCount,
      'assignedLockedFee': assignedLockedFee,
      'unassignedVehicleCount': unassignedVehicleCount,
      'unassignedLockedFee': unassignedLockedFee,
      'invalidSectorVehicleCount': invalidSectorVehicleCount,
      'invalidSectorLockedFee': invalidSectorLockedFee,
      'legacyFeeClassification': legacyFeeClassification,
      'items': items.map((item) => item.toMap()).toList(growable: false),
    };
  }

  factory EndWorkSectorMetrics.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    final items = <EndWorkSectorMetricItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map<String, dynamic>) {
          items.add(EndWorkSectorMetricItem.fromMap(raw));
        } else if (raw is Map) {
          items.add(
            EndWorkSectorMetricItem.fromMap(
              raw.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }
    items.sort((a, b) {
      final byName = a.sectorName.compareTo(b.sectorName);
      if (byName != 0) return byName;
      return a.sectorId.compareTo(b.sectorId);
    });
    final invalidCount = _integer(map['invalidSectorVehicleCount']);
    final hasSeparatedInvalidFee = map.containsKey('invalidSectorLockedFee');
    final invalidFee = hasSeparatedInvalidFee
        ? _number(map['invalidSectorLockedFee'])
        : 0;
    var unassignedCount = _integer(map['unassignedVehicleCount']);
    var unassignedFee = _number(map['unassignedLockedFee']);
    if (!map.containsKey('invalidSectorLockedFee') && invalidCount > 0) {
      unassignedCount = (unassignedCount - invalidCount).clamp(0, 1 << 30).toInt();
    }
    return EndWorkSectorMetrics(
      enabled: map['enabled'] == true,
      sectorCount: _integer(map['sectorCount']),
      assignedVehicleCount: _integer(map['assignedVehicleCount']),
      assignedLockedFee: _number(map['assignedLockedFee']),
      unassignedVehicleCount: unassignedCount,
      unassignedLockedFee: unassignedFee,
      invalidSectorVehicleCount: invalidCount,
      invalidSectorLockedFee: invalidFee,
      legacyFeeClassification:
          map['legacyFeeClassification'] == true ||
              (!hasSeparatedInvalidFee && invalidCount > 0),
      items: List<EndWorkSectorMetricItem>.unmodifiable(items),
    );
  }

  static EndWorkSectorMetrics? fromDynamic(Object? value) {
    if (value is Map<String, dynamic>) {
      return EndWorkSectorMetrics.fromMap(value);
    }
    if (value is Map) {
      return EndWorkSectorMetrics.fromMap(
        value.map((key, item) => MapEntry(key.toString(), item)),
      );
    }
    return null;
  }

  static EndWorkSectorMetrics merge(
    Iterable<EndWorkSectorMetrics> metrics,
  ) {
    final grouped = <String, _MutableSectorMetric>{};
    var assignedVehicleCount = 0;
    num assignedLockedFee = 0;
    var unassignedVehicleCount = 0;
    num unassignedLockedFee = 0;
    var invalidSectorVehicleCount = 0;
    num invalidSectorLockedFee = 0;
    var enabled = false;
    var legacyFeeClassification = false;

    for (final metric in metrics) {
      if (!metric.enabled) continue;
      enabled = true;
      legacyFeeClassification =
          legacyFeeClassification || metric.legacyFeeClassification;
      assignedVehicleCount += metric.assignedVehicleCount;
      assignedLockedFee += metric.assignedLockedFee;
      unassignedVehicleCount += metric.unassignedVehicleCount;
      unassignedLockedFee += metric.unassignedLockedFee;
      invalidSectorVehicleCount += metric.invalidSectorVehicleCount;
      invalidSectorLockedFee += metric.invalidSectorLockedFee;
      for (final item in metric.items) {
        final key = '${item.sectorId}\u0000${item.sectorName}';
        final target = grouped.putIfAbsent(
          key,
          () => _MutableSectorMetric(
            sectorId: item.sectorId,
            sectorName: item.sectorName,
          ),
        );
        target.vehicleCount += item.vehicleCount;
        target.totalLockedFee += item.totalLockedFee;
      }
    }

    final items = grouped.values
        .map(
          (item) => EndWorkSectorMetricItem(
            sectorId: item.sectorId,
            sectorName: item.sectorName,
            vehicleCount: item.vehicleCount,
            totalLockedFee: item.totalLockedFee,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byCount = b.vehicleCount.compareTo(a.vehicleCount);
        if (byCount != 0) return byCount;
        final byName = a.sectorName.compareTo(b.sectorName);
        if (byName != 0) return byName;
        return a.sectorId.compareTo(b.sectorId);
      });

    return EndWorkSectorMetrics(
      enabled: enabled,
      sectorCount: items.length,
      assignedVehicleCount: assignedVehicleCount,
      assignedLockedFee: assignedLockedFee,
      unassignedVehicleCount: unassignedVehicleCount,
      unassignedLockedFee: unassignedLockedFee,
      invalidSectorVehicleCount: invalidSectorVehicleCount,
      invalidSectorLockedFee: invalidSectorLockedFee,
      legacyFeeClassification: legacyFeeClassification,
      items: List<EndWorkSectorMetricItem>.unmodifiable(items),
    );
  }
}

class _MutableSectorMetric {
  final String sectorId;
  final String sectorName;
  int vehicleCount = 0;
  num totalLockedFee = 0;

  _MutableSectorMetric({
    required this.sectorId,
    required this.sectorName,
  });
}

String _text(Object? value) {
  return value?.toString().trim() ?? '';
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
}

num _number(Object? value) {
  if (value is num) return value;
  if (value is String) {
    return num.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
}
