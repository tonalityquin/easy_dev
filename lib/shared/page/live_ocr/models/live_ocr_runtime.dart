import 'dart:typed_data';

class LiveOcrRuntimeProfile {
  const LiveOcrRuntimeProfile({
    required this.name,
    required this.autoIntervalMs,
    required this.voteWindow,
    required this.weakStructuredVoteThreshold,
    required this.heavyRecoveryCooldownFrames,
    required this.allowStableSingleSlotProbe,
    required this.autoSelectIncomplete,
    required this.enableAutoRefocus,
    required this.maxAttempts,
    required this.returnBestIncompleteOnLimit,
    required this.developerRecoveredHoldMs,
    required this.decodeGeometryEveryFrame,
    required this.repeatRecoveryAcrossFrames,
    required this.showCandidateChips,
    required this.showOperationCaption,
  });

  final String name;
  final int autoIntervalMs;
  final int voteWindow;
  final int weakStructuredVoteThreshold;
  final int heavyRecoveryCooldownFrames;
  final bool allowStableSingleSlotProbe;
  final bool autoSelectIncomplete;
  final bool enableAutoRefocus;
  final int maxAttempts;
  final bool returnBestIncompleteOnLimit;
  final int developerRecoveredHoldMs;
  final bool decodeGeometryEveryFrame;
  final bool repeatRecoveryAcrossFrames;
  final bool showCandidateChips;
  final bool showOperationCaption;
}

class LiveOcrStructuredObservation {
  const LiveOcrStructuredObservation({
    required this.signature,
    required this.front,
    required this.back,
    required this.observedToken,
    required this.rawValue,
    required this.frontLen,
    required this.score,
  });

  final String signature;
  final String front;
  final String back;
  final String observedToken;
  final String rawValue;
  final int frontLen;
  final double score;

  String get identityKey => '$front|$back';
}

class LiveOcrPartialObservation {
  const LiveOcrPartialObservation({
    required this.front,
    required this.mid,
    required this.back,
    required this.frontLen,
    required this.score,
  });

  final String? front;
  final String mid;
  final String? back;
  final int frontLen;
  final double score;

  String? get identityKey {
    final frontValue = front;
    final backValue = back;
    if (frontValue == null || backValue == null) return null;
    return '$frontValue|$backValue';
  }
}

class LiveOcrFrameObservation {
  const LiveOcrFrameObservation({
    required this.attempt,
    required this.ocrText,
    required this.geometryReliable,
    required this.structured,
    required this.partial,
    required this.capturedAt,
    required this.plateAreaRatio,
    required this.leftClipped,
    required this.rightClipped,
    required this.topClipped,
    required this.bottomClipped,
  });

  final int attempt;
  final String ocrText;
  final bool? geometryReliable;
  final List<LiveOcrStructuredObservation> structured;
  final List<LiveOcrPartialObservation> partial;
  final DateTime capturedAt;
  final double? plateAreaRatio;
  final bool leftClipped;
  final bool rightClipped;
  final bool topClipped;
  final bool bottomClipped;

  bool get clipped => leftClipped || rightClipped || topClipped || bottomClipped;
}

enum LiveOcrCompleteSource {
  strict,
  loose,
  partialRecovery,
  dynamicRecovery,
  forceInsert,
  multiFrameFusion,
}

class LiveOcrCompleteObservation {
  const LiveOcrCompleteObservation({
    required this.plate,
    required this.attempt,
    required this.source,
    required this.geometryReliable,
    required this.capturedAt,
  });

  final String plate;
  final int attempt;
  final LiveOcrCompleteSource source;
  final bool? geometryReliable;
  final DateTime capturedAt;
}

enum LiveOcrCompleteAction {
  accept,
  defer,
  reject,
}

class LiveOcrCompleteDecision {
  const LiveOcrCompleteDecision({
    required this.action,
    required this.reason,
    this.completeVotes = 0,
    this.identityFrames = 0,
  });

  const LiveOcrCompleteDecision.accept({
    required this.reason,
    this.completeVotes = 0,
    this.identityFrames = 0,
  }) : action = LiveOcrCompleteAction.accept;

  const LiveOcrCompleteDecision.defer({
    required this.reason,
    this.completeVotes = 0,
    this.identityFrames = 0,
  }) : action = LiveOcrCompleteAction.defer;

  const LiveOcrCompleteDecision.reject({
    required this.reason,
    this.completeVotes = 0,
    this.identityFrames = 0,
  }) : action = LiveOcrCompleteAction.reject;

  final LiveOcrCompleteAction action;
  final String reason;
  final int completeVotes;
  final int identityFrames;

  bool get accepted => action == LiveOcrCompleteAction.accept;
  bool get deferred => action == LiveOcrCompleteAction.defer;
}

class LiveOcrFrameDecision {
  const LiveOcrFrameDecision({
    required this.allowHeavyRecovery,
    required this.captureNextImmediately,
    required this.reason,
    this.preferredIdentity,
    this.frameQuality,
  });

  const LiveOcrFrameDecision.input()
      : allowHeavyRecovery = true,
        captureNextImmediately = false,
        reason = 'inputDefault',
        preferredIdentity = null,
        frameQuality = null;

  final bool allowHeavyRecovery;
  final bool captureNextImmediately;
  final String reason;
  final String? preferredIdentity;
  final double? frameQuality;
}

abstract class LiveOcrCoordinator {
  LiveOcrRuntimeProfile get profile;

  Uint8List? get initialFrameBytes => null;

  void reset();

  LiveOcrFrameDecision observeFrame(LiveOcrFrameObservation observation);

  LiveOcrCompleteDecision evaluateCompleteCandidate(
    LiveOcrCompleteObservation observation,
  );

  LiveOcrStructuredObservation? get bestStructuredObservation;

  String? get fusedCompletePlate;

  String get debugStatus;
}

class PassiveLiveOcrCoordinator implements LiveOcrCoordinator {
  PassiveLiveOcrCoordinator(this.profile, {this.initialFrameBytes});

  @override
  final LiveOcrRuntimeProfile profile;

  @override
  final Uint8List? initialFrameBytes;

  @override
  LiveOcrStructuredObservation? get bestStructuredObservation => null;

  @override
  String? get fusedCompletePlate => null;

  @override
  String get debugStatus => 'profile=${profile.name}';

  @override
  LiveOcrCompleteDecision evaluateCompleteCandidate(
    LiveOcrCompleteObservation observation,
  ) {
    return const LiveOcrCompleteDecision.accept(reason: 'passiveImmediate');
  }

  @override
  LiveOcrFrameDecision observeFrame(LiveOcrFrameObservation observation) {
    return const LiveOcrFrameDecision.input();
  }

  @override
  void reset() {}
}
