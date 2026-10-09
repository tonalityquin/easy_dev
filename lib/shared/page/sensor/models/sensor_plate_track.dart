import '../../live_ocr/models/live_ocr_runtime.dart';
import 'sensor_ocr_frame_evidence.dart';

class SensorTrackFrameUpdate {
  const SensorTrackFrameUpdate({
    required this.frameQuality,
    required this.newBestFrame,
    required this.primaryIdentity,
    required this.identityFrames,
    required this.needsMiddleRecovery,
    required this.clipped,
    required this.hasStructured,
    required this.hasPartial,
  });

  final double frameQuality;
  final bool newBestFrame;
  final String? primaryIdentity;
  final int identityFrames;
  final bool needsMiddleRecovery;
  final bool clipped;
  final bool hasStructured;
  final bool hasPartial;
}

class SensorCompleteEvidence {
  const SensorCompleteEvidence({
    required this.plate,
    required this.identityKey,
    required this.completeVotes,
    required this.identityFrames,
    required this.midFrames,
  });

  final String plate;
  final String identityKey;
  final int completeVotes;
  final int identityFrames;
  final int midFrames;
}


enum _SensorMidEvidenceSource {
  structured,
  partial,
  strict,
  loose,
  partialRecovery,
  dynamicRecovery,
  forceInsert,
  multiFrameFusion,
}

class _SensorMidAttemptEvidence {
  const _SensorMidAttemptEvidence({
    required this.weight,
    required this.source,
  });

  final double weight;
  final _SensorMidEvidenceSource source;
}

class SensorPlateTrack {
  SensorPlateTrack({this.maxFrames = 12});

  final int maxFrames;
  final List<SensorOcrFrameEvidence> _frames = <SensorOcrFrameEvidence>[];
  final Map<String, int> _signatureVotes = <String, int>{};
  final Map<String, double> _bestSignatureScores = <String, double>{};
  final Map<String, LiveOcrStructuredObservation> _bestBySignature =
      <String, LiveOcrStructuredObservation>{};
  final Map<String, int> _bestFrameAttemptBySignature = <String, int>{};
  final Map<String, Set<int>> _identityAttempts = <String, Set<int>>{};
  final Map<String, double> _bestIdentityScores = <String, double>{};
  final Map<String, LiveOcrStructuredObservation> _bestByIdentity =
      <String, LiveOcrStructuredObservation>{};
  final Map<String, int> _bestFrameAttemptByIdentity = <String, int>{};
  final Map<String, Map<String, double>> _midWeightsByIdentity =
      <String, Map<String, double>>{};
  final Map<String, Map<String, Set<int>>> _midAttemptsByIdentity =
      <String, Map<String, Set<int>>>{};
  final Map<String, Map<String, Map<int, _SensorMidAttemptEvidence>>>
      _midEvidenceByIdentity =
      <String, Map<String, Map<int, _SensorMidAttemptEvidence>>>{};
  final Map<String, Set<int>> _completeAttemptsByPlate = <String, Set<int>>{};
  final Map<String, String> _completeIdentityByPlate = <String, String>{};
  final Map<String, double> _completeWeightByPlate = <String, double>{};
  final Map<String, LiveOcrCompleteSource> _latestCompleteSourceByPlate =
      <String, LiveOcrCompleteSource>{};
  double? _bestFrameQuality;
  int? _bestFrameAttempt;
  String _lastMidEvidenceDecision = '-';

  List<SensorOcrFrameEvidence> get frames =>
      List<SensorOcrFrameEvidence>.unmodifiable(_frames);

  int get frameCount => _frames.length;

  double? get bestFrameQuality => _bestFrameQuality;

  int? get bestFrameAttempt => _bestFrameAttempt;

