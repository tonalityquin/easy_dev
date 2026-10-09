import 'dart:typed_data';

import '../../live_ocr/models/live_ocr_runtime.dart';
import '../models/sensor_ocr_frame_evidence.dart';
import '../models/sensor_plate_track.dart';

class SensorLiveOcrController implements LiveOcrCoordinator {
  SensorLiveOcrController({
    this.allowIncompleteResult = false,
    this.initialFrameBytes,
  });

  final bool allowIncompleteResult;

  @override
  final Uint8List? initialFrameBytes;

  final SensorPlateTrack track = SensorPlateTrack(maxFrames: 12);
  String _lastFrameDecision = '-';
  String _lastCompleteDecision = '-';

  LiveOcrRuntimeProfile get _runtimeProfile => LiveOcrRuntimeProfile(
        name: allowIncompleteResult ? 'sensor_dev_apply' : 'sensor',
        autoIntervalMs: 200,
        voteWindow: 8,
        weakStructuredVoteThreshold: 2,
        heavyRecoveryCooldownFrames: 1,
        allowStableSingleSlotProbe: true,
        autoSelectIncomplete: false,
        enableAutoRefocus: false,
        maxAttempts: 10,
        returnBestIncompleteOnLimit: allowIncompleteResult,
        developerRecoveredHoldMs: 120,
        decodeGeometryEveryFrame: true,
        repeatRecoveryAcrossFrames: true,
        showCandidateChips: false,
        showOperationCaption: false,
      );

  @override
  LiveOcrRuntimeProfile get profile => _runtimeProfile;

  @override
  LiveOcrStructuredObservation? get bestStructuredObservation =>
      track.bestStructured;

  @override
  String? get fusedCompletePlate => track.fusedPlate;

  @override
  String get debugStatus =>
      'profile=${profile.name} frameDecision=$_lastFrameDecision '
      'completeDecision=$_lastCompleteDecision ${track.debugStatus}';

  @override
  LiveOcrCompleteDecision evaluateCompleteCandidate(
    LiveOcrCompleteObservation observation,
  ) {
    final evidence = track.observeComplete(observation);
    if (evidence.identityKey.isEmpty) {
      _lastCompleteDecision =
          'plate=${observation.plate} action=reject reason=invalidComplete';
      return const LiveOcrCompleteDecision.reject(reason: 'invalidComplete');
    }

    if (observation.source == LiveOcrCompleteSource.multiFrameFusion) {
      _lastCompleteDecision =
          'plate=${observation.plate} action=accept reason=multiFrameFusion '
          'completeVotes=${evidence.completeVotes} identityFrames=${evidence.identityFrames} '
          'midFrames=${evidence.midFrames}';
      return LiveOcrCompleteDecision.accept(
        reason: 'multiFrameFusion',
        completeVotes: evidence.completeVotes,
        identityFrames: evidence.identityFrames,
      );
    }

    if (observation.source == LiveOcrCompleteSource.forceInsert) {
      _lastCompleteDecision =
          'plate=${observation.plate} action=accept reason=forceInsert '
          'completeVotes=${evidence.completeVotes} identityFrames=${evidence.identityFrames} '
          'midFrames=${evidence.midFrames}';
      return LiveOcrCompleteDecision.accept(
        reason: 'forceInsert',
        completeVotes: evidence.completeVotes,
        identityFrames: evidence.identityFrames,
      );
    }

    if (evidence.completeVotes >= 2) {
      _lastCompleteDecision =
          'plate=${observation.plate} action=accept reason=repeatComplete '
          'completeVotes=${evidence.completeVotes} identityFrames=${evidence.identityFrames}';
      return LiveOcrCompleteDecision.accept(
        reason: 'repeatComplete',
        completeVotes: evidence.completeVotes,
        identityFrames: evidence.identityFrames,
      );
    }

    final recoveryConfirmed =
        (observation.source == LiveOcrCompleteSource.dynamicRecovery ||
            observation.source == LiveOcrCompleteSource.partialRecovery) &&
        evidence.identityFrames >= 2;
    if (recoveryConfirmed) {
      _lastCompleteDecision =
          'plate=${observation.plate} action=accept reason=recoveryCorroborated '
          'completeVotes=${evidence.completeVotes} identityFrames=${evidence.identityFrames} '
          'midFrames=${evidence.midFrames}';
      return LiveOcrCompleteDecision.accept(
        reason: 'recoveryCorroborated',
        completeVotes: evidence.completeVotes,
        identityFrames: evidence.identityFrames,
      );
    }

    if (evidence.identityFrames >= 2 && evidence.midFrames >= 2) {
      _lastCompleteDecision =
          'plate=${observation.plate} action=accept reason=midCorroborated '
          'completeVotes=${evidence.completeVotes} identityFrames=${evidence.identityFrames} '
          'midFrames=${evidence.midFrames}';
      return LiveOcrCompleteDecision.accept(
        reason: 'midCorroborated',
        completeVotes: evidence.completeVotes,
        identityFrames: evidence.identityFrames,
      );
    }

    _lastCompleteDecision =
        'plate=${observation.plate} action=defer reason=awaitTemporalConfirmation '
        'completeVotes=${evidence.completeVotes} identityFrames=${evidence.identityFrames} '
        'midFrames=${evidence.midFrames}';
    return LiveOcrCompleteDecision.defer(
      reason: 'awaitTemporalConfirmation',
      completeVotes: evidence.completeVotes,
      identityFrames: evidence.identityFrames,
    );
  }

