import 'dart:typed_data';

import '../../live_ocr/models/live_ocr_runtime.dart';

class InputLiveOcrController implements LiveOcrCoordinator {
  InputLiveOcrController();

  static const LiveOcrRuntimeProfile _profile = LiveOcrRuntimeProfile(
    name: 'input',
    autoIntervalMs: 900,
    voteWindow: 4,
    weakStructuredVoteThreshold: 2,
    heavyRecoveryCooldownFrames: 2,
    allowStableSingleSlotProbe: true,
    autoSelectIncomplete: true,
    enableAutoRefocus: true,
    maxAttempts: 0,
    returnBestIncompleteOnLimit: false,
    developerRecoveredHoldMs: 720,
    decodeGeometryEveryFrame: false,
    repeatRecoveryAcrossFrames: false,
    showCandidateChips: true,
    showOperationCaption: true,
  );

  @override
  LiveOcrRuntimeProfile get profile => _profile;

  @override
  Uint8List? get initialFrameBytes => null;

  @override
  LiveOcrStructuredObservation? get bestStructuredObservation => null;

  @override
  String? get fusedCompletePlate => null;

  @override
  String get debugStatus => 'profile=input';

  @override
  LiveOcrCompleteDecision evaluateCompleteCandidate(
    LiveOcrCompleteObservation observation,
  ) {
    return const LiveOcrCompleteDecision.accept(reason: 'inputImmediate');
  }

  @override
  LiveOcrFrameDecision observeFrame(LiveOcrFrameObservation observation) {
    return const LiveOcrFrameDecision.input();
  }

  @override
  void reset() {}
}