  void reset() {
    _frames.clear();
    _signatureVotes.clear();
    _bestSignatureScores.clear();
    _bestBySignature.clear();
    _bestFrameAttemptBySignature.clear();
    _identityAttempts.clear();
    _bestIdentityScores.clear();
    _bestByIdentity.clear();
    _bestFrameAttemptByIdentity.clear();
    _midWeightsByIdentity.clear();
    _midAttemptsByIdentity.clear();
    _midEvidenceByIdentity.clear();
    _completeAttemptsByPlate.clear();
    _completeIdentityByPlate.clear();
    _completeWeightByPlate.clear();
    _latestCompleteSourceByPlate.clear();
    _bestFrameQuality = null;
    _bestFrameAttempt = null;
    _lastMidEvidenceDecision = '-';
  }

  SensorTrackFrameUpdate add(SensorOcrFrameEvidence frame) {
    _frames.add(frame);
    if (_frames.length > maxFrames) {
      _frames.removeAt(0);
    }

    for (final observation in frame.structured) {
      _signatureVotes[observation.signature] =
          (_signatureVotes[observation.signature] ?? 0) + 1;
      final identityKey = observation.identityKey;
      _identityAttempts.putIfAbsent(identityKey, () => <int>{}).add(frame.attempt);
      final score = frame.scoreOf(observation);
      final previousSignatureScore = _bestSignatureScores[observation.signature];
      if (previousSignatureScore == null || score > previousSignatureScore) {
        _bestSignatureScores[observation.signature] = score;
        _bestBySignature[observation.signature] = observation;
        _bestFrameAttemptBySignature[observation.signature] = frame.attempt;
      }
      final previousIdentityScore = _bestIdentityScores[identityKey];
      if (previousIdentityScore == null || score > previousIdentityScore) {
        _bestIdentityScores[identityKey] = score;
        _bestByIdentity[identityKey] = observation;
        _bestFrameAttemptByIdentity[identityKey] = frame.attempt;
      }
      if (RegExp(r'^[가-힣]$').hasMatch(observation.observedToken)) {
        _addMidEvidence(
          identityKey: identityKey,
          mid: observation.observedToken,
          attempt: frame.attempt,
          weight: 2.0,
          source: _SensorMidEvidenceSource.structured,
        );
      }
    }

    for (final partial in frame.partial) {
      final identityKey = partial.identityKey;
      if (identityKey == null) continue;
      _identityAttempts.putIfAbsent(identityKey, () => <int>{}).add(frame.attempt);
      if (RegExp(r'^[가-힣]$').hasMatch(partial.mid)) {
        _addMidEvidence(
          identityKey: identityKey,
          mid: partial.mid,
          attempt: frame.attempt,
          weight: 1.8,
          source: _SensorMidEvidenceSource.partial,
        );
      }
    }

    final frameQuality = frame.frameQuality;
    final previousBest = _bestFrameQuality;
    final newBestFrame = previousBest == null || frameQuality > previousBest + .05;
    if (newBestFrame) {
      _bestFrameQuality = frameQuality;
      _bestFrameAttempt = frame.attempt;
    }

    final primaryIdentity = frame.primaryIdentity;
    return SensorTrackFrameUpdate(
      frameQuality: frameQuality,
      newBestFrame: newBestFrame,
      primaryIdentity: primaryIdentity,
      identityFrames:
          primaryIdentity == null ? 0 : identityFrameCount(primaryIdentity),
      needsMiddleRecovery: frame.needsMiddleRecovery,
      clipped: frame.clipped,
      hasStructured: frame.structured.isNotEmpty,
      hasPartial: frame.partial.isNotEmpty,
    );
  }