  @override
  LiveOcrFrameDecision observeFrame(LiveOcrFrameObservation observation) {
    final evidence = SensorOcrFrameEvidence(
      attempt: observation.attempt,
      capturedAt: observation.capturedAt,
      ocrText: observation.ocrText,
      geometryReliable: observation.geometryReliable,
      structured: observation.structured,
      partial: observation.partial,
      plateAreaRatio: observation.plateAreaRatio,
      leftClipped: observation.leftClipped,
      rightClipped: observation.rightClipped,
      topClipped: observation.topClipped,
      bottomClipped: observation.bottomClipped,
    );
    final update = track.add(evidence);
    final identity = update.primaryIdentity;
    final stableIdentity = update.identityFrames >= 2;
    final recoverable = update.hasStructured || update.hasPartial;
    final recoveryNeed = update.needsMiddleRecovery || update.hasPartial;
    final earlyStableIdentity =
        update.identityFrames >= 2 && update.identityFrames <= 3;
    final allowHeavyRecovery = recoverable &&
        recoveryNeed &&
        !update.clipped &&
        (earlyStableIdentity ||
            (update.newBestFrame && (stableIdentity || update.hasPartial)));

    final reason = allowHeavyRecovery
        ? (earlyStableIdentity
            ? 'earlyStableIdentityRecovery'
            : 'newBestRecoverableFrame')
        : update.clipped
            ? 'clippedFastPass'
            : !recoverable
                ? 'noRecoverableEvidence'
                : !recoveryNeed
                    ? 'noHeavyRecoveryNeed'
                    : !stableIdentity && !update.hasPartial
                        ? 'awaitIdentityStability'
                        : 'fastFramePreferred';

    _lastFrameDecision =
        'attempt=${observation.attempt} heavy=$allowHeavyRecovery '
        'nextImmediate=true reason=$reason identity=${identity ?? '-'} '
        'identityFrames=${update.identityFrames} '
        'quality=${update.frameQuality.toStringAsFixed(2)} '
        'newBest=${update.newBestFrame} clipped=${update.clipped}';

    return LiveOcrFrameDecision(
      allowHeavyRecovery: allowHeavyRecovery,
      captureNextImmediately: true,
      reason: reason,
      preferredIdentity: identity,
      frameQuality: update.frameQuality,
    );
  }

  @override
  void reset() {
    track.reset();
    _lastFrameDecision = '-';
    _lastCompleteDecision = '-';
  }
}
