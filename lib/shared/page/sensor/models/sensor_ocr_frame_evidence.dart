import '../../live_ocr/models/live_ocr_runtime.dart';

class SensorOcrFrameEvidence {
  const SensorOcrFrameEvidence({
    required this.attempt,
    required this.capturedAt,
    required this.ocrText,
    required this.geometryReliable,
    required this.structured,
    required this.partial,
    required this.plateAreaRatio,
    required this.leftClipped,
    required this.rightClipped,
    required this.topClipped,
    required this.bottomClipped,
  });

  final int attempt;
  final DateTime capturedAt;
  final String ocrText;
  final bool? geometryReliable;
  final List<LiveOcrStructuredObservation> structured;
  final List<LiveOcrPartialObservation> partial;
  final double? plateAreaRatio;
  final bool leftClipped;
  final bool rightClipped;
  final bool topClipped;
  final bool bottomClipped;

  bool get clipped => leftClipped || rightClipped || topClipped || bottomClipped;

  LiveOcrStructuredObservation? get bestStructuredObservation {
    if (structured.isEmpty) return null;
    final ranked = structured.toList(growable: false)
      ..sort((a, b) {
        final byScore = scoreOf(b).compareTo(scoreOf(a));
        if (byScore != 0) return byScore;
        final bySingle = (b.observedToken.length == 1 ? 1 : 0)
            .compareTo(a.observedToken.length == 1 ? 1 : 0);
        if (bySingle != 0) return bySingle;
        final byFront = b.frontLen.compareTo(a.frontLen);
        if (byFront != 0) return byFront;
        return a.signature.compareTo(b.signature);
      });
    return ranked.first;
  }

  String? get primaryIdentity => bestStructuredObservation?.identityKey;

  bool get needsMiddleRecovery {
    final best = bestStructuredObservation;
    if (best == null) return false;
    return !RegExp(r'^[가-힣]$').hasMatch(best.observedToken);
  }

  double get frameQuality {
    var quality = 0.0;
    if (geometryReliable == true) quality += 1.4;
    if (geometryReliable == false) quality -= 1.4;
    if (clipped) quality -= 4.5;
    final ratio = plateAreaRatio;
    if (ratio != null) {
      if (ratio >= .015 && ratio <= .28) quality += 1.5;
      if (ratio >= .035 && ratio <= .20) quality += .8;
      if (ratio < .004) quality -= 1.4;
      if (ratio > .45) quality -= 2.0;
    }
    final best = bestStructuredObservation;
    if (best != null) {
      quality += scoreOf(best);
    } else if (partial.isNotEmpty) {
      final partialScores = partial.map((entry) => entry.score).toList()
        ..sort((a, b) => b.compareTo(a));
      quality += 1.0 + partialScores.first.clamp(0.0, 6.0) * .18;
    } else if (ocrText.isNotEmpty) {
      quality += .2;
    }
    return quality;
  }

  double scoreOf(LiveOcrStructuredObservation observation) {
    var score = observation.score;
    if (observation.frontLen == 3) score += .4;
    if (observation.observedToken.length == 1) score += 5.0;
    if (geometryReliable == true) score += 1.0;
    if (geometryReliable == false) score -= 1.0;
    if (clipped) score -= 4.0;
    final ratio = plateAreaRatio;
    if (ratio != null) {
      if (ratio >= .015 && ratio <= .28) score += 1.2;
      if (ratio < .004) score -= 1.2;
      if (ratio > .45) score -= 1.5;
    }
    return score;
  }
}