  SensorCompleteEvidence observeComplete(
    LiveOcrCompleteObservation observation,
  ) {
    final parsed = _parseCompletePlate(observation.plate);
    final identityKey = parsed == null
        ? 'plate:${observation.plate}'
        : '${parsed.$1}|${parsed.$3}';
    _completeAttemptsByPlate
        .putIfAbsent(observation.plate, () => <int>{})
        .add(observation.attempt);
    _completeIdentityByPlate[observation.plate] = identityKey;
    _identityAttempts
        .putIfAbsent(identityKey, () => <int>{})
        .add(observation.attempt);
    final sourceWeight = _sourceWeight(observation.source);
    final geometryMultiplier = observation.geometryReliable == false ? .72 : 1.0;
    final weight = sourceWeight * geometryMultiplier;
    final previousWeight = _completeWeightByPlate[observation.plate] ?? 0.0;
    if (weight > previousWeight) {
      _completeWeightByPlate[observation.plate] = weight;
    }
    _latestCompleteSourceByPlate[observation.plate] = observation.source;
    if (parsed != null) {
      _addMidEvidence(
        identityKey: identityKey,
        mid: parsed.$2,
        attempt: observation.attempt,
        weight: weight,
        source: _midEvidenceSource(observation.source),
      );
    }
    return SensorCompleteEvidence(
      plate: observation.plate,
      identityKey: identityKey,
      completeVotes: completeVoteCount(observation.plate),
      identityFrames: identityFrameCount(identityKey),
      midFrames: parsed == null ? 0 : midFrameCount(identityKey, parsed.$2),
    );
  }

  void _addMidEvidence({
    required String identityKey,
    required String mid,
    required int attempt,
    required double weight,
    required _SensorMidEvidenceSource source,
  }) {
    if (mid.isEmpty || !weight.isFinite || weight <= 0) return;
    final votes = _midWeightsByIdentity.putIfAbsent(
      identityKey,
      () => <String, double>{},
    );
    final attempts = _midAttemptsByIdentity.putIfAbsent(
      identityKey,
      () => <String, Set<int>>{},
    );
    final attemptSet = attempts.putIfAbsent(mid, () => <int>{});
    final byMid = _midEvidenceByIdentity.putIfAbsent(
      identityKey,
      () => <String, Map<int, _SensorMidAttemptEvidence>>{},
    );
    final byAttempt = byMid.putIfAbsent(
      mid,
      () => <int, _SensorMidAttemptEvidence>{},
    );
    final previous = byAttempt[attempt];
    if (previous == null) {
      byAttempt[attempt] = _SensorMidAttemptEvidence(
        weight: weight,
        source: source,
      );
      attemptSet.add(attempt);
      final total = (votes[mid] ?? 0.0) + weight;
      votes[mid] = total;
      _lastMidEvidenceDecision =
          'add identity=$identityKey mid=$mid attempt=$attempt '
          'source=${source.name} weight=${weight.toStringAsFixed(2)} '
          'frames=${attemptSet.length} total=${total.toStringAsFixed(2)}';
      return;
    }

    attemptSet.add(attempt);
    if (weight > previous.weight + .0001) {
      byAttempt[attempt] = _SensorMidAttemptEvidence(
        weight: weight,
        source: source,
      );
      final delta = weight - previous.weight;
      final total = (votes[mid] ?? 0.0) + delta;
      votes[mid] = total;
      _lastMidEvidenceDecision =
          'promote identity=$identityKey mid=$mid attempt=$attempt '
          'from=${previous.weight.toStringAsFixed(2)} '
          'to=${weight.toStringAsFixed(2)} '
          'fromSource=${previous.source.name} source=${source.name} '
          'frames=${attemptSet.length} total=${total.toStringAsFixed(2)}';
      return;
    }

    _lastMidEvidenceDecision =
        'keep identity=$identityKey mid=$mid attempt=$attempt '
        'kept=${previous.weight.toStringAsFixed(2)} '
        'incoming=${weight.toStringAsFixed(2)} '
        'keptSource=${previous.source.name} source=${source.name} '
        'frames=${attemptSet.length} '
        'total=${(votes[mid] ?? 0.0).toStringAsFixed(2)}';
  }

