import 'dart:collection';
import 'dart:math' as math;

import 'firebase_activity_billing_config.dart';
import 'firebase_activity_write_scope.dart';

enum FirestoreReadStrategy { pointRead, collectionScan, indexedQuery, unknown }

class FirebaseCostEntry {
  const FirebaseCostEntry({
    required this.kind,
    required this.units,
    required this.won,
    required this.bytes,
    required this.fields,
    required this.uncertain,
    this.possibleExtraUnits = 0,
    this.possibleExtraWon = 0,
    this.reason = '',
  });

  final String kind;
  final int units;
  final double won;
  final int bytes;
  final int fields;
  final bool uncertain;
  final int possibleExtraUnits;
  final double possibleExtraWon;
  final String reason;
}

class FirebaseCostSummary {
  const FirebaseCostSummary({
    required this.label,
    required this.units,
    required this.won,
  });

  final String label;
  final int units;
  final double won;
}

class FirebaseActivityCostEstimator {
  final Map<String, int> _units = <String, int>{};
  final Map<String, double> _won = <String, double>{};
  final Queue<FirebaseCostEntry> _recent = Queue<FirebaseCostEntry>();
  double _totalWon = 0;
  double _possibleExtraWon = 0;
  int _possibleExtraUnits = 0;
  int _totalUnits = 0;
  int _uncertainOperations = 0;
  int _knownBytes = 0;
  int _knownFields = 0;
  int _unknownRemoved = 0;
  int _reconnectCandidates = 0;
  int _metadataOnlyEvents = 0;

  double get totalWon => _totalWon;
  double get possibleExtraWon => _possibleExtraWon;
  int get possibleExtraUnits => _possibleExtraUnits;
  int get totalUnits => _totalUnits;
  int get uncertainOperations => _uncertainOperations;
  int get knownBytes => _knownBytes;
  int get knownFields => _knownFields;
  int get unknownRemoved => _unknownRemoved;
  int get reconnectCandidates => _reconnectCandidates;
  int get metadataOnlyEvents => _metadataOnlyEvents;
  List<FirebaseCostEntry> get recent => List<FirebaseCostEntry>.unmodifiable(_recent);

  List<FirebaseCostSummary> get summaries {
    const labels = <String>['read', 'snapshot', 'set', 'create', 'update',
      'delete', 'write', 'batchWrite', 'batchDelete', 'transactionRead',
      'transactionWrite', 'transactionDelete'];
    return List<FirebaseCostSummary>.unmodifiable(labels.map((kind) =>
        FirebaseCostSummary(label: kind, units: _units[kind] ?? 0,
          won: _won[kind] ?? 0)));
  }

  static String formatWon(double won) {
    if (won == 0) return '₩0';
    if (won.abs() < 1) return '₩${won.toStringAsFixed(5)}';
    if (won.abs() < 100) return '₩${won.toStringAsFixed(3)}';
    return '₩${won.toStringAsFixed(2)}';
  }

  static bool get enterprise =>
      FirebaseActivityBillingConfig.edition == FirebaseBillingEdition.enterprise;

  int _readUnits(int docs, int bytes, {
    bool emptyMinimum = true,
    FirestoreReadStrategy strategy = FirestoreReadStrategy.unknown,
    int pointReadUnits = 0,
    int indexBytes = 0,
  }) {
    if (!enterprise) return math.max(emptyMinimum ? 1 : 0, docs);
    if (docs <= 0 && !emptyMinimum) return 0;
    switch (strategy) {
      case FirestoreReadStrategy.pointRead:
        return math.max(emptyMinimum ? 1 : 0,
            pointReadUnits > 0 ? pointReadUnits : math.max(1, (bytes / 4096).ceil()));
      case FirestoreReadStrategy.collectionScan:
        return math.max(emptyMinimum ? 1 : 0, (bytes / 4096).ceil());
      case FirestoreReadStrategy.indexedQuery:
        final docUnits = pointReadUnits > 0 ? pointReadUnits :
            math.max(docs, (bytes / 4096).ceil());
        final indexUnits = math.max(1, (indexBytes / 4096).ceil());
        return docUnits + indexUnits;
      case FirestoreReadStrategy.unknown:
        return math.max(emptyMinimum ? 1 : 0,
            pointReadUnits > 0 ? pointReadUnits : math.max(1, (bytes / 4096).ceil()));
    }
  }

  int _writeUnits(int count, int bytes, List<FirestoreWriteMetric>? metrics) {
    if (count <= 0) return 0;
    if (!enterprise) return count;
    if (metrics != null && metrics.isNotEmpty) {
      return metrics.fold<int>(
        0,
        (sum, metric) {
          final units = (metric.bytes + 1023) ~/ 1024;
          return sum + (units < 1 ? 1 : units) + metric.indexWriteUnits;
        },
      );
    }
    return math.max(count, (bytes / 1024).ceil());
  }

  double _price(String kind, int units, {bool initialSnapshot = false}) {
    final rateKrw = FirebaseActivityBillingConfig.krwPerUsd;
    if (!enterprise) {
      final rate = kind == 'delete' || kind == 'batchDelete' ||
              kind == 'transactionDelete'
          ? FirebaseActivityBillingConfig.standardDeleteUsdPer100k
          : kind == 'read' || kind == 'snapshot' || kind == 'transactionRead'
              ? FirebaseActivityBillingConfig.standardReadUsdPer100k
              : FirebaseActivityBillingConfig.standardWriteUsdPer100k;
      return units * rate / 100000 * rateKrw;
    }
    final rate = kind == 'snapshot' && !initialSnapshot
        ? FirebaseActivityBillingConfig.enterpriseRealtimeUsdPerMillion
        : kind == 'read' || kind == 'transactionRead' ||
            (kind == 'snapshot' && initialSnapshot)
            ? FirebaseActivityBillingConfig.enterpriseReadUsdPerMillion
            : FirebaseActivityBillingConfig.enterpriseWriteUsdPerMillion;
    return units * rate / 1000000 * rateKrw;
  }

  FirebaseCostEntry record(
    String kind, {
    required int count,
    int bytes = 0,
    int fields = 0,
    bool uncertain = false,
    bool initialSnapshot = false,
    bool isRead = false,
    FirestoreReadStrategy readStrategy = FirestoreReadStrategy.unknown,
    int pointReadUnits = 0,
    int indexBytes = 0,
    List<FirestoreWriteMetric>? writeMetrics,
    int possibleExtraReads = 0,
    int unknownRemoved = 0,
    bool reconnectCandidate = false,
    bool metadataOnly = false,
    String reason = '',
  }) {
    final bool read = isRead || initialSnapshot || kind == 'snapshot';
    final int units = read
        ? _readUnits(count, bytes,
            emptyMinimum: isRead || initialSnapshot,
            strategy: readStrategy,
            pointReadUnits: pointReadUnits,
            indexBytes: indexBytes)
        : _writeUnits(count, bytes, writeMetrics);
    final amount = _price(kind, units, initialSnapshot: initialSnapshot);
    final extraUnits = math.max(0, possibleExtraReads);
    final extra = _price(kind, extraUnits, initialSnapshot: initialSnapshot);
    final flagged = uncertain || extraUnits > 0 || reconnectCandidate ||
        (enterprise && !read && count > 0 &&
            (writeMetrics == null || writeMetrics.any((m) => !m.sizeKnown || m.indexWriteUnits == 0))) ||
        (enterprise && read && readStrategy == FirestoreReadStrategy.unknown);
    final entry = FirebaseCostEntry(
      kind: kind, units: units, won: amount, bytes: bytes, fields: fields,
      uncertain: flagged, possibleExtraUnits: extraUnits,
      possibleExtraWon: extra, reason: reason,
    );
    if (units > 0) {
      _totalWon += amount;
      _totalUnits += units;
      _won.update(kind, (v) => v + amount, ifAbsent: () => amount);
      _units.update(kind, (v) => v + units, ifAbsent: () => units);
    }
    _possibleExtraWon += extra;
    _possibleExtraUnits += extraUnits;
    _unknownRemoved += unknownRemoved;
    if (reconnectCandidate) _reconnectCandidates++;
    if (metadataOnly) _metadataOnlyEvents++;
    if (flagged) _uncertainOperations++;
    _knownBytes += bytes;
    _knownFields += fields;
    _recent.addLast(entry);
    while (_recent.length > 200) _recent.removeFirst();
    return entry;
  }
}