  _SensorMidEvidenceSource _midEvidenceSource(
    LiveOcrCompleteSource source,
  ) {
    switch (source) {
      case LiveOcrCompleteSource.strict:
        return _SensorMidEvidenceSource.strict;
      case LiveOcrCompleteSource.loose:
        return _SensorMidEvidenceSource.loose;
      case LiveOcrCompleteSource.partialRecovery:
        return _SensorMidEvidenceSource.partialRecovery;
      case LiveOcrCompleteSource.dynamicRecovery:
        return _SensorMidEvidenceSource.dynamicRecovery;
      case LiveOcrCompleteSource.forceInsert:
        return _SensorMidEvidenceSource.forceInsert;
      case LiveOcrCompleteSource.multiFrameFusion:
        return _SensorMidEvidenceSource.multiFrameFusion;
    }
  }

  double _sourceWeight(LiveOcrCompleteSource source) {
    switch (source) {
      case LiveOcrCompleteSource.strict:
        return 5.0;
      case LiveOcrCompleteSource.loose:
        return 4.0;
      case LiveOcrCompleteSource.partialRecovery:
        return 4.2;
      case LiveOcrCompleteSource.dynamicRecovery:
        return 4.6;
      case LiveOcrCompleteSource.forceInsert:
        return 2.5;
      case LiveOcrCompleteSource.multiFrameFusion:
        return 5.0;
    }
  }

  (String, String, String)? _parseCompletePlate(String plate) {
    final match = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(plate);
    if (match == null) return null;
    return (match.group(1)!, match.group(2)!, match.group(3)!);
  }

  int identityFrameCount(String identityKey) =>
      _identityAttempts[identityKey]?.length ?? 0;

  int completeVoteCount(String plate) =>
      _completeAttemptsByPlate[plate]?.length ?? 0;

  int midFrameCount(String identityKey, String mid) =>
      _midAttemptsByIdentity[identityKey]?[mid]?.length ?? 0;

  double completeWeight(String plate) => _completeWeightByPlate[plate] ?? 0.0;

  LiveOcrCompleteSource? completeSource(String plate) =>
      _latestCompleteSourceByPlate[plate];

  LiveOcrStructuredObservation? get bestStructured {
    if (_bestByIdentity.isEmpty) return null;
    final ranked = _bestByIdentity.entries.toList(growable: false)
      ..sort((a, b) {
        final aFrames = identityFrameCount(a.key);
        final bFrames = identityFrameCount(b.key);
        final byFrames = bFrames.compareTo(aFrames);
        if (byFrames != 0) return byFrames;
        final aSingle = a.value.observedToken.length == 1 ? 1 : 0;
        final bSingle = b.value.observedToken.length == 1 ? 1 : 0;
        final bySingle = bSingle.compareTo(aSingle);
        if (bySingle != 0) return bySingle;
        final aScore = _bestIdentityScores[a.key] ?? a.value.score;
        final bScore = _bestIdentityScores[b.key] ?? b.value.score;
        final byScore = bScore.compareTo(aScore);
        if (byScore != 0) return byScore;
        final byFront = b.value.frontLen.compareTo(a.value.frontLen);
        if (byFront != 0) return byFront;
        return a.key.compareTo(b.key);
      });
    return ranked.first.value;
  }

  String? get bestIdentityKey => bestStructured?.identityKey;

  String? get bestCompletePlate {
    if (_completeAttemptsByPlate.isEmpty) return null;
    final ranked = _completeAttemptsByPlate.keys.toList(growable: false)
      ..sort((a, b) {
        final aVotes = completeVoteCount(a);
        final bVotes = completeVoteCount(b);
        final byVotes = bVotes.compareTo(aVotes);
        if (byVotes != 0) return byVotes;
        final aIdentity = _completeIdentityByPlate[a] ?? '';
        final bIdentity = _completeIdentityByPlate[b] ?? '';
        final byIdentityFrames =
            identityFrameCount(bIdentity).compareTo(identityFrameCount(aIdentity));
        if (byIdentityFrames != 0) return byIdentityFrames;
        final byWeight = completeWeight(b).compareTo(completeWeight(a));
        if (byWeight != 0) return byWeight;
        return a.compareTo(b);
      });
    return ranked.first;
  }

  String? get fusedPlate {
    final complete = bestCompletePlate;
    if (complete != null) {
      final identityKey = _completeIdentityByPlate[complete];
      final parsed = _parseCompletePlate(complete);
      if (identityKey != null) {
        final repeated = completeVoteCount(complete) >= 2;
        final midCorroborated = parsed != null &&
            identityFrameCount(identityKey) >= 2 &&
            midFrameCount(identityKey, parsed.$2) >= 2;
        if (repeated || midCorroborated) {
          return complete;
        }
      }
    }

    final identity = bestStructured;
    if (identity == null) return null;
    final identityKey = identity.identityKey;
    if (identityFrameCount(identityKey) < 2) return null;
    final midVotes = _midWeightsByIdentity[identityKey];
    if (midVotes == null || midVotes.isEmpty) return null;
    final mid = _topMid(identityKey, midVotes);
    if (mid == null) return null;
    final midAttempts = _midAttemptsByIdentity[identityKey]?[mid];
    if (midAttempts == null || midAttempts.isEmpty) return null;
    if (!RegExp(r'^\d{2,3}$').hasMatch(identity.front)) return null;
    if (!RegExp(r'^[가-힣]$').hasMatch(mid)) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(identity.back)) return null;
    return '${identity.front}$mid${identity.back}';
  }

  String? _topMid(String identityKey, Map<String, double> votes) {
    if (votes.isEmpty) return null;
    final attempts = _midAttemptsByIdentity[identityKey] ?? const <String, Set<int>>{};
    final ranked = votes.entries.toList(growable: false)
      ..sort((a, b) {
        final byWeight = b.value.compareTo(a.value);
        if (byWeight != 0) return byWeight;
        final byAttempts =
            (attempts[b.key]?.length ?? 0).compareTo(attempts[a.key]?.length ?? 0);
        if (byAttempts != 0) return byAttempts;
        return a.key.compareTo(b.key);
      });
    return ranked.first.key;
  }

  String get debugStatus {
    final best = bestStructured;
    final signatureVotes = _signatureVotes.entries.toList(growable: false)
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        if (byValue != 0) return byValue;
        return a.key.compareTo(b.key);
      });
    final identityVotes = _identityAttempts.entries.toList(growable: false)
      ..sort((a, b) {
        final byValue = b.value.length.compareTo(a.value.length);
        if (byValue != 0) return byValue;
        return a.key.compareTo(b.key);
      });
    final completeVotes = _completeAttemptsByPlate.entries.toList(growable: false)
      ..sort((a, b) {
        final byValue = b.value.length.compareTo(a.value.length);
        if (byValue != 0) return byValue;
        return a.key.compareTo(b.key);
      });
    final clippedFrames = _frames.where((frame) => frame.clipped).length;
    return 'frames=$frameCount best=${best?.signature ?? '-'} '
        'identity=${best?.identityKey ?? '-'} '
        'bestFrame=${bestFrameAttempt ?? '-'} '
        'bestQuality=${bestFrameQuality?.toStringAsFixed(2) ?? '-'} '
        'clippedFrames=$clippedFrames bestRaw=${best?.rawValue ?? '-'} '
        'fused=${fusedPlate ?? '-'} '
        'midEvidence=$_lastMidEvidenceDecision '
        'identityVotes=${identityVotes.map((e) => '${e.key}:${e.value.length}').join('|')} '
        'signatureVotes=${signatureVotes.map((e) => '${e.key}:${e.value}').join('|')} '
        'completeVotes=${completeVotes.map((e) => '${e.key}:${e.value.length}').join('|')}';
  }
}
