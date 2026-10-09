import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Path, RRect, Rect;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/selector/application/dev_auth.dart';

import '../domain/ocr_learning_repository.dart';
import '../models/live_ocr_runtime.dart';

class _KoreanPlatePolicy {
  static const List<String> allowedNewMids = [
    '가',
    '나',
    '다',
    '라',
    '마',
    '거',
    '너',
    '더',
    '러',
    '머',
    '버',
    '서',
    '어',
    '저',
    '고',
    '노',
    '도',
    '로',
    '모',
    '보',
    '소',
    '오',
    '조',
    '구',
    '누',
    '두',
    '루',
    '무',
    '부',
    '수',
    '우',
    '육',
    '주',
    '아',
    '바',
    '사',
    '자',
    '하',
    '허',
    '호',
    '배'
  ];

  static const Map<String, String> staticMidNormalize = {
    '리': '러',
    '이': '어',
    '지': '저',
    '히': '허',
    '기': '거',
    '니': '너',
    '디': '더',
    '미': '머',
    '비': '버',
    '시': '서',
  };

  static const List<String> allowedRegions = [
    '서울',
    '부산',
    '대구',
    '인천',
    '광주',
    '대전',
    '울산',
    '세종',
    '경기',
    '강원',
    '충북',
    '충남',
    '전북',
    '전남',
    '경북',
    '경남',
    '제주'
  ];

  static String newMidCharClass() => allowedNewMids.join();

  static String regionAlternation() => allowedRegions.join('|');
}

enum _KoreanPlateFormat {
  modern,
  legacyRegion,
}

enum _ChipTier {
  stable,
  tentative,
  weak,
}

enum LiveOcrExitType {
  autoDirect,
  autoLoose,
  autoForceInsert,
  autoStructuredSelected,
  candidateChipSelected,
  userAborted,
  permissionDenied,
  cameraInitFailed,
  sensorTrackExhausted,
}

typedef LiveOcrExitPreparing = Future<void> Function(
  LiveOcrSessionResult result,
);

class LiveOcrSessionResult {
  final String sessionId;
  final String? plate;
  final LiveOcrExitType exitType;
  final List<String> logs;
  final List<String> candidateValues;
  final String? selectedChipLabel;
  final String? lastOcrText;
  final String? lastFailureReason;
  final int attemptCount;
  final bool usedLearningMid;
  final bool usedLearningRank;
  final String? weakFront;
  final String? weakBack;
  final String? weakObservedValue;
  final bool requiresMidCompletion;
  final List<String> weakMidSuggestions;

  const LiveOcrSessionResult({
    required this.sessionId,
    required this.plate,
    required this.exitType,
    required this.logs,
    required this.candidateValues,
    required this.selectedChipLabel,
    required this.lastOcrText,
    required this.lastFailureReason,
    required this.attemptCount,
    required this.usedLearningMid,
    required this.usedLearningRank,
    required this.weakFront,
    required this.weakBack,
    required this.weakObservedValue,
    required this.requiresMidCompletion,
    required this.weakMidSuggestions,
  });

  String get logText => logs.join('\n');
}

class _DisplayChip {
  final String value;
  final String label;
  final _ChipTier tier;
  final String? weakFront;
  final String? weakBack;
  final String? weakObservedValue;
  final bool requiresMidCompletion;
  final List<String> weakMidSuggestions;

  const _DisplayChip({
    required this.value,
    required this.label,
    required this.tier,
    this.weakFront,
    this.weakBack,
    this.weakObservedValue,
    this.requiresMidCompletion = false,
    this.weakMidSuggestions = const [],
  });
}

enum _WeakSegmentationEvidence {
  explicit,
  observedSlot,
  numericSlot,
  persistentBridge,
  inferred,
}

enum _PlateRecoverySlot {
  front,
  mid,
  back,
}

class _PlateSlotUncertainty {
  final bool front;
  final bool mid;
  final bool back;

  const _PlateSlotUncertainty({
    required this.front,
    required this.mid,
    required this.back,
  });
}

class _LocalBoundaryEvidence {
  final _PlateRecoverySlot slot;
  final String? front;
  final String? mid;
  final String? back;
  final String text;
  final Rect rect;
  final Uint8List bytes;
  final int ocrMs;
  final String sourceKind;
  final double score;

  const _LocalBoundaryEvidence({
    required this.slot,
    required this.front,
    required this.mid,
    required this.back,
    required this.text,
    required this.rect,
    required this.bytes,
    required this.ocrMs,
    required this.sourceKind,
    required this.score,
  });
}

class _LocalOcrBudget {
  final int maxAttempts;
  int used = 0;
  int totalOcrMs = 0;

  _LocalOcrBudget({required this.maxAttempts});

  bool get canRun => used < maxAttempts;

  bool consume() {
    if (!canRun) return false;
    used++;
    return true;
  }

  void addOcrMs(int value) {
    totalOcrMs += value;
  }
}

class _BoundaryAnchorCandidate {
  final Rect rect;
  final String sourceKind;
  final double score;

  const _BoundaryAnchorCandidate({
    required this.rect,
    required this.sourceKind,
    required this.score,
  });
}

class _PartialBoundarySeed {
  final _PlateRecoverySlot slot;
  final Rect plateBox;
  final String? front;
  final String mid;
  final String? back;
  final int frontLen;
  final String rawFront;
  final String rawBack;
  final String sourceText;
  final String sourceKind;
  final double score;

  const _PartialBoundarySeed({
    required this.slot,
    required this.plateBox,
    required this.front,
    required this.mid,
    required this.back,
    required this.frontLen,
    required this.rawFront,
    required this.rawBack,
    required this.sourceText,
    required this.sourceKind,
    required this.score,
  });

  String get signature => '${front ?? rawFront}?${back ?? rawBack}';
}

class _StructuredWeakCandidate {
  final String signature;
  final String front;
  final String back;
  final String observedToken;
  final String rawValue;
  final int frontLen;
  final bool tokenMissing;
  final _WeakSegmentationEvidence segmentationEvidence;
  final double score;

  const _StructuredWeakCandidate({
    required this.signature,
    required this.front,
    required this.back,
    required this.observedToken,
    required this.rawValue,
    required this.frontLen,
    required this.tokenMissing,
    required this.segmentationEvidence,
    required this.score,
  });
}

class _TopologyProbeDecision {
  final _StructuredWeakCandidate selected;
  final List<_StructuredWeakCandidate> alternatives;
  final bool probeEligible;
  final String reason;
  final String observations;
  final String ranking;

  const _TopologyProbeDecision({
    required this.selected,
    required this.alternatives,
    required this.probeEligible,
    required this.reason,
    required this.observations,
    required this.ranking,
  });
}

enum _OcrDebugStage {
  idle,
  capturing,
  fullOcr,
  weakPlateDetected,
  cropPrepared,
  cropOcr,
  localCropPrepared,
  localCropOcr,
  refocusing,
  recovered,
  fallback,
}

enum _OcrRecoveryMode {
  scanning,
  fastMidRecovery,
  candidateReady,
}

enum _OcrRecoveryPreviewPhase {
  none,
  plateDetected,
  plateRectified,
  midContext,
  midGlyph,
  midFocused,
}

class _OcrDebugLineBox {
  final Rect box;
  final String text;

  const _OcrDebugLineBox({
    required this.box,
    required this.text,
  });
}

class _PlateQuad {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const _PlateQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  double get topLength => (topRight - topLeft).distance;
  double get bottomLength => (bottomRight - bottomLeft).distance;
  double get leftLength => (bottomLeft - topLeft).distance;
  double get rightLength => (bottomRight - topRight).distance;

  double get angleRadians {
    final left = Offset(
      (topLeft.dx + bottomLeft.dx) / 2,
      (topLeft.dy + bottomLeft.dy) / 2,
    );
    final right = Offset(
      (topRight.dx + bottomRight.dx) / 2,
      (topRight.dy + bottomRight.dy) / 2,
    );
    final d = right - left;
    return math.atan2(d.dy, d.dx);
  }

  double get angleDegrees => angleRadians * 180 / math.pi;

  Rect get bounds => Rect.fromLTRB(
        math.min(topLeft.dx, bottomLeft.dx),
        math.min(topLeft.dy, topRight.dy),
        math.max(topRight.dx, bottomRight.dx),
        math.max(bottomLeft.dy, bottomRight.dy),
      );

  _PlateQuad clampTo(Size size) {
    Offset clampPoint(Offset p) => Offset(
          p.dx.clamp(0.0, math.max(0.0, size.width - 1)).toDouble(),
          p.dy.clamp(0.0, math.max(0.0, size.height - 1)).toDouble(),
        );
    return _PlateQuad(
      topLeft: clampPoint(topLeft),
      topRight: clampPoint(topRight),
      bottomRight: clampPoint(bottomRight),
      bottomLeft: clampPoint(bottomLeft),
    );
  }
}

class _WeakPlateRegion {
  final Rect box;
  final String front;
  final String back;
  final String signature;
  final String sourceText;
  final String sourceKind;
  final double score;
  final _PlateQuad? quad;

  const _WeakPlateRegion({
    required this.box,
    required this.front,
    required this.back,
    required this.signature,
    required this.sourceText,
    required this.sourceKind,
    required this.score,
    this.quad,
  });
}

class _MidRecoveryLayout {
  final Rect contextRect;
  final Rect leftAnchorRect;
  final Rect glyphRect;
  final Rect rightAnchorRect;
  final String sourceKind;
  final bool geometryBacked;

  const _MidRecoveryLayout({
    required this.contextRect,
    required this.leftAnchorRect,
    required this.glyphRect,
    required this.rightAnchorRect,
    required this.sourceKind,
    required this.geometryBacked,
  });
}

class _MidAnchorEvidence {
  final String expectedLeft;
  final String expectedRight;
  final String? observedLeft;
  final String? observedRight;
  final bool leftMatched;
  final bool rightMatched;
  final String sourceKind;
  final bool geometryBacked;

  const _MidAnchorEvidence({
    required this.expectedLeft,
    required this.expectedRight,
    required this.observedLeft,
    required this.observedRight,
    required this.leftMatched,
    required this.rightMatched,
    required this.sourceKind,
    required this.geometryBacked,
  });

  bool get strong => leftMatched && rightMatched;

  String get quality => geometryBacked ? 'geometryBacked' : 'slotSupported';
}

class _MidGlyphEvidence {
  final String mid;
  final double score;
  final String text;

  const _MidGlyphEvidence({
    required this.mid,
    required this.score,
    required this.text,
  });
}

class _MicroCropRecovery {
  final String? plate;
  final String text;
  final Rect rect;
  final Uint8List bytes;
  final int ocrMs;
  final String signature;
  final bool hasUsefulEvidence;

  const _MicroCropRecovery({
    required this.plate,
    required this.text,
    required this.rect,
    required this.bytes,
    required this.ocrMs,
    required this.signature,
    required this.hasUsefulEvidence,
  });
}

class _DecodedCapture {
  final img.Image image;
  final Size imageSize;
  final bool geometryReliable;
  final bool decodedFits;
  final bool bakedFits;

  const _DecodedCapture({
    required this.image,
    required this.imageSize,
    required this.geometryReliable,
    required this.decodedFits,
    required this.bakedFits,
  });
}

class _CropRecoveryOutcome {
  final String signature;
  final String? plate;
  final String cropText;
  final Rect sourceRegion;
  final Rect cropRegion;
  final Size sourceImageSize;
  final Uint8List cropBytes;
  final Offset focusPoint;
  final int cropOcrMs;
  final int recoveryWallMs;
  final bool allowRefocus;

  const _CropRecoveryOutcome({
    required this.signature,
    required this.plate,
    required this.cropText,
    required this.sourceRegion,
    required this.cropRegion,
    required this.sourceImageSize,
    required this.cropBytes,
    required this.focusPoint,
    required this.cropOcrMs,
    required this.recoveryWallMs,
    this.allowRefocus = true,
  });
}

class LiveOcrPage extends StatefulWidget {
  const LiveOcrPage({
    super.key,
    required this.sessionId,
    required this.coordinator,
    this.onExitPreparing,
  });

  final String sessionId;
  final LiveOcrCoordinator coordinator;
  final LiveOcrExitPreparing? onExitPreparing;

  @override
  State<LiveOcrPage> createState() => _LiveOcrPageState();
}

class _LiveOcrPageState extends State<LiveOcrPage> {
  CameraController? _controller;
  CameraDescription? _cameraDescription;
  ResolutionPreset _activePreset = ResolutionPreset.high;
  late final TextRecognizer _recognizer;

  final OcrLearningRepository _learningRepo = OcrLearningRepository.instance;

  bool _initialized = false;
  bool _autoRunning = false;
  bool _shooting = false;
  bool _torch = false;
  bool _completed = false;
  bool _allowForceInsert = false;
  bool _learningLoaded = false;
  bool _usedLearningMidLast = false;
  bool _usedLearningRankLast = false;
  bool _recoveringCamera = false;
  bool _developerMode = false;

  _OcrDebugStage _ocrDebugStage = _OcrDebugStage.idle;
  List<_OcrDebugLineBox> _ocrDebugLineBoxes = const [];
  Size? _ocrDebugSourceImageSize;
  Rect? _ocrDebugWeakBox;
  Rect? _ocrDebugCropBox;
  Rect? _ocrDebugLocalCropBox;
  Rect? _ocrDebugMidContextBox;
  Rect? _ocrDebugMidLeftBox;
  Rect? _ocrDebugMidGlyphBox;
  Rect? _ocrDebugMidRightBox;
  _PlateRecoverySlot? _ocrDebugLocalSlot;
  Offset? _ocrDebugFocusPoint;
  Uint8List? _ocrDebugCropBytes;
  Uint8List? _ocrDebugSourcePlateBytes;
  Uint8List? _ocrDebugRectifiedPlateBytes;
  Uint8List? _ocrDebugLocalCropBytes;
  Uint8List? _ocrDebugMidContextBytes;
  Uint8List? _ocrDebugMidGlyphBytes;
  _OcrRecoveryPreviewPhase _ocrRecoveryPreviewPhase =
      _OcrRecoveryPreviewPhase.none;
  String? _ocrDebugCropText;
  String? _ocrDebugLocalCropText;
  String? _ocrDebugMidAnchorStatus;
  String? _ocrDebugMidGlyphText;
  String? _ocrDebugMidContextText;
  String? _ocrDebugStructuredPlate;
  String? _ocrDebugRecoveredPlate;
  String? _ocrDebugStageDetail;
  int? _ocrDebugCaptureMs;
  int? _ocrDebugFullOcrMs;
  int? _ocrDebugCropOcrMs;
  int? _ocrDebugLocalOcrMs;
  int? _ocrDebugLocalWallMs;
  int? _ocrDebugRecoveryWallMs;
  int _ocrDebugRevision = 0;
  _PlateQuad? _ocrDebugPerspectiveQuad;
  bool _ocrDebugPerspectiveApplied = false;
  double? _ocrDebugPerspectiveAngle;
  Size? _ocrDebugRectifiedSize;
  String? _ocrDebugPerspectiveText;
  Offset? _tapFocusPoint;
  int _tapFocusRevision = 0;
  String? _pendingRefocusSignature;
  int _pendingRefocusRetryCount = 0;
  DateTime? _lastAutoRefocusAt;
  String? _lastAutoRefocusIdentity;
  Rect? _lastAutoRefocusRegion;
  Size? _lastAutoRefocusImageSize;
  String? _lastRefocusDecision;
  String? _lastSegmentationDecision;
  String? _lastTopologyDecision;
  String? _lastFrameDecision;
  String? _lastCompleteDecision;
  int? _lastLocalStageWallMs;
  String? _lastLocalStageSignature;

  int get _autoIntervalMs => widget.coordinator.profile.autoIntervalMs;
  int _attempt = 0;
  int _autoGen = 0;
  int _captureErrorStreak = 0;
  final int _captureErrorBackoffThreshold = 3;
  final int _captureErrorRecoverThreshold = 5;

  String? _lastText;
  String? _debugText;
  String? _lastFailureReason;
  String? _currentFailureReason;

  List<String> _candidateChips = const [];
  List<_DisplayChip> _displayChips = const [];

  OcrLearningSummary? _learningSummary;
  Map<String, String> _dynMidMap = const {};
  Map<String, String> _dynCandidateMap = const {};
  int? _preferredFrontLen;

  final List<String> _sessionLogs = [];
  final int _maxSessionLogLines = 800;
  String? _lastSavedLearningKey;

  final List<Set<String>> _stableFrames = [];
  final List<Set<String>> _tentativeFrames = [];
  final Map<String, int> _stableVotes = {};
  final Map<String, int> _tentativeVotes = {};
  final List<Set<String>> _weakStructuredFrames = [];
  final List<List<_StructuredWeakCandidate>> _weakStructuredCandidateFrames = [];
  final Map<String, int> _weakStructuredVotes = {};
  final Map<String, Map<String, int>> _weakStructuredObservedHangulVotes = {};
  final Map<String, _StructuredWeakCandidate> _weakStructuredBest = {};
  final List<Map<String, Map<String, double>>> _segmentationEvidenceFrames = [];
  final List<Map<String, Set<String>>> _discriminativeSegmentationFrames = [];
  final Map<String, Map<String, int>> _localMidEvidenceVotes = {};
  final Map<String, int> _lastHeavyRecoveryAttemptBySignature = {};
  final Set<String> _fastRecoveryExecutedIdentities = {};
  final Set<String> _topologyProbeExecutedIdentities = {};
  final Set<String> _fastRecoveryAbandonedIdentities = {};
  final Map<String, int> _fastRecoveryDeferredFrames = {};
  _OcrRecoveryMode _recoveryMode = _OcrRecoveryMode.scanning;
  String? _fastRecoveryIdentity;
  _StructuredWeakCandidate? _fastRecoveryCandidateSnapshot;
  int get _voteWindow => widget.coordinator.profile.voteWindow;
  static const int _stableVoteThreshold = 2;
  static const int _tentativeVoteThreshold = 2;
  int get _weakStructuredVoteThreshold =>
      widget.coordinator.profile.weakStructuredVoteThreshold;
  static const int _fastRecoveryDeferredFrameLimit = 2;
  static const int _refocusRetryLimit = 1;
  static const int _refocusRetryIntervalMs = 260;
  static const int _refocusCooldownMs = 10000;
  int get _heavyRecoveryCooldownFrames =>
      widget.coordinator.profile.heavyRecoveryCooldownFrames;
  static const double _refocusMajorCenterShift = .18;
  static const double _refocusMajorScaleRatio = 1.55;

  static const double _chipBottomSpacer = 24;
  Duration get _developerRecoveredHold => Duration(
        milliseconds: widget.coordinator.profile.developerRecoveredHoldMs,
      );
  Size? _previewSizeLogical;
  Uint8List? _pendingInitialFrameBytes;

  static const Map<String, String> _charMap = {
    'O': '0',
    'o': '0',
    '○': '0',
    'I': '1',
    'l': '1',
    'í': '1',
    'B': '8',
    'S': '5',
    '０': '0',
    '１': '1',
    '２': '2',
    '３': '3',
    '４': '4',
    '５': '5',
    '６': '6',
    '７': '7',
    '８': '8',
    '９': '9',
  };

  static const Map<String, List<String>> _genericWeakMidHints = {
    '': ['러', '부', '누', '육', '조', '허', '어', '저', '머', '버'],
    '4': ['러', '부', '누', '무', '버', '허'],
    '1': ['러', '어', '허', '누', '저'],
    '0': ['오', '어', '우', '조', '호', '아'],
    'O': ['오', '어', '우', '조', '호', '아'],
    '○': ['오', '어', '우', '조', '호', '아'],
    '2': ['육', '조', '저', '자', '누'],
    '유': ['육'],
    '5': ['사', '조', '저', '허'],
    '8': ['버', '부', '머', '배', '바'],
    'B': ['버', '부', '머', '배', '바'],
    '6': ['오', '우', '조', '호'],
    '9': ['오', '우', '조', '호'],
    '7': ['저', '주', '허'],
    '3': ['머', '버', '보'],
    'H': ['허', '부', '버', '머'],
    '#': ['부', '버', '머'],
    '25': ['조', '저', '자'],
    '52': ['조', '사'],
  };

  static const String _plateSepPattern = r'[\s\.\-·•_]*';

  @override
  void initState() {
    super.initState();
    _recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    _pendingInitialFrameBytes = widget.coordinator.initialFrameBytes;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    widget.coordinator.reset();
    _developerMode = await DevAuth.isDeveloperLoggedIn();
    _appendLog('개발자 모드 ${_developerMode ? 'ON' : 'OFF'} profile=${widget.coordinator.profile.name}');
    if (mounted) {
      setState(() {});
    }
    await _loadLearningPolicy();
    await _initCamera();
  }

  Future<void> _loadLearningPolicy() async {
    try {
      _dynMidMap = await _learningRepo.loadDynamicMidMap();
      _dynCandidateMap = await _learningRepo.loadDynamicCandidateMap();
      _preferredFrontLen = await _learningRepo.getPreferredFrontLen();
      _learningSummary = await _learningRepo.getSummary();
      _appendLog(
        '학습 정책 로드 committed=${_learningSummary?.committedCount ?? 0} '
            'pending=${_learningSummary?.pendingCount ?? 0} '
            'midMap=${_dynMidMap.length} candidateMap=${_dynCandidateMap.length} '
            'preferredFrontLen=${_preferredFrontLen ?? '-'}',
      );
    } catch (e) {
      if (kDebugMode && mounted) {
        setState(() => _debugText = 'learning load err: $e');
      }
      _appendLog('학습 정책 로드 오류 $e');
    } finally {
      if (mounted) {
        setState(() => _learningLoaded = true);
      }
    }
  }

  @override
  void dispose() {
    _autoRunning = false;
    _autoGen++;
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _appendLog('카메라 권한 거부');
        if (!mounted) return;
        await _finishAndPop(exitType: LiveOcrExitType.permissionDenied);
        return;
      }

      final cameras = await availableCameras();
      final back = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraDescription = back;

      await _initializeControllerWithFallback(back);

      unawaited(_meterTo(const Offset(0.5, 0.5)));

      _initialized = true;
      if (mounted) {
        setState(() {});
      }

      _startAuto(resetSession: true);
    } catch (e) {
      _appendLog('카메라 초기화 오류 $e');
      if (!mounted) return;
      await _finishAndPop(exitType: LiveOcrExitType.cameraInitFailed);
    }
  }

  Future<void> _initializeControllerWithFallback(
      CameraDescription camera) async {
    CameraController? controller;
    try {
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _activePreset = ResolutionPreset.high;
    } catch (_) {
      await controller?.dispose();
      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _activePreset = ResolutionPreset.medium;
    }

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}

    _controller = controller;
    _appendLog('카메라 초기화 preset=${_activePreset.toString().split('.').last}');
  }

  Future<void> _recoverCameraAfterCaptureFailure() async {
    if (_recoveringCamera || _cameraDescription == null) return;
    _recoveringCamera = true;
    _appendLog('카메라 복구 시작 streak=$_captureErrorStreak');
    try {
      final old = _controller;
      _controller = null;
      await old?.dispose();
      await Future.delayed(const Duration(milliseconds: 400));
      await _initializeControllerWithFallback(_cameraDescription!);
      _captureErrorStreak = 0;
      _pendingRefocusSignature = null;
      _pendingRefocusRetryCount = 0;
      _lastAutoRefocusAt = null;
      _lastAutoRefocusIdentity = null;
      _lastAutoRefocusRegion = null;
      _lastAutoRefocusImageSize = null;
      _lastRefocusDecision = null;
      _lastSegmentationDecision = null;
      _lastTopologyDecision = null;
      _lastFrameDecision = null;
      _lastCompleteDecision = null;
      _lastLocalStageWallMs = null;
      _lastLocalStageSignature = null;
      _appendLog('카메라 복구 성공');
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _appendLog('카메라 복구 실패 $e');
      if (mounted && kDebugMode) {
        setState(() => _debugText = 'camera recover err: $e');
      }
    } finally {
      _recoveringCamera = false;
    }
  }

  Future<void> _meterTo(Offset p) async {
    try {
      await _controller?.setExposurePoint(p);
      await _controller?.setFocusPoint(p);
      _appendLog(
        '측광/포커스 이동 dx=${p.dx.toStringAsFixed(2)} dy=${p.dy.toStringAsFixed(2)}',
      );
    } catch (_) {}
  }

  void _startAuto({required bool resetSession}) {
    if (!_initialized) return;
    _autoRunning = true;
    _shooting = false;

    if (resetSession) {
      _attempt = 0;
      _completed = false;
      _captureErrorStreak = 0;
      _candidateChips = const [];
      _displayChips = const [];
      _lastText = null;
      _debugText = null;
      _lastFailureReason = null;
      _currentFailureReason = null;
      _usedLearningMidLast = false;
      _usedLearningRankLast = false;
      _stableFrames.clear();
      _tentativeFrames.clear();
      _stableVotes.clear();
      _tentativeVotes.clear();
      _weakStructuredFrames.clear();
      _weakStructuredCandidateFrames.clear();
      _weakStructuredVotes.clear();
      _weakStructuredObservedHangulVotes.clear();
      _weakStructuredBest.clear();
      _segmentationEvidenceFrames.clear();
      _discriminativeSegmentationFrames.clear();
      _localMidEvidenceVotes.clear();
      _lastHeavyRecoveryAttemptBySignature.clear();
      _fastRecoveryExecutedIdentities.clear();
      _topologyProbeExecutedIdentities.clear();
      _fastRecoveryAbandonedIdentities.clear();
      _fastRecoveryDeferredFrames.clear();
      _recoveryMode = _OcrRecoveryMode.scanning;
      _fastRecoveryIdentity = null;
      _fastRecoveryCandidateSnapshot = null;
      _sessionLogs.clear();
      widget.coordinator.reset();
      _lastSavedLearningKey = null;
      _ocrDebugStage = _OcrDebugStage.idle;
      _ocrDebugLineBoxes = const [];
      _ocrDebugSourceImageSize = null;
      _ocrDebugWeakBox = null;
      _ocrDebugCropBox = null;
      _ocrDebugLocalCropBox = null;
      _ocrDebugMidContextBox = null;
      _ocrDebugMidLeftBox = null;
      _ocrDebugMidGlyphBox = null;
      _ocrDebugMidRightBox = null;
      _ocrDebugLocalSlot = null;
      _ocrDebugFocusPoint = null;
      _ocrDebugCropBytes = null;
      _ocrDebugSourcePlateBytes = null;
      _ocrDebugRectifiedPlateBytes = null;
      _ocrDebugLocalCropBytes = null;
      _ocrDebugMidContextBytes = null;
      _ocrDebugMidGlyphBytes = null;
      _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.none;
      _ocrDebugCropText = null;
      _ocrDebugLocalCropText = null;
      _ocrDebugMidAnchorStatus = null;
      _ocrDebugMidGlyphText = null;
      _ocrDebugMidContextText = null;
      _ocrDebugStructuredPlate = null;
      _ocrDebugRecoveredPlate = null;
      _ocrDebugStageDetail = null;
      _ocrDebugCaptureMs = null;
      _ocrDebugFullOcrMs = null;
      _ocrDebugCropOcrMs = null;
      _ocrDebugLocalOcrMs = null;
      _ocrDebugLocalWallMs = null;
      _ocrDebugRecoveryWallMs = null;
      _ocrDebugPerspectiveQuad = null;
      _ocrDebugPerspectiveApplied = false;
      _ocrDebugPerspectiveAngle = null;
      _ocrDebugRectifiedSize = null;
      _ocrDebugPerspectiveText = null;
      _ocrDebugRevision = 0;
      _pendingRefocusSignature = null;
      _pendingRefocusRetryCount = 0;
      _lastAutoRefocusAt = null;
      _lastAutoRefocusIdentity = null;
      _lastAutoRefocusRegion = null;
      _lastAutoRefocusImageSize = null;
      _lastRefocusDecision = null;
      _lastSegmentationDecision = null;
      _lastTopologyDecision = null;
      _lastFrameDecision = null;
      _lastCompleteDecision = null;
      _lastLocalStageWallMs = null;
      _lastLocalStageSignature = null;
    }

    _autoGen++;
    final gen = _autoGen;
    _appendLog(
      '인식 시작 gen=$gen profile=${widget.coordinator.profile.name} intervalMs=$_autoIntervalMs '
          'forceInsert=${_allowForceInsert ? 'on' : 'off'} torch=${_torch ? 'on' : 'off'}',
    );
    _autoLoop(gen);
  }

  void _stopAuto() {
    _autoRunning = false;
    _autoGen++;
    _pendingRefocusSignature = null;
    _pendingRefocusRetryCount = 0;
    _lastAutoRefocusAt = null;
    _lastAutoRefocusIdentity = null;
    _lastAutoRefocusRegion = null;
    _lastAutoRefocusImageSize = null;
    _lastRefocusDecision = null;
    _lastLocalStageWallMs = null;
    _lastLocalStageSignature = null;
    _appendLog('인식 중지');
  }

  Future<void> _autoLoop(int gen) async {
    while (mounted && _autoRunning && !_completed && gen == _autoGen) {
      if (_recoveringCamera) {
        await Future.delayed(const Duration(milliseconds: 120));
        continue;
      }
      if (_shooting) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      final cam = _controller;
      if (cam == null || !cam.value.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 120));
        continue;
      }

      _shooting = true;
      String? capturedPath;
      bool usedLearningMidThis = false;
      bool usedLearningRankThis = false;
      bool fastRefocusRetryRequested = false;
      bool captureNextImmediately = false;
      bool allowHeavyRecoveryThisFrame = true;
      bool completeDeferredThisFrame = false;
      String? suppressedWeakSignature;
      _DecodedCapture? decodedCapture;

      try {
        _setOcrDebugStage(
          _OcrDebugStage.capturing,
          detail: 'capture',
          clearFrameGeometry: true,
        );

        final captureWatch = Stopwatch()..start();
        final initialBytes = _pendingInitialFrameBytes;
        if (initialBytes != null && initialBytes.isNotEmpty) {
          _pendingInitialFrameBytes = null;
          final safeSession = widget.sessionId.replaceAll(
            RegExp(r'[^A-Za-z0-9_-]'),
            '_',
          );
          final initialFile = File(
            '${Directory.systemTemp.path}/live_ocr_initial_$safeSession.jpg',
          );
          await initialFile.writeAsBytes(initialBytes, flush: true);
          capturedPath = initialFile.path;
          _appendLog('초기 전달 프레임 사용 bytes=${initialBytes.length}');
        } else {
          final captured = await cam.takePicture();
          capturedPath = captured.path;
        }
        captureWatch.stop();
        _captureErrorStreak = 0;
        _ocrDebugCaptureMs = captureWatch.elapsedMilliseconds;

        final input = InputImage.fromFilePath(capturedPath);
        final ocrWatch = Stopwatch()..start();
        final result = await _recognizer.processImage(input);
        ocrWatch.stop();
        final allText = result.text;
        _attempt++;
        _ocrDebugFullOcrMs = ocrWatch.elapsedMilliseconds;
        _setOcrDebugStage(
          _OcrDebugStage.fullOcr,
          detail: 'read',
        );

        if (_developerMode ||
            widget.coordinator.profile.decodeGeometryEveryFrame) {
          decodedCapture = await _decodeCaptureForGeometry(
            capturedPath,
            result,
          );
          _setRawOcrDebugGeometry(
            result: result,
            sourceImageSize: decodedCapture?.imageSize,
          );
        }

        _lastText = allText.replaceAll('\n', ' ');
        if ((_lastText ?? '').length > 180) {
          _lastText = '${_lastText!.substring(0, 180)}…';
        }
        _appendLog(
          'attempt=$_attempt captureMs=${captureWatch.elapsedMilliseconds} '
              'fullOcrMs=${ocrWatch.elapsedMilliseconds} ocrText=${_lastText ?? ''}',
        );

        final direct = _extractStrictKoreanPlate(allText);
        if (direct != null) {
          _usedLearningMidLast = false;
          _usedLearningRankLast = false;
          _appendLog('직접 후보 $direct');
          final action = await _handleCompleteCandidate(
            plate: direct,
            source: LiveOcrCompleteSource.strict,
            exitType: LiveOcrExitType.autoDirect,
            detail: 'strict:$direct',
            geometryReliable: decodedCapture?.geometryReliable,
          );
          if (action == LiveOcrCompleteAction.accept) {
            return;
          }
          completeDeferredThisFrame =
              action == LiveOcrCompleteAction.defer;
        } else {
          final loose = _extractLooseKoreanPlate(
            allText,
            onUseLearningMid: () {
              usedLearningMidThis = true;
            },
          );
          if (loose != null) {
            _usedLearningMidLast = usedLearningMidThis;
            _usedLearningRankLast = false;
            _appendLog('완화 후보 $loose');
            final action = await _handleCompleteCandidate(
              plate: loose,
              source: LiveOcrCompleteSource.loose,
              exitType: LiveOcrExitType.autoLoose,
              detail: 'loose:$loose',
              geometryReliable: decodedCapture?.geometryReliable,
            );
            if (action == LiveOcrCompleteAction.accept) {
              return;
            }
            completeDeferredThisFrame =
                action == LiveOcrCompleteAction.defer;
          }
        }

        final structuredWeakFrame =
            _augmentStructuredWeakCandidatesWithPersistentIdentity(
          result,
          _extractStructuredWeakCandidates(result),
        );
        _observeSegmentationEvidence(structuredWeakFrame);
        _pushWeakStructuredCandidateFrame(structuredWeakFrame);
        final midRecoveryCandidates = _rankStructuredWeakCandidates(
          structuredWeakFrame,
        );
        final partialSeedsForFrame = midRecoveryCandidates.isEmpty
            ? _extractPartialBoundarySeeds(
                result,
                onUseLearningMid: () {
                  usedLearningMidThis = true;
                },
              )
            : const <_PartialBoundarySeed>[];
        final trackingRegion = midRecoveryCandidates.isEmpty
            ? null
            : _findWeakPlateRegion(result, midRecoveryCandidates);
        final trackingSize = decodedCapture?.imageSize;
        double? trackingAreaRatio;
        var leftClipped = false;
        var rightClipped = false;
        var topClipped = false;
        var bottomClipped = false;
        if (trackingRegion != null &&
            trackingSize != null &&
            trackingSize.width > 0 &&
            trackingSize.height > 0) {
          final imageArea = trackingSize.width * trackingSize.height;
          trackingAreaRatio = imageArea <= 0
              ? null
              : (trackingRegion.box.width * trackingRegion.box.height) /
                  imageArea;
          final marginX = math.max(4.0, trackingSize.width * .025).toDouble();
          final marginY = math.max(4.0, trackingSize.height * .025).toDouble();
          leftClipped = trackingRegion.box.left <= marginX;
          rightClipped = trackingRegion.box.right >= trackingSize.width - marginX;
          topClipped = trackingRegion.box.top <= marginY;
          bottomClipped =
              trackingRegion.box.bottom >= trackingSize.height - marginY;
        }
        final frameDecision = widget.coordinator.observeFrame(
          LiveOcrFrameObservation(
            attempt: _attempt,
            ocrText: _lastText ?? '',
            geometryReliable: decodedCapture?.geometryReliable,
            structured: structuredWeakFrame
                .map(
                  (candidate) => LiveOcrStructuredObservation(
                    signature: candidate.signature,
                    front: candidate.front,
                    back: candidate.back,
                    observedToken: candidate.observedToken,
                    rawValue: candidate.rawValue,
                    frontLen: candidate.frontLen,
                    score: candidate.score,
                  ),
                )
                .toList(growable: false),
            partial: partialSeedsForFrame
                .map(
                  (seed) => LiveOcrPartialObservation(
                    front: seed.front,
                    mid: seed.mid,
                    back: seed.back,
                    frontLen: seed.frontLen,
                    score: seed.score,
                  ),
                )
                .toList(growable: false),
            capturedAt: DateTime.now(),
            plateAreaRatio: trackingAreaRatio,
            leftClipped: leftClipped,
            rightClipped: rightClipped,
            topClipped: topClipped,
            bottomClipped: bottomClipped,
          ),
        );
        allowHeavyRecoveryThisFrame = frameDecision.allowHeavyRecovery;
        captureNextImmediately = frameDecision.captureNextImmediately;
        _lastFrameDecision =
            'heavy=${frameDecision.allowHeavyRecovery} '
            'nextImmediate=${frameDecision.captureNextImmediately} '
            'reason=${frameDecision.reason} '
            'identity=${frameDecision.preferredIdentity ?? '-'} '
            'quality=${frameDecision.frameQuality?.toStringAsFixed(2) ?? '-'}';
        if (completeDeferredThisFrame) {
          allowHeavyRecoveryThisFrame = false;
          captureNextImmediately = true;
        }

        if (widget.coordinator.profile.name.startsWith('sensor')) {
          _appendLog(
            'sensor track ${widget.coordinator.debugStatus} '
            'area=${trackingAreaRatio?.toStringAsFixed(4) ?? '-'} '
            'clip=${leftClipped ? 'L' : ''}${rightClipped ? 'R' : ''}${topClipped ? 'T' : ''}${bottomClipped ? 'B' : ''}',
          );
        }
        final fusedPlate = widget.coordinator.fusedCompletePlate;
        if (fusedPlate != null &&
            _isModernPlate(_normalizeCandidateKey(fusedPlate))) {
          final recoveredPlate = _normalizeCandidateKey(fusedPlate);
          _usedLearningMidLast = usedLearningMidThis;
          _usedLearningRankLast = true;
          _appendLog(
            'sensor multi-frame fusion candidate plate=$recoveredPlate ${widget.coordinator.debugStatus}',
          );
          final action = await _handleCompleteCandidate(
            plate: recoveredPlate,
            source: LiveOcrCompleteSource.multiFrameFusion,
            exitType: LiveOcrExitType.autoLoose,
            detail: 'sensorFusion:$recoveredPlate',
            geometryReliable: decodedCapture?.geometryReliable,
          );
          if (action == LiveOcrCompleteAction.accept) {
            return;
          }
        }
        if (completeDeferredThisFrame) {
          _appendLog(
            'complete temporal pending attempt=$_attempt '
            'decision=${_lastCompleteDecision ?? '-'} '
            'nextFrame=immediate',
          );
          if (await _finishWhenProfileAttemptLimitReached()) {
            return;
          }
          continue;
        }
        if (midRecoveryCandidates.isEmpty) {
          _lastSegmentationDecision = null;
          _lastTopologyDecision = null;
        }

        if (midRecoveryCandidates.isEmpty &&
            (_recoveryMode != _OcrRecoveryMode.candidateReady ||
                widget.coordinator.profile.repeatRecoveryAcrossFrames)) {
          final partialSeeds = partialSeedsForFrame;
          if (partialSeeds.isNotEmpty) {
            final partialSignature = partialSeeds.first.signature;
            _CropRecoveryOutcome? partialOutcome;
            if (allowHeavyRecoveryThisFrame &&
                _canRunHeavyRecovery(partialSignature)) {
              partialOutcome = await _tryRecoverPartialBoundaryCases(
                capturedPath: capturedPath,
                result: result,
                seeds: partialSeeds,
                decodedCapture: decodedCapture,
                onUseLearningMid: () {
                  usedLearningMidThis = true;
                },
              );
            } else {
              final reason = !allowHeavyRecoveryThisFrame
                  ? 'framePolicy:${_lastFrameDecision ?? '-'}'
                  : 'heavyRecoveryCooldown:${_heavyRecoveryCooldownRemainingFrames(partialSignature)}';
              _appendLog(
                'partial recovery skip signature=$partialSignature '
                'reason=$reason',
              );
            }
            if (partialOutcome?.plate != null &&
                _isModernPlate(_normalizeCandidateKey(partialOutcome!.plate!))) {
              final recoveredPlate = _normalizeCandidateKey(partialOutcome.plate!);
              _pendingRefocusSignature = null;
              _pendingRefocusRetryCount = 0;
              _usedLearningMidLast = usedLearningMidThis;
              _usedLearningRankLast = false;
              _appendLog(
                'partial local 복구 후보 plate=$recoveredPlate '
                'ocrMs=${partialOutcome.cropOcrMs} '
                'text=${partialOutcome.cropText.replaceAll('\n', ' ')}',
              );
              final action = await _handleCompleteCandidate(
                plate: recoveredPlate,
                source: LiveOcrCompleteSource.partialRecovery,
                exitType: LiveOcrExitType.autoLoose,
                detail: 'partialLocalRecovered:$recoveredPlate',
                geometryReliable: decodedCapture?.geometryReliable,
              );
              if (action == LiveOcrCompleteAction.accept) {
                return;
              }
              if (action == LiveOcrCompleteAction.defer) {
                captureNextImmediately = true;
                if (await _finishWhenProfileAttemptLimitReached()) {
                  return;
                }
                continue;
              }
            }
          }
        }

        if (midRecoveryCandidates.isEmpty &&
            _pendingRefocusSignature != null) {
          _appendLog(
            '재초점 대기 해제 signature=$_pendingRefocusSignature reason=unresolvedCandidateGone',
          );
          _pendingRefocusSignature = null;
          _pendingRefocusRetryCount = 0;
        }

        if (midRecoveryCandidates.isNotEmpty) {
          final primaryCandidate = midRecoveryCandidates.first;
          final primarySignature = primaryCandidate.signature;
          final exactEvidence = _exactWeakEvidenceIncludingCurrent(
            primarySignature,
            structuredWeakFrame,
          );
          final resolvedFront = _resolveFrontFromEvidence(
            primaryCandidate.back,
            structuredWeakFrame,
          );
          final segmentationResolved =
              _isFastRecoverySegmentationResolved(
            primaryCandidate,
            structuredWeakFrame,
          );
          final segmentationScores = _segmentationScoreSummary(
            primaryCandidate.back,
            structuredWeakFrame,
          );
          final discriminativeFronts = _segmentationDiscriminativeSummary(
            primaryCandidate.back,
            structuredWeakFrame,
          );
          final segmentationEvidenceMode = _segmentationEvidenceMode(
            primaryCandidate.back,
            structuredWeakFrame,
          );
          _lastSegmentationDecision =
              'signature=$primarySignature exact=$exactEvidence/'
              '$_weakStructuredVoteThreshold resolved=${resolvedFront ?? '-'} '
              'scores=$segmentationScores discriminative=$discriminativeFronts '
              'evidenceMode=$segmentationEvidenceMode';
          final fastRecoveryEligible =
              exactEvidence >= _weakStructuredVoteThreshold &&
                  segmentationResolved;
          final topologyDecision = !fastRecoveryEligible &&
                  exactEvidence >= _weakStructuredVoteThreshold &&
                  segmentationEvidenceMode == 'numeric_only'
              ? _selectTopologyProbeDecision(structuredWeakFrame)
              : null;
          _CropRecoveryOutcome? outcome;
          var topologyProbeAttempted = false;
          if (fastRecoveryEligible) {
            _fastRecoveryCandidateSnapshot = primaryCandidate;
            _lastTopologyDecision = null;
          }

          if (!fastRecoveryEligible) {
            if (topologyDecision != null) {
              _lastTopologyDecision =
                  'selected=${topologyDecision.selected.signature} '
                  'probeEligible=${topologyDecision.probeEligible} '
                  'reason=${topologyDecision.reason} '
                  'observations=${topologyDecision.observations} '
                  'ranking=${topologyDecision.ranking}';
              _appendLog(
                'topology alternatives=${_joinForLog(topologyDecision.alternatives.map((e) => e.signature).toList())} '
                'observations=${topologyDecision.observations} '
                'ranking=${topologyDecision.ranking} '
                'selected=${topologyDecision.selected.signature} '
                'probeEligible=${topologyDecision.probeEligible} '
                'reason=${topologyDecision.reason}',
              );
              if (topologyDecision.probeEligible &&
                  (widget.coordinator.profile.repeatRecoveryAcrossFrames ||
                      !_topologyProbeExecutedIdentities
                          .contains(topologyDecision.selected.signature))) {
                _fastRecoveryCandidateSnapshot = topologyDecision.selected;
                _setRecoveryMode(
                  _OcrRecoveryMode.fastMidRecovery,
                  identity: topologyDecision.selected.signature,
                );
                if (allowHeavyRecoveryThisFrame &&
                    _canRunHeavyRecovery(
                      topologyDecision.selected.signature,
                    )) {
                  topologyProbeAttempted = true;
                  _topologyProbeExecutedIdentities
                      .add(topologyDecision.selected.signature);
                  _appendLog(
                    'topology probe start signature=${topologyDecision.selected.signature} '
                    'observations=${topologyDecision.observations}',
                  );
                  outcome = await _tryRecoverFromDynamicCrop(
                    capturedPath: capturedPath,
                    result: result,
                    weakCandidates: [topologyDecision.selected],
                    decodedCapture: decodedCapture,
                    onUseLearningMid: () {
                      usedLearningMidThis = true;
                    },
                    fastMidOnly: true,
                  );
                } else {
                  final reason = !allowHeavyRecoveryThisFrame
                      ? 'framePolicy:${_lastFrameDecision ?? '-'}'
                      : 'heavyRecoveryCooldown:${_heavyRecoveryCooldownRemainingFrames(topologyDecision.selected.signature)}';
                  _appendLog(
                    'topology probe skip signature=${topologyDecision.selected.signature} '
                    'reason=$reason',
                  );
                }
              } else {
                _setRecoveryMode(_OcrRecoveryMode.scanning);
              }
            } else {
              _lastTopologyDecision = null;
              _setRecoveryMode(_OcrRecoveryMode.scanning);
              _appendLog(
                'fast mid recovery wait signature=$primarySignature '
                'exact=$exactEvidence/$_weakStructuredVoteThreshold '
                'segmentationResolved=$segmentationResolved '
                'resolvedFront=${resolvedFront ?? '-'} '
                'scores=$segmentationScores '
                'discriminative=$discriminativeFronts '
                'evidenceMode=$segmentationEvidenceMode',
              );
            }
          } else if (_isFastRecoveryClosed(primarySignature)) {
            _setRecoveryMode(
              _OcrRecoveryMode.candidateReady,
              identity: primarySignature,
            );
            _appendLog(
              'fast mid recovery closed signature=$primarySignature '
              'executed=${_hasFastRecoveryExecuted(primarySignature)} '
              'abandoned=${_hasFastRecoveryAbandoned(primarySignature)} '
              'evidence=$exactEvidence',
            );
          } else {
            _setRecoveryMode(
              _OcrRecoveryMode.fastMidRecovery,
              identity: primarySignature,
            );
            if (allowHeavyRecoveryThisFrame &&
                _canRunHeavyRecovery(primarySignature)) {
              outcome = await _tryRecoverFromDynamicCrop(
                capturedPath: capturedPath,
                result: result,
                weakCandidates: midRecoveryCandidates,
                decodedCapture: decodedCapture,
                onUseLearningMid: () {
                  usedLearningMidThis = true;
                },
                fastMidOnly: true,
              );
              if (outcome == null &&
                  !_hasFastRecoveryExecuted(primarySignature)) {
                final deferred =
                    _recordFastRecoveryDeferredFrame(primarySignature);
                _appendLog(
                  'fast mid recovery deferred signature=$primarySignature '
                  'count=$deferred/$_fastRecoveryDeferredFrameLimit',
                );
                if (deferred >= _fastRecoveryDeferredFrameLimit) {
                  _fastRecoveryAbandonedIdentities.add(primarySignature);
                  _setRecoveryMode(
                    _OcrRecoveryMode.candidateReady,
                    identity: primarySignature,
                  );
                  _appendLog(
                    'fast mid recovery timebox exhausted '
                    'signature=$primarySignature fallback=candidateReady',
                  );
                }
              }
            } else {
              final reason = !allowHeavyRecoveryThisFrame
                  ? 'framePolicy:${_lastFrameDecision ?? '-'}'
                  : 'heavyRecoveryCooldown:${_heavyRecoveryCooldownRemainingFrames(primarySignature)}';
              _appendLog(
                'dynamic recovery skip signature=$primarySignature '
                'reason=$reason',
              );
            }
          }

          if (outcome != null) {
            if (outcome.plate != null &&
                _isModernPlate(_normalizeCandidateKey(outcome.plate!))) {
              final recoveredPlate = _normalizeCandidateKey(outcome.plate!);
              _pendingRefocusSignature = null;
              _pendingRefocusRetryCount = 0;
              _usedLearningMidLast = usedLearningMidThis;
              _usedLearningRankLast = false;
              final recoveryKind =
                  _ocrDebugLocalCropText == null ? 'dynamic' : 'local';
              _appendLog(
                '복구 후보 kind=$recoveryKind plate=$recoveredPlate '
                'ocrMs=${outcome.cropOcrMs} text=${outcome.cropText.replaceAll('\n', ' ')}',
              );
              final action = await _handleCompleteCandidate(
                plate: recoveredPlate,
                source: LiveOcrCompleteSource.dynamicRecovery,
                exitType: LiveOcrExitType.autoLoose,
                detail: '${recoveryKind}Recovered:$recoveredPlate',
                geometryReliable: decodedCapture?.geometryReliable,
              );
              if (action == LiveOcrCompleteAction.accept) {
                return;
              }
              if (action == LiveOcrCompleteAction.defer) {
                captureNextImmediately = true;
                if (await _finishWhenProfileAttemptLimitReached()) {
                  return;
                }
                continue;
              }
            }

            _setRecoveryMode(
              _OcrRecoveryMode.candidateReady,
              identity: outcome.signature,
            );
            final samePendingSignature =
                _pendingRefocusSignature == outcome.signature;
            final retryConsumed = samePendingSignature &&
                _pendingRefocusRetryCount >= _refocusRetryLimit;

            if (!widget.coordinator.profile.enableAutoRefocus ||
                !outcome.allowRefocus) {
              final suppressionReason =
                  !widget.coordinator.profile.enableAutoRefocus
                      ? 'profileDisabled'
                      : (_recoveryMode == _OcrRecoveryMode.candidateReady
                          ? 'fastRecoveryBudgetConsumed'
                          : 'midOnlyStableDigits');
              _lastRefocusDecision = 'suppressed:$suppressionReason';
              _pendingRefocusSignature = null;
              _pendingRefocusRetryCount = 0;
              _appendLog(
                '재초점 억제 signature=${outcome.signature} '
                'reason=$suppressionReason wallMs=${outcome.recoveryWallMs}',
              );
            } else if (!retryConsumed) {
              final refocusDecision = _evaluateAutoRefocus(outcome);
              if (refocusDecision.allow) {
                if (!samePendingSignature) {
                  _pendingRefocusSignature = outcome.signature;
                  _pendingRefocusRetryCount = 0;
                }
                _pendingRefocusRetryCount++;
                suppressedWeakSignature = outcome.signature;
                fastRefocusRetryRequested = true;
                _lastRefocusDecision = 'allowed:${refocusDecision.reason}';
                _setOcrDebugStage(
                  _OcrDebugStage.refocusing,
                  detail:
                  'retry=$_pendingRefocusRetryCount/$_refocusRetryLimit ${refocusDecision.reason} focus:${outcome.focusPoint.dx.toStringAsFixed(3)},${outcome.focusPoint.dy.toStringAsFixed(3)}',
                  structuredPlate: outcome.signature,
                  focusPoint: outcome.focusPoint,
                );
                await _meterTo(outcome.focusPoint);
                _recordAutoRefocus(outcome, refocusDecision.reason);
                await _developerDebugBeat(
                  const Duration(milliseconds: 220),
                );
                _appendLog(
                  '동적 crop 복구 실패 focus 재지정 '
                      'signature=${outcome.signature} '
                      'retry=$_pendingRefocusRetryCount/$_refocusRetryLimit '
                      'reason=${refocusDecision.reason} '
                      'cropOcrMs=${outcome.cropOcrMs} cropText=${outcome.cropText.replaceAll('\n', ' ')} '
                      'weakChip=suppressed',
                );
              } else {
                _lastRefocusDecision = 'suppressed:${refocusDecision.reason}';
                _pendingRefocusSignature = null;
                _pendingRefocusRetryCount = 0;
                _appendLog(
                  '재초점 cooldown 억제 signature=${outcome.signature} '
                      'reason=${refocusDecision.reason} '
                      'sourceBox=${_rectForLog(outcome.sourceRegion)}',
                );
              }
            } else {
              _appendLog(
                '재초점 자동 재시도 소진 signature=${outcome.signature} '
                    'retry=$_pendingRefocusRetryCount/$_refocusRetryLimit fallback=allowed',
              );
              _pendingRefocusSignature = null;
              _pendingRefocusRetryCount = 0;
            }
          } else if (_pendingRefocusSignature != null &&
              midRecoveryCandidates.any(
                    (candidate) =>
                candidate.signature == _pendingRefocusSignature,
              )) {
            _appendLog(
              '재초점 자동 재시도 결과 없음 signature=$_pendingRefocusSignature fallback=allowed',
            );
            _pendingRefocusSignature = null;
            _pendingRefocusRetryCount = 0;
          }

          if (topologyDecision != null && !fastRecoveryEligible) {
            final resultLabel = outcome?.plate != null
                ? 'success'
                : (topologyProbeAttempted ? 'failed' : 'not_run');
            _appendLog(
              'topology probe result=$resultLabel '
              'selected=${topologyDecision.selected.signature} '
              'autoSelectIncomplete=${outcome?.plate == null}',
            );
            if (outcome?.plate == null) {
              if (widget.coordinator.profile.autoSelectIncomplete) {
                _usedLearningMidLast = usedLearningMidThis;
                _usedLearningRankLast = true;
                await _finishAutoStructuredSelection(
                  front: topologyDecision.selected.front,
                  back: topologyDecision.selected.back,
                  observedValue: topologyDecision.selected.rawValue,
                  suggestions:
                      _inferWeakMidSuggestions(topologyDecision.selected),
                  alternatives: topologyDecision.alternatives
                      .map((e) => e.signature)
                      .toList(growable: false),
                  reason: topologyProbeAttempted
                      ? 'topologyProbeFailed'
                      : 'topologyRankedNoProbe',
                );
                return;
              }
              _setRecoveryMode(_OcrRecoveryMode.scanning);
              _appendLog(
                'structured incomplete deferred profile=${widget.coordinator.profile.name} '
                'selected=${topologyDecision.selected.signature} reason=${topologyProbeAttempted ? 'topologyProbeFailed' : 'topologyRankedNoProbe'}',
              );
            }
          }
        }

        final rawSet = <String>{};
        rawSet.addAll(
            _extractModernCandidatesAnyChar(allText, onUseLearningMid: () {
              usedLearningMidThis = true;
            }));
        rawSet.addAll(_extractLegacyRegionCandidates(allText));
        rawSet.addAll(_extractDigitsOnlyNoMidCandidates(structuredWeakFrame));
        rawSet.addAll(_extractByGeometryCandidates(result));
        rawSet.addAll(
            _extractWeakRecoverableCandidates(structuredWeakFrame, onUseLearningMid: () {
              usedLearningMidThis = true;
            }));

        final prioritized = _applyLearnedCandidateMap(rawSet);
        if (prioritized.isNotEmpty || _preferredFrontLen != null) {
          usedLearningRankThis = true;
        }

        final stableFrame = <String>{};
        final tentativeFrame = <String>{};
        final weakFrame = <String>{};

        for (final cand in rawSet) {
          final normalized = _normalizeCandidateKey(cand);
          if (_isValidKoreanPlate(normalized)) {
            if (prioritized.contains(normalized)) {
              stableFrame.add(normalized);
            } else if (_isLikelyStableCandidate(normalized)) {
              stableFrame.add(normalized);
            } else {
              tentativeFrame.add(normalized);
            }
            continue;
          }

          final mapped = _dynCandidateMap[normalized];
          if (mapped != null && _isValidKoreanPlate(mapped)) {
            tentativeFrame.add(mapped);
            usedLearningRankThis = true;
            continue;
          }

          if (_looksLikeWeakModernPattern(normalized)) {
            weakFrame.add(normalized);
          }
        }

        _pushObservedWeakMidEvidence(allText, structuredWeakFrame);
        _pushVoteFrame(_stableFrames, _stableVotes, stableFrame);
        _pushVoteFrame(_tentativeFrames, _tentativeVotes, tentativeFrame);
        _pushWeakStructuredFrame(structuredWeakFrame);

        final displayStructuredWeakFrame =
            List<_StructuredWeakCandidate>.from(structuredWeakFrame);
        if (_recoveryMode == _OcrRecoveryMode.candidateReady &&
            _fastRecoveryIdentity != null &&
            !displayStructuredWeakFrame.any(
              (candidate) => _sameStableWeakIdentity(
                _fastRecoveryIdentity!,
                candidate.signature,
              ),
            )) {
          final snapshot = _fastRecoveryCandidateSnapshot;
          if (snapshot != null &&
              _sameStableWeakIdentity(
                _fastRecoveryIdentity!,
                snapshot.signature,
              )) {
            displayStructuredWeakFrame.add(snapshot);
          } else {
            final stored =
                _bestStoredStableWeakCandidate(_fastRecoveryIdentity!);
            if (stored != null) {
              displayStructuredWeakFrame.add(stored);
            }
          }
        }

        var displayChips = _buildDisplayChips(
          stableFrame,
          tentativeFrame,
          weakFrame,
          displayStructuredWeakFrame,
        );
        if (suppressedWeakSignature != null) {
          displayChips = displayChips
              .where(
                (chip) => !_shouldSuppressWeakChip(
              chip,
              suppressedWeakSignature!,
            ),
          )
              .toList(growable: false);
        }
        if (!widget.coordinator.profile.showCandidateChips) {
          displayChips = const <_DisplayChip>[];
        }
        final structuredChoiceChips = displayChips
            .where(
              (chip) =>
                  chip.requiresMidCompletion &&
                  chip.weakFront != null &&
                  chip.weakBack != null,
            )
            .toList(growable: false);
        final ambiguousFronts = structuredChoiceChips
            .map((chip) => chip.weakFront!)
            .toSet();
        final ambiguousBacks = structuredChoiceChips
            .map((chip) => chip.weakBack!)
            .toSet();
        final segmentationChoiceReady = structuredChoiceChips.length >= 2 &&
            ambiguousFronts.length >= 2 &&
            ambiguousBacks.length == 1;
        if (segmentationChoiceReady &&
            widget.coordinator.profile.autoSelectIncomplete) {
          final selected = structuredChoiceChips.first;
          _candidateChips =
              displayChips.map((e) => e.value).toList(growable: false);
          _displayChips = const [];
          _usedLearningMidLast = usedLearningMidThis;
          _usedLearningRankLast = true;
          _lastTopologyDecision =
              'selected=${selected.weakFront}?${selected.weakBack} '
              'probeEligible=false reason=structuredRankingFallback '
              'alternatives=${structuredChoiceChips.map((e) => '${e.weakFront}?${e.weakBack}').join('|')}';
          await _finishAutoStructuredSelection(
            front: selected.weakFront!,
            back: selected.weakBack!,
            observedValue: selected.weakObservedValue ?? selected.value,
            suggestions: selected.weakMidSuggestions,
            alternatives: structuredChoiceChips
                .map((e) => '${e.weakFront}?${e.weakBack}')
                .toList(growable: false),
            reason: 'structuredRankingFallback',
          );
          return;
        }
        if (widget.coordinator.profile.autoSelectIncomplete &&
            _recoveryMode == _OcrRecoveryMode.candidateReady &&
            structuredChoiceChips.isNotEmpty) {
          final selected = structuredChoiceChips.first;
          final alternatives = structuredChoiceChips
              .map((e) => '${e.weakFront}?${e.weakBack}')
              .toList(growable: false);
          _candidateChips =
              displayChips.map((e) => e.value).toList(growable: false);
          _displayChips = const [];
          _usedLearningMidLast = usedLearningMidThis;
          _usedLearningRankLast = usedLearningRankThis;
          final previousTopology = _lastTopologyDecision;
          final topologyPrefix =
              previousTopology == null ? '' : '$previousTopology;';
          _lastTopologyDecision =
              '${topologyPrefix}selected=${selected.weakFront}?${selected.weakBack} '
              'probeEligible=false reason=candidateReadyAutoSelect '
              'alternatives=${alternatives.join('|')}';
          await _finishAutoStructuredSelection(
            front: selected.weakFront!,
            back: selected.weakBack!,
            observedValue: selected.weakObservedValue ?? selected.value,
            suggestions: selected.weakMidSuggestions,
            alternatives: alternatives,
            reason: 'candidateReadyAutoSelect',
          );
          return;
        }
        _candidateChips =
            displayChips.map((e) => e.value).toList(growable: false);
        _displayChips = displayChips;
        _usedLearningMidLast = usedLearningMidThis;
        _usedLearningRankLast = usedLearningRankThis;
        _lastFailureReason = _deriveFailureReason(
          allText: allText,
          stableFrame: stableFrame,
          tentativeFrame: tentativeFrame,
          weakFrame: weakFrame,
        );
        _currentFailureReason = _lastFailureReason;

        if (midRecoveryCandidates.isNotEmpty &&
            suppressedWeakSignature == null) {
          _setOcrDebugStage(
            _OcrDebugStage.fallback,
            detail: midRecoveryCandidates.first.signature,
            structuredPlate: midRecoveryCandidates.first.signature,
          );
        }

        if (mounted) {
          setState(() {});
        }

        _appendLog(
          'rawCandidates=${_joinForLog(_rankAllCandidates(rawSet.toList(), prioritized: prioritized))} '
              'stableFrame=${_joinForLog(stableFrame.toList())} '
              'tentativeFrame=${_joinForLog(tentativeFrame.toList())} '
              'weakFrame=${_joinForLog(weakFrame.toList())} '
              'weakStructured=${_joinForLog(_rankStructuredWeakLogs(structuredWeakFrame))} '
              'display=${_joinForLog(displayChips.map((e) => e.label).toList())} '
              'failure=${_currentFailureReason ?? '-'}',
        );

        if (_allowForceInsert) {
          final force = _extractForceInsertCandidate(allText);
          if (force != null) {
            _appendLog('강제 삽입 후보 $force');
            _usedLearningMidLast = usedLearningMidThis;
            _usedLearningRankLast = usedLearningRankThis;
            final action = await _handleCompleteCandidate(
              plate: force,
              source: LiveOcrCompleteSource.forceInsert,
              exitType: LiveOcrExitType.autoForceInsert,
              detail: 'forceInsert:$force',
              geometryReliable: decodedCapture?.geometryReliable,
            );
            if (action == LiveOcrCompleteAction.accept) {
              return;
            }
          }
        }

        if (await _finishWhenProfileAttemptLimitReached()) {
          return;
        }

        if (kDebugMode && mounted) {
          setState(() => _debugText = 'attempt:$_attempt');
        }
      } catch (e, stackTrace) {
        final msg = e.toString();
        if (e is CameraException || msg.contains('ImageCaptureException')) {
          _captureErrorStreak++;
          _appendLog('autoLoop 오류 $e');
          _appendLog('autoLoop stack=$stackTrace');
          if (_captureErrorStreak >= _captureErrorRecoverThreshold) {
            await _recoverCameraAfterCaptureFailure();
          } else if (_captureErrorStreak >= _captureErrorBackoffThreshold) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } else {
          _appendLog('autoLoop 오류 $e');
          _appendLog('autoLoop stack=$stackTrace');
          if (kDebugMode && mounted) {
            setState(() => _debugText = 'autoLoop err: $e');
          }
        }
      } finally {
        try {
          if (capturedPath != null) {
            final f = File(capturedPath);
            if (f.existsSync()) {
              f.deleteSync();
            }
          }
        } catch (_) {}
        _shooting = false;
      }

      final nextDelayMs = fastRefocusRetryRequested
          ? _refocusRetryIntervalMs
          : captureNextImmediately
              ? 0
              : _autoIntervalMs.clamp(200, 3000).toInt();
      if (nextDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: nextDelayMs));
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  void _setOcrDebugStage(
      _OcrDebugStage stage, {
        String? detail,
        String? structuredPlate,
        String? recoveredPlate,
        Offset? focusPoint,
        bool clearFrameGeometry = false,
      }) {
    if (clearFrameGeometry) {
      _ocrDebugLineBoxes = const [];
      _ocrDebugSourceImageSize = null;
      _ocrDebugWeakBox = null;
      _ocrDebugCropBox = null;
      _ocrDebugLocalCropBox = null;
      _ocrDebugMidContextBox = null;
      _ocrDebugMidLeftBox = null;
      _ocrDebugMidGlyphBox = null;
      _ocrDebugMidRightBox = null;
      _ocrDebugLocalSlot = null;
      _ocrDebugFocusPoint = null;
      _ocrDebugCropBytes = null;
      _ocrDebugSourcePlateBytes = null;
      _ocrDebugRectifiedPlateBytes = null;
      _ocrDebugLocalCropBytes = null;
      _ocrDebugMidContextBytes = null;
      _ocrDebugMidGlyphBytes = null;
      _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.none;
      _ocrDebugCropText = null;
      _ocrDebugLocalCropText = null;
      _ocrDebugMidAnchorStatus = null;
      _ocrDebugMidGlyphText = null;
      _ocrDebugMidContextText = null;
      _ocrDebugStructuredPlate = null;
      _ocrDebugRecoveredPlate = null;
      _ocrDebugCropOcrMs = null;
      _ocrDebugLocalOcrMs = null;
      _ocrDebugLocalWallMs = null;
      _ocrDebugRecoveryWallMs = null;
      _ocrDebugPerspectiveQuad = null;
      _ocrDebugPerspectiveApplied = false;
      _ocrDebugPerspectiveAngle = null;
      _ocrDebugRectifiedSize = null;
      _ocrDebugPerspectiveText = null;
    }
    _ocrDebugStage = stage;
    _ocrDebugStageDetail = detail;
    if (structuredPlate != null) {
      _ocrDebugStructuredPlate = structuredPlate;
    }
    if (recoveredPlate != null) {
      _ocrDebugRecoveredPlate = recoveredPlate;
    }
    if (focusPoint != null) {
      _ocrDebugFocusPoint = focusPoint;
    }
    _ocrDebugRevision++;
    _appendLog(
      'debugStage=${stage.name} detail=${detail ?? '-'} '
          'structured=${_ocrDebugStructuredPlate ?? '-'} '
          'recovered=${_ocrDebugRecoveredPlate ?? '-'}',
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _setRawOcrDebugGeometry({
    required RecognizedText result,
    required Size? sourceImageSize,
  }) {
    if (!_developerMode) return;
    final boxes = <_OcrDebugLineBox>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        boxes.add(
          _OcrDebugLineBox(
            box: line.boundingBox,
            text: text,
          ),
        );
      }
    }
    _ocrDebugStage = _OcrDebugStage.fullOcr;
    _ocrDebugLineBoxes = boxes;
    _ocrDebugSourceImageSize = sourceImageSize;
    _ocrDebugWeakBox = null;
    _ocrDebugCropBox = null;
    _ocrDebugLocalCropBox = null;
    _ocrDebugMidContextBox = null;
    _ocrDebugMidLeftBox = null;
    _ocrDebugMidGlyphBox = null;
    _ocrDebugMidRightBox = null;
    _ocrDebugLocalSlot = null;
    _ocrDebugFocusPoint = null;
    _ocrDebugCropBytes = null;
    _ocrDebugSourcePlateBytes = null;
    _ocrDebugRectifiedPlateBytes = null;
    _ocrDebugLocalCropBytes = null;
    _ocrDebugMidContextBytes = null;
    _ocrDebugMidGlyphBytes = null;
    _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.none;
    _ocrDebugCropText = null;
    _ocrDebugLocalCropText = null;
    _ocrDebugMidAnchorStatus = null;
    _ocrDebugMidGlyphText = null;
    _ocrDebugMidContextText = null;
    _ocrDebugCropOcrMs = null;
    _ocrDebugLocalOcrMs = null;
    _ocrDebugLocalWallMs = null;
    _ocrDebugRecoveryWallMs = null;
    _ocrDebugStructuredPlate = null;
    _ocrDebugRecoveredPlate = null;
    _ocrDebugStageDetail = 'lines=${boxes.length}';
    _ocrDebugRevision++;
    _appendLog(
      'debugGeometry lines=${boxes.length} sourceSize='
          '${sourceImageSize == null ? '-' : '${sourceImageSize.width.toInt()}x${sourceImageSize.height.toInt()}'}',
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _holdDeveloperVisualization() async {
    if (!_developerMode) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    await Future<void>.delayed(_developerRecoveredHold);
  }

  Future<void> _developerDebugBeat([
    Duration duration = const Duration(milliseconds: 180),
  ]) async {
    if (!_developerMode) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    await Future<void>.delayed(duration);
  }

  Future<_DecodedCapture?> _decodeCaptureForGeometry(
      String path,
      RecognizedText result,
      ) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _appendLog('geometry image decode 실패 path=$path');
        return null;
      }

      final baked = img.bakeOrientation(decoded);
      final decodedFits = _imageSizeFitsRecognizedText(
        Size(decoded.width.toDouble(), decoded.height.toDouble()),
        result,
      );
      final bakedFits = _imageSizeFitsRecognizedText(
        Size(baked.width.toDouble(), baked.height.toDouble()),
        result,
      );
      final geometryReliable = decodedFits || bakedFits;
      final selected = bakedFits || !decodedFits ? baked : decoded;
      final size = Size(
        selected.width.toDouble(),
        selected.height.toDouble(),
      );
      _appendLog(
        'geometry image size=${selected.width}x${selected.height} '
            'decodedFits=$decodedFits bakedFits=$bakedFits '
            'reliable=$geometryReliable',
      );
      return _DecodedCapture(
        image: selected,
        imageSize: size,
        geometryReliable: geometryReliable,
        decodedFits: decodedFits,
        bakedFits: bakedFits,
      );
    } catch (e, stackTrace) {
      _appendLog('geometry image load 오류 $e');
      _appendLog('geometry image stack=$stackTrace');
      return null;
    }
  }

  bool _imageSizeFitsRecognizedText(Size imageSize, RecognizedText result) {
    double maxRight = 0;
    double maxBottom = 0;
    for (final block in result.blocks) {
      maxRight = math.max(maxRight, block.boundingBox.right);
      maxBottom = math.max(maxBottom, block.boundingBox.bottom);
      for (final line in block.lines) {
        maxRight = math.max(maxRight, line.boundingBox.right);
        maxBottom = math.max(maxBottom, line.boundingBox.bottom);
      }
    }
    return maxRight <= imageSize.width + 4 &&
        maxBottom <= imageSize.height + 4;
  }

  String _normalizeWeakSource(String text) {
    var value = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    const fullWidthDigits = {
      '０': '0',
      '１': '1',
      '２': '2',
      '３': '3',
      '４': '4',
      '５': '5',
      '６': '6',
      '７': '7',
      '８': '8',
      '９': '9',
    };
    fullWidthDigits.forEach((key, mapped) {
      value = value.replaceAll(key, mapped);
    });
    return value.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  bool _digitsSupportWeakCandidate(
      String digits,
      _StructuredWeakCandidate candidate,
      ) {
    if (digits.isEmpty) return false;
    final targetDigits = '${candidate.front}${candidate.back}';
    if (digits.contains(targetDigits)) return true;
    final pattern = RegExp(
      '${RegExp.escape(candidate.front)}\\d{0,2}${RegExp.escape(candidate.back)}',
    );
    return pattern.hasMatch(digits);
  }

  Rect _unionRects(Iterable<Rect> rects) {
    final list = rects.where((rect) => rect.width > 0 && rect.height > 0).toList();
    if (list.isEmpty) return Rect.zero;
    var left = list.first.left;
    var top = list.first.top;
    var right = list.first.right;
    var bottom = list.first.bottom;
    for (final rect in list.skip(1)) {
      left = math.min(left, rect.left);
      top = math.min(top, rect.top);
      right = math.max(right, rect.right);
      bottom = math.max(bottom, rect.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect? _estimatedLiteralSpanBox(TextLine line, String literal) {
    final source = _normalizeWeakSource(line.text);
    if (source.isEmpty || literal.isEmpty) return null;
    final index = source.indexOf(literal);
    if (index < 0) return null;
    final lineBox = line.boundingBox;
    if (lineBox.width <= 0 || lineBox.height <= 0) return null;
    final startRatio = index / source.length;
    final endRatio = (index + literal.length) / source.length;
    final pad = math.max(lineBox.height * .18, 2.0);
    return Rect.fromLTRB(
      lineBox.left + lineBox.width * startRatio - pad,
      lineBox.top,
      lineBox.left + lineBox.width * endRatio + pad,
      lineBox.bottom,
    );
  }

  Rect? _estimatedCandidateSpanBox(
      TextLine line,
      _StructuredWeakCandidate candidate,
      ) {
    final source = _normalizeWeakSource(line.text);
    if (source.isEmpty) return null;
    final sep = r'[\s\.\-·•_]*';
    final tokenPattern = candidate.observedToken.isEmpty
        ? r'[0-9A-Za-z○#]{0,2}'
        : '(?:${RegExp.escape(candidate.observedToken)}|[0-9A-Za-z○#]{0,2})';
    final pattern = RegExp(
      '${RegExp.escape(candidate.front)}$sep$tokenPattern$sep${RegExp.escape(candidate.back)}',
    );
    final match = pattern.firstMatch(source);
    if (match == null) return null;
    final lineBox = line.boundingBox;
    if (lineBox.width <= 0 || lineBox.height <= 0) return null;
    final startRatio = match.start / source.length;
    final endRatio = match.end / source.length;
    final pad = math.max(lineBox.height * .22, 3.0);
    return Rect.fromLTRB(
      lineBox.left + lineBox.width * startRatio - pad,
      lineBox.top,
      lineBox.left + lineBox.width * endRatio + pad,
      lineBox.bottom,
    );
  }

  Rect? _candidateElementUnionBox(
      TextLine line,
      _StructuredWeakCandidate candidate,
      ) {
    final wholeEvidence = <Rect>[];
    final frontEvidence = <Rect>[];
    final backEvidence = <Rect>[];
    for (final element in line.elements) {
      final raw = _normalizeWeakSource(element.text);
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (_digitsSupportWeakCandidate(digits, candidate)) {
        wholeEvidence.add(element.boundingBox);
        continue;
      }
      if (digits.contains(candidate.front)) {
        frontEvidence.add(element.boundingBox);
      }
      if (digits.contains(candidate.back)) {
        backEvidence.add(element.boundingBox);
      }
    }
    if (wholeEvidence.isNotEmpty) {
      final box = _unionRects(wholeEvidence);
      return box == Rect.zero ? null : box;
    }
    if (frontEvidence.isNotEmpty && backEvidence.isNotEmpty) {
      final box = _unionRects([...frontEvidence, ...backEvidence]);
      return box == Rect.zero ? null : box;
    }
    return null;
  }

  ({Rect box, String kind})? _tightCandidateBoxInLine(
      TextLine line,
      _StructuredWeakCandidate candidate,
      ) {
    final boxes = <({Rect box, String kind})>[];
    final elementBox = _candidateElementUnionBox(line, candidate);
    if (elementBox != null) {
      boxes.add((box: elementBox, kind: 'elementUnion'));
    }
    final estimatedBox = _estimatedCandidateSpanBox(line, candidate);
    if (estimatedBox != null) {
      boxes.add((box: estimatedBox, kind: 'lineSpan'));
    }
    if (boxes.isEmpty) return null;
    boxes.sort((a, b) {
      final aa = a.box.width * a.box.height;
      final bb = b.box.width * b.box.height;
      return aa.compareTo(bb);
    });
    return boxes.first;
  }

  ({double slope, double intercept})? _fitLine(List<Offset> points) {
    if (points.length < 2) return null;
    final meanX = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final meanY = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (final point in points) {
      final dx = point.dx - meanX;
      numerator += dx * (point.dy - meanY);
      denominator += dx * dx;
    }
    if (denominator.abs() < .0001) return null;
    final slope = numerator / denominator;
    return (slope: slope, intercept: meanY - slope * meanX);
  }

  _PlateQuad? _estimatePlateQuadFromLines(
    List<TextLine> lines,
    Rect fallback,
  ) {
    final search = fallback.inflate(math.max(8.0, fallback.height * .45));
    final boxes = <Rect>[];
    for (final line in lines) {
      for (final element in line.elements) {
        final box = element.boundingBox;
        if (box.width <= 1 || box.height <= 1) continue;
        if (box.overlaps(search) || search.contains(box.center)) {
          boxes.add(box);
        }
      }
    }
    if (boxes.length < 2) return null;
    boxes.sort((a, b) => a.center.dx.compareTo(b.center.dx));
    final heights = boxes.map((box) => box.height).where((v) => v > 0).toList();
    final widths = boxes.map((box) => box.width).where((v) => v > 0).toList();
    if (heights.isEmpty || widths.isEmpty) return null;
    heights.sort();
    widths.sort();
    final medianHeight = heights[heights.length ~/ 2];
    final medianWidth = widths[widths.length ~/ 2];
    final topPoints = boxes.map((box) => Offset(box.center.dx, box.top)).toList();
    final bottomPoints = boxes.map((box) => Offset(box.center.dx, box.bottom)).toList();
    final topFit = _fitLine(topPoints);
    final bottomFit = _fitLine(bottomPoints);
    if (topFit == null || bottomFit == null) return null;
    if (topFit.slope.abs() > 1.15 || bottomFit.slope.abs() > 1.15) return null;
    final left = boxes.map((box) => box.left).reduce(math.min) - math.max(4.0, medianWidth * .28);
    final right = boxes.map((box) => box.right).reduce(math.max) + math.max(4.0, medianWidth * .28);
    final padY = math.max(3.0, medianHeight * .20);
    final topLeftY = topFit.slope * left + topFit.intercept - padY;
    final topRightY = topFit.slope * right + topFit.intercept - padY;
    final bottomLeftY = bottomFit.slope * left + bottomFit.intercept + padY;
    final bottomRightY = bottomFit.slope * right + bottomFit.intercept + padY;
    if (bottomLeftY - topLeftY < medianHeight * .55 ||
        bottomRightY - topRightY < medianHeight * .55) {
      return null;
    }
    final quad = _PlateQuad(
      topLeft: Offset(left, topLeftY),
      topRight: Offset(right, topRightY),
      bottomRight: Offset(right, bottomRightY),
      bottomLeft: Offset(left, bottomLeftY),
    );
    final averageWidth = (quad.topLength + quad.bottomLength) / 2;
    final averageHeight = (quad.leftLength + quad.rightLength) / 2;
    if (averageWidth <= averageHeight * 1.8 || averageHeight <= 2) return null;
    return quad;
  }

  _WeakPlateRegion? _findWeakPlateRegion(
      RecognizedText result,
      List<_StructuredWeakCandidate> weakCandidates,
      ) {
    if (weakCandidates.isEmpty) return null;
    final sorted = List<_StructuredWeakCandidate>.from(weakCandidates)
      ..sort((a, b) => b.score.compareTo(a.score));

    _WeakPlateRegion? best;

    void consider({
      required Rect box,
      required String text,
      required String sourceKind,
      required _StructuredWeakCandidate candidate,
      required double bonus,
      _PlateQuad? quad,
    }) {
      if (box.width <= 0 || box.height <= 0) return;
      final perspectiveBonus = quad == null ? 0.0 : .35;
      final score = candidate.score + bonus + perspectiveBonus -
          (box.width * box.height * 0.000002);
      if (best == null || score > best!.score) {
        best = _WeakPlateRegion(
          box: box,
          front: candidate.front,
          back: candidate.back,
          signature: candidate.signature,
          sourceText: text,
          sourceKind: sourceKind,
          score: score,
          quad: quad,
        );
      }
    }

    for (final candidate in sorted) {
      final frontLines = <TextLine>[];
      final backLines = <TextLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final weakSource = _normalizeWeakSource(line.text);
          final digitsOnly = weakSource.replaceAll(RegExp(r'[^0-9]'), '');
          if (digitsOnly.contains(candidate.front)) {
            frontLines.add(line);
          }
          if (digitsOnly.contains(candidate.back)) {
            backLines.add(line);
          }
          if (_digitsSupportWeakCandidate(digitsOnly, candidate)) {
            final tight = _tightCandidateBoxInLine(line, candidate);
            if (tight != null) {
              consider(
                box: tight.box,
                text: line.text,
                sourceKind: tight.kind,
                candidate: candidate,
                bonus: 3.2,
                quad: _estimatePlateQuadFromLines([line], tight.box),
              );
            } else {
              consider(
                box: line.boundingBox,
                text: line.text,
                sourceKind: 'lineFallback',
                candidate: candidate,
                bonus: 1.0,
                quad: _estimatePlateQuadFromLines([line], line.boundingBox),
              );
            }
          }
        }
      }

      for (final frontLine in frontLines) {
        for (final backLine in backLines) {
          if (identical(frontLine, backLine)) continue;
          final frontBox =
              _estimatedLiteralSpanBox(frontLine, candidate.front) ??
                  frontLine.boundingBox;
          final backBox = _estimatedLiteralSpanBox(backLine, candidate.back) ??
              backLine.boundingBox;
          final averageHeight = (frontBox.height + backBox.height) / 2;
          final delta = backBox.center - frontBox.center;
          if (delta.dx <= 0) continue;
          final angle = math.atan2(delta.dy, delta.dx).abs();
          if (angle > math.pi * .24) continue;
          final centerDistance = delta.distance;
          final projectedGap = centerDistance - (frontBox.width + backBox.width) / 2;
          if (projectedGap < -math.max(frontBox.width, backBox.width) * .32) {
            continue;
          }
          if (projectedGap > math.max(averageHeight * 5.2, 145.0)) continue;
          final combined = Rect.fromLTRB(
            math.min(frontBox.left, backBox.left),
            math.min(frontBox.top, backBox.top),
            math.max(frontBox.right, backBox.right),
            math.max(frontBox.bottom, backBox.bottom),
          );
          consider(
            box: combined,
            text: '${frontLine.text} ${backLine.text}',
            sourceKind: 'adjacentLines',
            candidate: candidate,
            bonus: 1.8,
            quad: _estimatePlateQuadFromLines(
              [frontLine, backLine],
              combined,
            ),
          );
        }
      }
    }

    return best;
  }

  Rect _expandWeakPlateRect(Rect source, Size imageSize) {
    final padX = math.max(source.width * .10, source.height * .65);
    final padY = math.max(source.height * .48, 10.0);
    final left = (source.left - padX).clamp(0.0, imageSize.width).toDouble();
    final top = (source.top - padY).clamp(0.0, imageSize.height).toDouble();
    final right =
    (source.right + padX).clamp(0.0, imageSize.width).toDouble();
    final bottom =
    (source.bottom + padY).clamp(0.0, imageSize.height).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Offset _normalizedFocusPoint(Rect rect, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return const Offset(.5, .5);
    }
    return Offset(
      (rect.center.dx / imageSize.width).clamp(0.0, 1.0).toDouble(),
      (rect.center.dy / imageSize.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  ({String front, String back})? _splitRefocusSignature(String signature) {
    final match = RegExp(r'^([0-9]{2,3})\?([0-9]{4})$').firstMatch(signature);
    if (match == null) return null;
    return (front: match.group(1)!, back: match.group(2)!);
  }

  bool _sameRefocusIdentity(String current, String previous) {
    final a = _splitRefocusSignature(current);
    final b = _splitRefocusSignature(previous);
    if (a == null || b == null) return current == previous;
    if (a.back != b.back) return false;
    return a.front == b.front ||
        a.front.startsWith(b.front) ||
        b.front.startsWith(a.front);
  }

  bool _sameStableWeakIdentity(String current, String previous) {
    return current == previous;
  }

  int _exactWeakVoteCount(String signature) {
    var count = 0;
    for (final frame in _weakStructuredFrames) {
      if (frame.contains(signature)) {
        count++;
      }
    }
    return count;
  }

  int _exactWeakEvidenceIncludingCurrent(
    String signature,
    List<_StructuredWeakCandidate> currentFrame,
  ) {
    var count = _exactWeakVoteCount(signature);
    if (currentFrame.any(
      (candidate) => _sameStableWeakIdentity(signature, candidate.signature),
    )) {
      count++;
    }
    return math.min(_voteWindow, count).toInt();
  }

  bool _hasFastRecoveryExecuted(String signature) {
    return _fastRecoveryExecutedIdentities.any(
      (executed) => _sameStableWeakIdentity(signature, executed),
    );
  }

  bool _hasFastRecoveryAbandoned(String signature) {
    return _fastRecoveryAbandonedIdentities.any(
      (abandoned) => _sameStableWeakIdentity(signature, abandoned),
    );
  }

  bool _isFastRecoveryClosed(String signature) {
    if (widget.coordinator.profile.repeatRecoveryAcrossFrames) return false;
    return _hasFastRecoveryExecuted(signature) ||
        _hasFastRecoveryAbandoned(signature);
  }

  int _fastRecoveryDeferredCount(String signature) {
    return _fastRecoveryDeferredFrames[signature] ?? 0;
  }

  int _recordFastRecoveryDeferredFrame(String signature) {
    final next = (_fastRecoveryDeferredFrames[signature] ?? 0) + 1;
    _fastRecoveryDeferredFrames[signature] = next;
    return next;
  }

  void _setRecoveryMode(_OcrRecoveryMode mode, {String? identity}) {
    final changed = _recoveryMode != mode || _fastRecoveryIdentity != identity;
    _recoveryMode = mode;
    _fastRecoveryIdentity = identity;
    if (mode == _OcrRecoveryMode.scanning) {
      _fastRecoveryCandidateSnapshot = null;
    }
    if (!changed) return;
    _appendLog(
      'recoveryMode=${mode.name} identity=${identity ?? '-'}',
    );
    if (mounted) {
      setState(() {});
    }
  }

  bool _hasMajorRefocusGeometryChange(
      Rect current,
      Size currentSize,
      Rect previous,
      Size previousSize,
      ) {
    if (currentSize.width <= 0 ||
        currentSize.height <= 0 ||
        previousSize.width <= 0 ||
        previousSize.height <= 0) {
      return true;
    }
    final currentCenter = Offset(
      current.center.dx / currentSize.width,
      current.center.dy / currentSize.height,
    );
    final previousCenter = Offset(
      previous.center.dx / previousSize.width,
      previous.center.dy / previousSize.height,
    );
    final centerShift = (currentCenter - previousCenter).distance;
    final currentScale = math.sqrt(
      math.max(1.0, current.width * current.height) /
          (currentSize.width * currentSize.height),
    );
    final previousScale = math.sqrt(
      math.max(1.0, previous.width * previous.height) /
          (previousSize.width * previousSize.height),
    );
    final scaleRatio = previousScale <= 0
        ? double.infinity
        : math.max(currentScale / previousScale, previousScale / currentScale);
    return centerShift >= _refocusMajorCenterShift ||
        scaleRatio >= _refocusMajorScaleRatio;
  }

  int get _refocusCooldownRemainingMs {
    final last = _lastAutoRefocusAt;
    if (last == null) return 0;
    final elapsed = DateTime.now().difference(last).inMilliseconds;
    return math.max(0, _refocusCooldownMs - elapsed).toInt();
  }

  ({bool allow, String reason}) _evaluateAutoRefocus(
      _CropRecoveryOutcome outcome,
      ) {
    final lastAt = _lastAutoRefocusAt;
    final lastIdentity = _lastAutoRefocusIdentity;
    final lastRegion = _lastAutoRefocusRegion;
    final lastSize = _lastAutoRefocusImageSize;
    if (lastAt == null ||
        lastIdentity == null ||
        lastRegion == null ||
        lastSize == null) {
      return (allow: true, reason: 'first');
    }
    final elapsed = DateTime.now().difference(lastAt).inMilliseconds;
    if (!_sameRefocusIdentity(outcome.signature, lastIdentity)) {
      return (allow: true, reason: 'identityChanged');
    }
    if (_hasMajorRefocusGeometryChange(
      outcome.sourceRegion,
      outcome.sourceImageSize,
      lastRegion,
      lastSize,
    )) {
      return (allow: true, reason: 'geometryChanged');
    }
    if (elapsed >= _refocusCooldownMs) {
      return (allow: true, reason: 'cooldownExpired');
    }
    return (
    allow: false,
    reason: 'cooldown:${math.max(0, _refocusCooldownMs - elapsed)}ms',
    );
  }

  void _recordAutoRefocus(_CropRecoveryOutcome outcome, String reason) {
    _lastAutoRefocusAt = DateTime.now();
    _lastAutoRefocusIdentity = outcome.signature;
    _lastAutoRefocusRegion = outcome.sourceRegion;
    _lastAutoRefocusImageSize = outcome.sourceImageSize;
    _lastRefocusDecision = 'allowed:$reason';
  }

  bool _canRunHeavyRecovery(String signature) {
    final lastAttempt = _lastHeavyRecoveryAttemptBySignature[signature];
    if (lastAttempt == null) return true;
    return _attempt - lastAttempt > _heavyRecoveryCooldownFrames;
  }

  int _heavyRecoveryCooldownRemainingFrames(String signature) {
    final lastAttempt = _lastHeavyRecoveryAttemptBySignature[signature];
    if (lastAttempt == null) return 0;
    return math.max(
      0,
      _heavyRecoveryCooldownFrames - (_attempt - lastAttempt) + 1,
    ).toInt();
  }

  void _markHeavyRecovery(String signature) {
    _lastHeavyRecoveryAttemptBySignature[signature] = _attempt;
  }

  int get _estimatedNextFrameWallMs {
    final capture = _ocrDebugCaptureMs ?? 500;
    final fullOcr = _ocrDebugFullOcrMs ?? 180;
    return _autoIntervalMs + capture + fullOcr;
  }

  bool _localRecoveryFitsLatencyBudget(String signature) {
    if (_lastLocalStageSignature != signature || _lastLocalStageWallMs == null) {
      return true;
    }
    return _lastLocalStageWallMs! <= _estimatedNextFrameWallMs;
  }

  void _recordLocalStageWall(String signature, int wallMs) {
    _lastLocalStageSignature = signature;
    _lastLocalStageWallMs = wallMs;
    _ocrDebugLocalWallMs = wallMs;
  }

  String _localEvidenceKey(String front, String back) {
    final prefixLength = math.min(2, front.length).toInt();
    final prefix = front.substring(0, prefixLength);
    return '$prefix|$back';
  }

  void _recordLocalMidEvidence(
    String front,
    String back,
    _MidGlyphEvidence glyph,
    _MidAnchorEvidence anchors,
  ) {
    if (!anchors.leftMatched && !anchors.rightMatched) return;
    final key = _localEvidenceKey(front, back);
    final votes = _localMidEvidenceVotes.putIfAbsent(
      key,
      () => <String, int>{},
    );
    final weight = anchors.strong ? 2 : 1;
    votes[glyph.mid] = (votes[glyph.mid] ?? 0) + weight;
    _appendLog(
      'local mid evidence key=$key mid=${glyph.mid} weight=$weight '
          'total=${votes[glyph.mid]} anchorStrong=${anchors.strong} '
          'anchorQuality=${anchors.quality}',
    );
  }

  ({String mid, int votes})? _bestLocalMidEvidence(
    String front,
    String back,
  ) {
    final votes = _localMidEvidenceVotes[_localEvidenceKey(front, back)];
    if (votes == null || votes.isEmpty) return null;
    final ranked = votes.entries.toList()
      ..sort((a, b) {
        final byVotes = b.value.compareTo(a.value);
        if (byVotes != 0) return byVotes;
        return a.key.compareTo(b.key);
      });
    final best = ranked.first;
    return (mid: best.key, votes: best.value);
  }

  _PlateSlotUncertainty _analyzeSlotUncertainty({
    required _WeakPlateRegion region,
    required List<_StructuredWeakCandidate> weakCandidates,
  }) {
    final relevant = weakCandidates
        .where((candidate) => candidate.back == region.back)
        .toList(growable: false);
    final fronts = relevant.map((candidate) => candidate.front).toSet();
    final backs = weakCandidates.map((candidate) => candidate.back).toSet();
    final resolvedFront = _resolveFrontFromEvidence(region.back, weakCandidates);
    return _PlateSlotUncertainty(
      front: resolvedFront == null || fronts.length > 1,
      mid: true,
      back: backs.length > 1,
    );
  }

  Rect _clampRecoveryRect(Rect rect, Size imageSize) {
    final maxWidth = math.max(1.0, imageSize.width);
    final maxHeight = math.max(1.0, imageSize.height);
    final left = rect.left.clamp(0.0, maxWidth - 1.0).toDouble();
    final top = rect.top.clamp(0.0, maxHeight - 1.0).toDouble();
    final right = rect.right.clamp(left + 1.0, maxWidth).toDouble();
    final bottom = rect.bottom.clamp(top + 1.0, maxHeight).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _estimatedSourceRangeBox({
    required Rect sourceBox,
    required int sourceLength,
    required int start,
    required int end,
  }) {
    if (sourceLength <= 0 || sourceBox.width <= 0 || sourceBox.height <= 0) {
      return sourceBox;
    }
    final safeStart = start.clamp(0, sourceLength).toInt();
    final safeEnd = end.clamp(safeStart + 1, sourceLength).toInt();
    final startRatio = safeStart / sourceLength;
    final endRatio = safeEnd / sourceLength;
    final pad = math.max(sourceBox.height * .20, 3.0);
    return Rect.fromLTRB(
      sourceBox.left + sourceBox.width * startRatio - pad,
      sourceBox.top - pad * .25,
      sourceBox.left + sourceBox.width * endRatio + pad,
      sourceBox.bottom + pad * .25,
    );
  }

  List<_PartialBoundarySeed> _extractPartialBoundarySeeds(
    RecognizedText result, {
    required VoidCallback onUseLearningMid,
  }) {
    final out = <_PartialBoundarySeed>[];
    final seen = <String>{};
    final sep = r'[\s\.\-·•_]*';
    final frontBroken = RegExp(
      '(?<![0-9A-Za-z가-힣])([0-9A-Za-z○#|]{2,3})$sep([가-힣])$sep(\\d{4})(?![0-9A-Za-z가-힣])',
    );
    final backBroken = RegExp(
      '(?<![0-9A-Za-z가-힣])(\\d{2,3})$sep([가-힣])$sep([0-9A-Za-z○#|]{4})(?![0-9A-Za-z가-힣])',
    );

    void process(String rawSource, Rect sourceBox, String sourceKind) {
      final source = _normalizeWeakSource(rawSource);
      if (source.isEmpty || sourceBox.width <= 0 || sourceBox.height <= 0) return;

      for (final match in frontBroken.allMatches(source)) {
        final rawFront = match.group(1)!;
        final mappedFront = _applyCharMap(rawFront);
        if (RegExp(r'^\d{2,3}$').hasMatch(mappedFront)) continue;
        final rawMid = match.group(2)!;
        final mid = _normalizeMidToken(
          rawMid,
          onUseLearningMid: onUseLearningMid,
        );
        if (!_KoreanPlatePolicy.allowedNewMids.contains(mid)) continue;
        final back = match.group(3)!;
        final plateBox = _estimatedSourceRangeBox(
          sourceBox: sourceBox,
          sourceLength: source.length,
          start: match.start,
          end: match.end,
        );
        final key = 'front|$rawFront|$mid|$back|${plateBox.left.round()}|${plateBox.top.round()}';
        if (!seen.add(key)) continue;
        out.add(
          _PartialBoundarySeed(
            slot: _PlateRecoverySlot.front,
            plateBox: plateBox,
            front: null,
            mid: mid,
            back: back,
            frontLen: rawFront.length.clamp(2, 3).toInt(),
            rawFront: rawFront,
            rawBack: back,
            sourceText: rawSource,
            sourceKind: sourceKind,
            score: sourceKind == 'line' ? 6.0 : 5.2,
          ),
        );
      }

      for (final match in backBroken.allMatches(source)) {
        final front = match.group(1)!;
        final rawMid = match.group(2)!;
        final mid = _normalizeMidToken(
          rawMid,
          onUseLearningMid: onUseLearningMid,
        );
        if (!_KoreanPlatePolicy.allowedNewMids.contains(mid)) continue;
        final rawBack = match.group(3)!;
        final mappedBack = _applyCharMap(rawBack);
        if (RegExp(r'^\d{4}$').hasMatch(mappedBack)) continue;
        final plateBox = _estimatedSourceRangeBox(
          sourceBox: sourceBox,
          sourceLength: source.length,
          start: match.start,
          end: match.end,
        );
        final key = 'back|$front|$mid|$rawBack|${plateBox.left.round()}|${plateBox.top.round()}';
        if (!seen.add(key)) continue;
        out.add(
          _PartialBoundarySeed(
            slot: _PlateRecoverySlot.back,
            plateBox: plateBox,
            front: front,
            mid: mid,
            back: null,
            frontLen: front.length,
            rawFront: front,
            rawBack: rawBack,
            sourceText: rawSource,
            sourceKind: sourceKind,
            score: sourceKind == 'line' ? 6.0 : 5.2,
          ),
        );
      }
    }

    for (final block in result.blocks) {
      final lines = block.lines;
      for (var i = 0; i < lines.length; i++) {
        process(lines[i].text, lines[i].boundingBox, 'line');
        if (i + 1 < lines.length) {
          final union = _unionRects([
            lines[i].boundingBox,
            lines[i + 1].boundingBox,
          ]);
          process('${lines[i].text} ${lines[i + 1].text}', union, 'adjacentLines');
        }
      }
    }

    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  List<_BoundaryAnchorCandidate> _buildAdaptiveBoundaryRects({
    required RecognizedText result,
    required Rect plateBox,
    required Size imageSize,
    required _PlateRecoverySlot slot,
    required int frontLen,
    String? front,
    String? back,
    String? mid,
  }) {
    final out = <_BoundaryAnchorCandidate>[];
    final seen = <String>{};
    final envelope = _clampRecoveryRect(
      plateBox.inflate(math.max(plateBox.height * 1.5, 18.0)),
      imageSize,
    );

    void add(Rect rawRect, String sourceKind, double score) {
      if (!rawRect.overlaps(envelope) && !envelope.contains(rawRect.center)) {
        return;
      }
      var rect = rawRect.intersect(envelope);
      rect = _clampRecoveryRect(rect, imageSize);
      if (rect.width < 4 || rect.height < 4) return;
      final key = '${rect.left.round()}|${rect.top.round()}|${rect.right.round()}|${rect.bottom.round()}';
      if (!seen.add(key)) return;
      out.add(
        _BoundaryAnchorCandidate(
          rect: rect,
          sourceKind: sourceKind,
          score: score,
        ),
      );
    }

    Rect expandVertical(Rect rect, double factor) {
      final padY = math.max(rect.height * factor, 7.0);
      return Rect.fromLTRB(rect.left, rect.top - padY, rect.right, rect.bottom + padY);
    }

    String? normalizedAllowedMid(String raw) {
      if (!RegExp(r'^[가-힣]$').hasMatch(raw)) return null;
      final normalized = _KoreanPlatePolicy.staticMidNormalize[raw] ?? raw;
      if (!_KoreanPlatePolicy.allowedNewMids.contains(normalized)) return null;
      if (mid != null && normalized != mid) return null;
      return normalized;
    }

    final searchRect = envelope;
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final lineBox = line.boundingBox;
        if (!searchRect.overlaps(lineBox) && !searchRect.contains(lineBox.center)) {
          continue;
        }

        final frontElements = <Rect>[];
        final midElements = <Rect>[];
        final backElements = <Rect>[];
        for (final element in line.elements) {
          final raw = _normalizeWeakSource(element.text);
          final mapped = _applyCharMap(raw);
          final digits = mapped.replaceAll(RegExp(r'[^0-9]'), '');
          if (front != null && digits.contains(front)) {
            frontElements.add(element.boundingBox);
          }
          if (back != null && digits.contains(back)) {
            backElements.add(element.boundingBox);
          }
          final chars = raw.split('');
          if (chars.any((char) => normalizedAllowedMid(char) != null)) {
            midElements.add(element.boundingBox);
          }
        }

        if (slot == _PlateRecoverySlot.front) {
          for (final f in frontElements) {
            for (final m in midElements) {
              if (m.center.dx + m.width * .4 < f.center.dx) continue;
              add(
                expandVertical(_unionRects([f, m]), .34),
                'elementPair',
                6.4,
              );
            }
          }
          for (final m in midElements) {
            final left = math.max(plateBox.left, m.left - math.max(m.width, m.height) * (frontLen + .7));
            add(
              expandVertical(Rect.fromLTRB(left, math.min(plateBox.top, m.top), m.right + m.width * .35, math.max(plateBox.bottom, m.bottom)), .28),
              'midElementAnchor',
              5.5,
            );
          }
          for (final f in frontElements) {
            add(
              expandVertical(Rect.fromLTRB(f.left - f.height * .2, f.top, f.right + f.height * 1.45, f.bottom), .32),
              'frontElementAnchor',
              4.7,
            );
          }
        } else if (slot == _PlateRecoverySlot.back) {
          for (final m in midElements) {
            for (final b in backElements) {
              if (b.center.dx - b.width * .4 < m.center.dx) continue;
              add(
                expandVertical(_unionRects([m, b]), .34),
                'elementPair',
                6.4,
              );
            }
          }
          for (final m in midElements) {
            final right = math.min(plateBox.right, m.right + math.max(m.width, m.height) * 5.0);
            add(
              expandVertical(Rect.fromLTRB(m.left - m.width * .35, math.min(plateBox.top, m.top), right, math.max(plateBox.bottom, m.bottom)), .28),
              'midElementAnchor',
              5.5,
            );
          }
          for (final b in backElements) {
            add(
              expandVertical(Rect.fromLTRB(b.left - b.height * 1.45, b.top, b.right + b.height * .2, b.bottom), .32),
              'backElementAnchor',
              4.7,
            );
          }
        }

        Rect? midSpan;
        if (mid != null) {
          midSpan = _estimatedLiteralSpanBox(line, mid);
        } else {
          final normalizedLine = _normalizeWeakSource(line.text);
          for (final char in normalizedLine.split('')) {
            if (normalizedAllowedMid(char) != null) {
              midSpan = _estimatedLiteralSpanBox(line, char);
              if (midSpan != null) break;
            }
          }
        }
        final frontSpan = front == null ? null : _estimatedLiteralSpanBox(line, front);
        final backSpan = back == null ? null : _estimatedLiteralSpanBox(line, back);

        if (slot == _PlateRecoverySlot.front) {
          if (frontSpan != null && midSpan != null) {
            add(expandVertical(_unionRects([frontSpan, midSpan]), .30), 'linePair', 6.0);
          }
          if (midSpan != null) {
            add(
              expandVertical(Rect.fromLTRB(plateBox.left, math.min(plateBox.top, midSpan.top), midSpan.right + midSpan.height * .45, math.max(plateBox.bottom, midSpan.bottom)), .24),
              'lineMidAnchor',
              5.0,
            );
          }
          if (frontSpan != null) {
            add(
              expandVertical(Rect.fromLTRB(frontSpan.left, frontSpan.top, frontSpan.right + frontSpan.height * 1.5, frontSpan.bottom), .30),
              'lineFrontAnchor',
              4.4,
            );
          }
        } else if (slot == _PlateRecoverySlot.back) {
          if (midSpan != null && backSpan != null) {
            add(expandVertical(_unionRects([midSpan, backSpan]), .30), 'linePair', 6.0);
          }
          if (midSpan != null) {
            add(
              expandVertical(Rect.fromLTRB(midSpan.left - midSpan.height * .45, math.min(plateBox.top, midSpan.top), plateBox.right, math.max(plateBox.bottom, midSpan.bottom)), .24),
              'lineMidAnchor',
              5.0,
            );
          }
          if (backSpan != null) {
            add(
              expandVertical(Rect.fromLTRB(backSpan.left - backSpan.height * 1.5, backSpan.top, backSpan.right, backSpan.bottom), .30),
              'lineBackAnchor',
              4.4,
            );
          }
        }
      }
    }

    final totalSlots = frontLen + 1 + 4;
    final unit = plateBox.width / math.max(7, totalSlots);
    final padX = math.max(unit * .45, 8.0);
    final padY = math.max(plateBox.height * .28, 8.0);
    if (slot == _PlateRecoverySlot.front) {
      add(
        Rect.fromLTRB(
          plateBox.left - padX,
          plateBox.top - padY,
          plateBox.left + unit * (frontLen + 1.35),
          plateBox.bottom + padY,
        ),
        'slotFallback',
        1.0,
      );
    } else if (slot == _PlateRecoverySlot.back) {
      add(
        Rect.fromLTRB(
          plateBox.left + unit * math.max(0.0, frontLen - .35),
          plateBox.top - padY,
          plateBox.right + padX,
          plateBox.bottom + padY,
        ),
        'slotFallback',
        1.0,
      );
    }

    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  _LocalBoundaryEvidence? _parseBoundaryLocalEvidence({
    required _PlateRecoverySlot slot,
    required String text,
    required Rect rect,
    required Uint8List bytes,
    required int ocrMs,
    required String sourceKind,
    required List<_StructuredWeakCandidate> weakCandidates,
    required _WeakPlateRegion region,
    required VoidCallback onUseLearningMid,
  }) {
    final normalized = _applyCharMap(text);
    final compact = normalized.replaceAll(RegExp(r'[^0-9가-힣]'), '');
    final relevant = weakCandidates
        .where((candidate) => candidate.back == region.back)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    String? bestFront;
    String? bestMid;
    String? bestBack;
    double bestScore = -1;

    if (slot == _PlateRecoverySlot.front) {
      final digitRuns = normalized
          .split(RegExp(r'[^0-9]+'))
          .where((value) => value.length >= 2 && value.length <= 3)
          .toSet();
      for (final candidate in relevant) {
        var score = digitRuns.contains(candidate.front) ? 3.0 : 0.0;
        String? mid;
        final frontIndex = compact.indexOf(candidate.front);
        if (frontIndex >= 0) {
          final midIndex = frontIndex + candidate.front.length;
          if (midIndex < compact.length) {
            final token = compact[midIndex];
            if (RegExp(r'[가-힣]').hasMatch(token)) {
              final normalizedMid = _normalizeMidToken(
                token,
                onUseLearningMid: onUseLearningMid,
              );
              if (_KoreanPlatePolicy.allowedNewMids.contains(normalizedMid)) {
                mid = normalizedMid;
                score += 4.0;
              }
            }
          }
        }
        if (score > bestScore) {
          bestScore = score;
          bestFront = score > 0 ? candidate.front : null;
          bestMid = mid;
        }
      }
    } else if (slot == _PlateRecoverySlot.back) {
      final digitRuns = normalized
          .split(RegExp(r'[^0-9]+'))
          .where((value) => value.length == 4)
          .toSet();
      final backCandidates = weakCandidates.map((candidate) => candidate.back).toSet();
      for (final back in backCandidates) {
        var score = digitRuns.contains(back) ? 3.0 : 0.0;
        String? mid;
        final backIndex = compact.lastIndexOf(back);
        if (backIndex >= 0 && backIndex > 0) {
          final token = compact[backIndex - 1];
          if (RegExp(r'[가-힣]').hasMatch(token)) {
            final normalizedMid = _normalizeMidToken(
              token,
              onUseLearningMid: onUseLearningMid,
            );
            if (_KoreanPlatePolicy.allowedNewMids.contains(normalizedMid)) {
              mid = normalizedMid;
              score += 4.0;
            }
          }
        }
        if (score > bestScore) {
          bestScore = score;
          bestBack = score > 0 ? back : null;
          bestMid = mid;
        }
      }
    }

    if (bestScore <= 0) return null;
    return _LocalBoundaryEvidence(
      slot: slot,
      front: bestFront,
      mid: bestMid,
      back: bestBack,
      text: text,
      rect: rect,
      bytes: bytes,
      ocrMs: ocrMs,
      sourceKind: sourceKind,
      score: bestScore,
    );
  }

  Future<_LocalBoundaryEvidence?> _runBoundaryLocalOcr({
    required String capturedPath,
    required _DecodedCapture decoded,
    required RecognizedText sourceResult,
    required _WeakPlateRegion region,
    required _StructuredWeakCandidate candidate,
    required List<_StructuredWeakCandidate> weakCandidates,
    required _PlateRecoverySlot slot,
    required VoidCallback onUseLearningMid,
    required _LocalOcrBudget budget,
    int maxAttempts = 1,
  }) async {
    String? knownMid;
    if (RegExp(r'^[가-힣]$').hasMatch(candidate.observedToken)) {
      final normalized = _KoreanPlatePolicy.staticMidNormalize[candidate.observedToken] ?? candidate.observedToken;
      if (_KoreanPlatePolicy.allowedNewMids.contains(normalized)) {
        knownMid = normalized;
      }
    }
    final anchors = _buildAdaptiveBoundaryRects(
      result: sourceResult,
      plateBox: region.box,
      imageSize: decoded.imageSize,
      slot: slot,
      frontLen: candidate.frontLen,
      front: candidate.front,
      back: candidate.back,
      mid: knownMid,
    );
    _LocalBoundaryEvidence? best;
    var tried = 0;

    for (var index = 0; index < anchors.length; index++) {
      if (!budget.canRun || tried >= maxAttempts) break;
      final anchor = anchors[index];
      final localRect = anchor.rect;
      _ocrDebugLocalSlot = slot;
      _ocrDebugLocalCropBox = localRect;
      _setOcrDebugStage(
        _OcrDebugStage.localCropPrepared,
        detail: '${slot.name}Boundary anchor=${anchor.sourceKind} rect=${_rectForLog(localRect)} budget=${budget.used}/${budget.maxAttempts}',
        structuredPlate: candidate.signature,
      );
      await _developerDebugBeat(const Duration(milliseconds: 90));
      final localStageWatch = Stopwatch()..start();

      final x = localRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
      final y = localRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
      final right = localRect.right.ceil().clamp(x + 1, decoded.image.width).toInt();
      final bottom = localRect.bottom.ceil().clamp(y + 1, decoded.image.height).toInt();
      var local = img.copyCrop(
        decoded.image,
        x: x,
        y: y,
        width: right - x,
        height: bottom - y,
      );
      local.exif.imageIfd.orientation = null;
      final scale = (360.0 / math.max(1, local.height)).clamp(1.0, 5.0).toDouble();
      if (scale > 1.02) {
        local = img.copyResize(
          local,
          width: math.max(1, (local.width * scale).round()).toInt(),
          height: math.max(1, (local.height * scale).round()).toInt(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final bytes = Uint8List.fromList(img.encodeJpg(local, quality: 98));
      final safeKind = anchor.sourceKind.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      final localPath = '$capturedPath.live_ocr_local_${slot.name}_${candidate.front}_${candidate.back}_${index}_$safeKind.jpg';
      final file = File(localPath);
      try {
        await file.writeAsBytes(bytes, flush: true);
        _ocrDebugLocalCropBytes = bytes;
        _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.midFocused;
        _ocrDebugLocalCropText = null;
        if (!budget.consume()) break;
        tried++;
        _setOcrDebugStage(
          _OcrDebugStage.localCropOcr,
          detail: '${slot.name}Boundary anchor=${anchor.sourceKind} crop=${local.width}x${local.height} budget=${budget.used}/${budget.maxAttempts}',
          structuredPlate: candidate.signature,
        );
        final watch = Stopwatch()..start();
        final localResult = await _recognizer.processImage(
          InputImage.fromFilePath(localPath),
        );
        watch.stop();
        final text = localResult.text;
        final ocrMs = watch.elapsedMilliseconds;
        budget.addOcrMs(ocrMs);
        localStageWatch.stop();
        _recordLocalStageWall(candidate.signature, localStageWatch.elapsedMilliseconds);
        _ocrDebugLocalCropText = text.replaceAll('\n', ' ');
        _ocrDebugLocalOcrMs = budget.totalOcrMs;
        final evidence = _parseBoundaryLocalEvidence(
          slot: slot,
          text: text,
          rect: localRect,
          bytes: bytes,
          ocrMs: ocrMs,
          sourceKind: anchor.sourceKind,
          weakCandidates: weakCandidates,
          region: region,
          onUseLearningMid: onUseLearningMid,
        );
        _appendLog(
          'local OCR slot=${slot.name} signature=${candidate.signature} '
          'anchor=${anchor.sourceKind} rect=${_rectForLog(localRect)} '
          'crop=${local.width}x${local.height} ocrMs=$ocrMs '
          'localWallMs=${localStageWatch.elapsedMilliseconds} '
          'localOcrTotalMs=${budget.totalOcrMs} budget=${budget.used}/${budget.maxAttempts} '
          'text=${text.replaceAll('\n', ' ')} front=${evidence?.front ?? '-'} '
          'mid=${evidence?.mid ?? '-'} back=${evidence?.back ?? '-'} score=${evidence?.score.toStringAsFixed(2) ?? '-'}',
        );
        if (evidence != null && (best == null || evidence.score > best.score)) {
          best = evidence;
        }
        if (evidence != null && evidence.score >= 7.0) {
          return evidence;
        }
      } finally {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    }
    return best;
  }

  _LocalBoundaryEvidence? _parsePartialBoundaryEvidence({
    required _PartialBoundarySeed seed,
    required String text,
    required Rect rect,
    required Uint8List bytes,
    required int ocrMs,
    required String sourceKind,
    required VoidCallback onUseLearningMid,
  }) {
    final compact = _applyCharMap(text).replaceAll(RegExp(r'[^0-9가-힣]'), '');
    if (seed.slot == _PlateRecoverySlot.front) {
      final reg = RegExp(r'(\d{2,3})([가-힣])');
      _LocalBoundaryEvidence? best;
      for (final match in reg.allMatches(compact)) {
        final front = match.group(1)!;
        final mid = _normalizeMidToken(
          match.group(2)!,
          onUseLearningMid: onUseLearningMid,
        );
        if (mid != seed.mid) continue;
        var score = 7.0;
        if (_preferredFrontLen != null && front.length == _preferredFrontLen) {
          score += .6;
        }
        final evidence = _LocalBoundaryEvidence(
          slot: seed.slot,
          front: front,
          mid: mid,
          back: seed.back,
          text: text,
          rect: rect,
          bytes: bytes,
          ocrMs: ocrMs,
          sourceKind: sourceKind,
          score: score,
        );
        if (best == null || evidence.score > best.score) best = evidence;
      }
      return best;
    }
    if (seed.slot == _PlateRecoverySlot.back) {
      final reg = RegExp(r'([가-힣])(\d{4})');
      for (final match in reg.allMatches(compact)) {
        final mid = _normalizeMidToken(
          match.group(1)!,
          onUseLearningMid: onUseLearningMid,
        );
        if (mid != seed.mid) continue;
        final back = match.group(2)!;
        return _LocalBoundaryEvidence(
          slot: seed.slot,
          front: seed.front,
          mid: mid,
          back: back,
          text: text,
          rect: rect,
          bytes: bytes,
          ocrMs: ocrMs,
          sourceKind: sourceKind,
          score: 7.0,
        );
      }
    }
    return null;
  }

  Future<_LocalBoundaryEvidence?> _runPartialBoundaryLocalOcr({
    required String capturedPath,
    required _DecodedCapture decoded,
    required RecognizedText sourceResult,
    required _PartialBoundarySeed seed,
    required VoidCallback onUseLearningMid,
    required _LocalOcrBudget budget,
  }) async {
    final anchors = _buildAdaptiveBoundaryRects(
      result: sourceResult,
      plateBox: seed.plateBox,
      imageSize: decoded.imageSize,
      slot: seed.slot,
      frontLen: seed.frontLen,
      front: seed.front,
      back: seed.back,
      mid: seed.mid,
    );
    for (var index = 0; index < anchors.length; index++) {
      if (!budget.canRun) break;
      final anchor = anchors[index];
      final localRect = anchor.rect;
      _ocrDebugWeakBox = seed.plateBox;
      _ocrDebugLocalSlot = seed.slot;
      _ocrDebugLocalCropBox = localRect;
      _setOcrDebugStage(
        _OcrDebugStage.localCropPrepared,
        detail: 'partial=${seed.slot.name} anchor=${anchor.sourceKind} rect=${_rectForLog(localRect)} budget=${budget.used}/${budget.maxAttempts}',
        structuredPlate: seed.signature,
      );
      await _developerDebugBeat(const Duration(milliseconds: 90));
      final localStageWatch = Stopwatch()..start();

      final x = localRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
      final y = localRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
      final right = localRect.right.ceil().clamp(x + 1, decoded.image.width).toInt();
      final bottom = localRect.bottom.ceil().clamp(y + 1, decoded.image.height).toInt();
      var local = img.copyCrop(
        decoded.image,
        x: x,
        y: y,
        width: right - x,
        height: bottom - y,
      );
      local.exif.imageIfd.orientation = null;
      final scale = (380.0 / math.max(1, local.height)).clamp(1.0, 5.5).toDouble();
      if (scale > 1.02) {
        local = img.copyResize(
          local,
          width: math.max(1, (local.width * scale).round()).toInt(),
          height: math.max(1, (local.height * scale).round()).toInt(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final bytes = Uint8List.fromList(img.encodeJpg(local, quality: 98));
      final safeKind = anchor.sourceKind.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      final path = '$capturedPath.live_ocr_partial_${seed.slot.name}_${index}_$safeKind.jpg';
      final file = File(path);
      try {
        await file.writeAsBytes(bytes, flush: true);
        _ocrDebugLocalCropBytes = bytes;
        _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.midFocused;
        _ocrDebugLocalCropText = null;
        if (!budget.consume()) break;
        _setOcrDebugStage(
          _OcrDebugStage.localCropOcr,
          detail: 'partial=${seed.slot.name} anchor=${anchor.sourceKind} crop=${local.width}x${local.height} budget=${budget.used}/${budget.maxAttempts}',
          structuredPlate: seed.signature,
        );
        final watch = Stopwatch()..start();
        final result = await _recognizer.processImage(InputImage.fromFilePath(path));
        watch.stop();
        final text = result.text;
        final ocrMs = watch.elapsedMilliseconds;
        budget.addOcrMs(ocrMs);
        localStageWatch.stop();
        _recordLocalStageWall(seed.signature, localStageWatch.elapsedMilliseconds);
        _ocrDebugLocalCropText = text.replaceAll('\n', ' ');
        _ocrDebugLocalOcrMs = budget.totalOcrMs;
        final evidence = _parsePartialBoundaryEvidence(
          seed: seed,
          text: text,
          rect: localRect,
          bytes: bytes,
          ocrMs: ocrMs,
          sourceKind: anchor.sourceKind,
          onUseLearningMid: onUseLearningMid,
        );
        _appendLog(
          'partial local OCR slot=${seed.slot.name} signature=${seed.signature} '
          'anchor=${anchor.sourceKind} rect=${_rectForLog(localRect)} '
          'ocrMs=$ocrMs localWallMs=${localStageWatch.elapsedMilliseconds} '
          'localOcrTotalMs=${budget.totalOcrMs} '
          'budget=${budget.used}/${budget.maxAttempts} text=${text.replaceAll('\n', ' ')} '
          'front=${evidence?.front ?? '-'} mid=${evidence?.mid ?? '-'} back=${evidence?.back ?? '-'}',
        );
        if (evidence != null) return evidence;
      } finally {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    }
    return null;
  }

  Future<_CropRecoveryOutcome?> _tryRecoverPartialBoundaryCases({
    required String capturedPath,
    required RecognizedText result,
    required List<_PartialBoundarySeed> seeds,
    required _DecodedCapture? decodedCapture,
    required VoidCallback onUseLearningMid,
  }) async {
    if (seeds.isEmpty) return null;
    final recoveryWatch = Stopwatch()..start();
    _ocrDebugRecoveryWallMs = null;
    final decoded = decodedCapture ?? await _decodeCaptureForGeometry(capturedPath, result);
    if (decoded == null) {
      recoveryWatch.stop();
      _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
      return null;
    }
    if (!decoded.geometryReliable) {
      recoveryWatch.stop();
      _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
      _appendLog(
        'partial recovery 생략 geometry unreliable '
        'decodedFits=${decoded.decodedFits} bakedFits=${decoded.bakedFits} '
        'wallMs=${recoveryWatch.elapsedMilliseconds}',
      );
      return null;
    }
    final budget = _LocalOcrBudget(maxAttempts: 1);
    final seenSlots = <_PlateRecoverySlot>{};
    for (final seed in seeds) {
      if (!budget.canRun) break;
      if (!seenSlots.add(seed.slot) && seeds.length > 1) continue;
      final localLatencyAllowed = _localRecoveryFitsLatencyBudget(seed.signature);
      _appendLog(
        'partial recovery seed slot=${seed.slot.name} signature=${seed.signature} '
        'source=${seed.sourceKind} text=${seed.sourceText.replaceAll('\n', ' ')} '
        'budget=${budget.used}/${budget.maxAttempts} '
        'latencyAllowed=$localLatencyAllowed nextFrameEstimateMs=$_estimatedNextFrameWallMs',
      );
      if (!localLatencyAllowed) {
        _appendLog(
          'partial recovery latency skip signature=${seed.signature} '
          'lastLocalWallMs=${_lastLocalStageWallMs ?? '-'}',
        );
        continue;
      }
      _markHeavyRecovery(seed.signature);
      final evidence = await _runPartialBoundaryLocalOcr(
        capturedPath: capturedPath,
        decoded: decoded,
        sourceResult: result,
        seed: seed,
        onUseLearningMid: onUseLearningMid,
        budget: budget,
      );
      if (evidence == null) continue;
      String? plate;
      if (seed.slot == _PlateRecoverySlot.front &&
          evidence.front != null &&
          seed.back != null &&
          evidence.mid == seed.mid) {
        plate = '${evidence.front}${seed.mid}${seed.back}';
      } else if (seed.slot == _PlateRecoverySlot.back &&
          seed.front != null &&
          evidence.back != null &&
          evidence.mid == seed.mid) {
        plate = '${seed.front}${seed.mid}${evidence.back}';
      }
      if (plate == null || !_isModernPlate(plate)) continue;
      _ocrDebugLocalOcrMs = budget.totalOcrMs;
      recoveryWatch.stop();
      _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
      return _CropRecoveryOutcome(
        signature: seed.signature,
        plate: plate,
        cropText: 'LOCAL ${evidence.text.replaceAll('\n', ' ')}',
        sourceRegion: seed.plateBox,
        cropRegion: evidence.rect,
        sourceImageSize: decoded.imageSize,
        cropBytes: evidence.bytes,
        focusPoint: _normalizedFocusPoint(seed.plateBox, decoded.imageSize),
        cropOcrMs: budget.totalOcrMs,
        recoveryWallMs: recoveryWatch.elapsedMilliseconds,
        allowRefocus: false,
      );
    }
    _ocrDebugLocalOcrMs = budget.totalOcrMs == 0 ? null : budget.totalOcrMs;
    recoveryWatch.stop();
    _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
    _appendLog(
      'partial recovery 실패 seeds=${seeds.length} localOcrTotalMs=${budget.totalOcrMs} '
      'budget=${budget.used}/${budget.maxAttempts} wallMs=${recoveryWatch.elapsedMilliseconds}',
    );
    return null;
  }

  String? _fuseBoundaryRecovery({
    required _WeakPlateRegion region,
    required List<_StructuredWeakCandidate> weakCandidates,
    required _LocalBoundaryEvidence evidence,
  }) {
    final storedMid = _bestLocalMidEvidence(region.front, region.back);
    final trustedStoredMid = storedMid != null && storedMid.votes >= 2
        ? storedMid.mid
        : null;
    if (evidence.mid == null && storedMid != null && storedMid.votes < 2) {
      _appendLog(
        'local mid evidence 자동확정 보류 key=${_localEvidenceKey(region.front, region.back)} '
        'mid=${storedMid.mid} votes=${storedMid.votes}',
      );
    }
    final mid = evidence.mid ?? trustedStoredMid;
    if (mid == null) return null;
    if (evidence.slot == _PlateRecoverySlot.front && evidence.front != null) {
      final supported = weakCandidates.any(
        (candidate) =>
            candidate.front == evidence.front && candidate.back == region.back,
      );
      if (!supported) return null;
      final plate = '${evidence.front}$mid${region.back}';
      return _isModernPlate(plate) ? plate : null;
    }
    if (evidence.slot == _PlateRecoverySlot.back && evidence.back != null) {
      final resolvedFront = _resolveFrontFromEvidence(
        evidence.back!,
        weakCandidates,
      );
      if (resolvedFront == null) return null;
      final plate = '$resolvedFront$mid${evidence.back}';
      return _isModernPlate(plate) ? plate : null;
    }
    return null;
  }

  List<double>? _solveLinear8(List<List<double>> a, List<double> b) {
    final n = 8;
    final m = List.generate(
      n,
      (r) => <double>[...a[r], b[r]],
      growable: false,
    );
    for (var col = 0; col < n; col++) {
      var pivot = col;
      var pivotValue = m[pivot][col].abs();
      for (var row = col + 1; row < n; row++) {
        final value = m[row][col].abs();
        if (value > pivotValue) {
          pivot = row;
          pivotValue = value;
        }
      }
      if (pivotValue < 1e-9) return null;
      if (pivot != col) {
        final tmp = m[col];
        m[col] = m[pivot];
        m[pivot] = tmp;
      }
      final divisor = m[col][col];
      for (var j = col; j <= n; j++) {
        m[col][j] /= divisor;
      }
      for (var row = 0; row < n; row++) {
        if (row == col) continue;
        final factor = m[row][col];
        if (factor.abs() < 1e-12) continue;
        for (var j = col; j <= n; j++) {
          m[row][j] -= factor * m[col][j];
        }
      }
    }
    return List<double>.generate(n, (i) => m[i][n], growable: false);
  }

  List<double>? _homographyDestinationToSource(
    List<Offset> destination,
    List<Offset> source,
  ) {
    if (destination.length != 4 || source.length != 4) return null;
    final a = <List<double>>[];
    final b = <double>[];
    for (var i = 0; i < 4; i++) {
      final x = destination[i].dx;
      final y = destination[i].dy;
      final u = source[i].dx;
      final v = source[i].dy;
      a.add([x, y, 1, 0, 0, 0, -u * x, -u * y]);
      b.add(u);
      a.add([0, 0, 0, x, y, 1, -v * x, -v * y]);
      b.add(v);
    }
    return _solveLinear8(a, b);
  }

  num _lerpNum(num a, num b, double t) => a + (b - a) * t;

  ({num r, num g, num b, num a}) _sampleBilinear(
    img.Image source,
    double x,
    double y,
  ) {
    final cx = x.clamp(0.0, math.max(0.0, source.width - 1)).toDouble();
    final cy = y.clamp(0.0, math.max(0.0, source.height - 1)).toDouble();
    final x0 = cx.floor();
    final y0 = cy.floor();
    final x1 = math.min(source.width - 1, x0 + 1);
    final y1 = math.min(source.height - 1, y0 + 1);
    final tx = cx - x0;
    final ty = cy - y0;
    final p00 = source.getPixel(x0, y0);
    final p10 = source.getPixel(x1, y0);
    final p01 = source.getPixel(x0, y1);
    final p11 = source.getPixel(x1, y1);
    num channel(num a00, num a10, num a01, num a11) {
      final top = _lerpNum(a00, a10, tx);
      final bottom = _lerpNum(a01, a11, tx);
      return _lerpNum(top, bottom, ty);
    }
    return (
      r: channel(p00.r, p10.r, p01.r, p11.r),
      g: channel(p00.g, p10.g, p01.g, p11.g),
      b: channel(p00.b, p10.b, p01.b, p11.b),
      a: channel(p00.a, p10.a, p01.a, p11.a),
    );
  }

  img.Image? _rectifyPlatePerspective(
    img.Image source,
    _PlateQuad quad,
  ) {
    final sourceSize = Size(source.width.toDouble(), source.height.toDouble());
    final q = quad.clampTo(sourceSize);
    final averageWidth = (q.topLength + q.bottomLength) / 2;
    final averageHeight = (q.leftLength + q.rightLength) / 2;
    if (averageWidth < 20 || averageHeight < 8) return null;
    final aspect = (averageWidth / averageHeight).clamp(2.6, 6.4).toDouble();
    const targetHeight = 300;
    final targetWidth = (targetHeight * aspect).round().clamp(360, 1920).toInt();
    final destination = <Offset>[
      Offset.zero,
      Offset((targetWidth - 1).toDouble(), 0),
      Offset((targetWidth - 1).toDouble(), (targetHeight - 1).toDouble()),
      Offset(0, (targetHeight - 1).toDouble()),
    ];
    final sourcePoints = <Offset>[
      q.topLeft,
      q.topRight,
      q.bottomRight,
      q.bottomLeft,
    ];
    final h = _homographyDestinationToSource(destination, sourcePoints);
    if (h == null) return null;
    final output = img.Image(width: targetWidth, height: targetHeight);
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final denominator = h[6] * x + h[7] * y + 1;
        if (denominator.abs() < 1e-9) continue;
        final sx = (h[0] * x + h[1] * y + h[2]) / denominator;
        final sy = (h[3] * x + h[4] * y + h[5]) / denominator;
        final pixel = _sampleBilinear(source, sx, sy);
        output.setPixelRgba(
          x,
          y,
          pixel.r.round(),
          pixel.g.round(),
          pixel.b.round(),
          pixel.a.round(),
        );
      }
    }
    output.exif.imageIfd.orientation = null;
    return output;
  }

  String _quadForLog(_PlateQuad quad) {
    String point(Offset p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}';
    return '${point(quad.topLeft)}|${point(quad.topRight)}|${point(quad.bottomRight)}|${point(quad.bottomLeft)}';
  }

  Future<_CropRecoveryOutcome?> _tryRecoverFromDynamicCrop({
    required String capturedPath,
    required RecognizedText result,
    required List<_StructuredWeakCandidate> weakCandidates,
    required _DecodedCapture? decodedCapture,
    required VoidCallback onUseLearningMid,
    bool fastMidOnly = false,
  }) async {
    String? tempCropPath;
    final recoveryWatch = Stopwatch()..start();
    try {
      _ocrDebugRecoveryWallMs = null;
      _ocrDebugLocalCropBox = null;
      _ocrDebugMidContextBox = null;
      _ocrDebugMidLeftBox = null;
      _ocrDebugMidGlyphBox = null;
      _ocrDebugMidRightBox = null;
      _ocrDebugLocalSlot = null;
      _ocrDebugSourcePlateBytes = null;
      _ocrDebugRectifiedPlateBytes = null;
      _ocrDebugLocalCropBytes = null;
      _ocrDebugMidContextBytes = null;
      _ocrDebugMidGlyphBytes = null;
      _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.none;
      _ocrDebugLocalCropText = null;
      _ocrDebugMidAnchorStatus = null;
      _ocrDebugMidGlyphText = null;
      _ocrDebugMidContextText = null;
      _ocrDebugLocalOcrMs = null;
      _ocrDebugLocalWallMs = null;
      final decoded = decodedCapture ??
          await _decodeCaptureForGeometry(capturedPath, result);
      if (decoded == null) {
        recoveryWatch.stop();
        _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
        _appendLog('동적 crop 복구 생략 image decode 실패 wallMs=${recoveryWatch.elapsedMilliseconds}');
        return null;
      }
      if (!decoded.geometryReliable) {
        recoveryWatch.stop();
        _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
        _appendLog(
          '동적 crop 복구 생략 geometry unreliable '
          'decodedFits=${decoded.decodedFits} bakedFits=${decoded.bakedFits} '
          'wallMs=${recoveryWatch.elapsedMilliseconds}',
        );
        return null;
      }

      final region = _findWeakPlateRegion(result, weakCandidates);
      if (region == null) {
        recoveryWatch.stop();
        _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
        _appendLog(
          '동적 crop 복구 생략 weak region 미검출 '
              'candidates=${_joinForLog(weakCandidates.map((e) => e.signature).toList())} '
              'wallMs=${recoveryWatch.elapsedMilliseconds}',
        );
        _setOcrDebugStage(
          _OcrDebugStage.fallback,
          detail: 'weakRegionNotFound',
          structuredPlate: weakCandidates.first.signature,
        );
        return null;
      }

      _markHeavyRecovery(region.signature);
      if (fastMidOnly) {
        _fastRecoveryExecutedIdentities.add(region.signature);
      }
      _ocrDebugSourceImageSize = decoded.imageSize;
      _ocrDebugWeakBox = region.box;
      _ocrDebugStructuredPlate = region.signature;
      _setOcrDebugStage(
        _OcrDebugStage.weakPlateDetected,
        detail: 'line=${region.sourceText.replaceAll('\n', ' ')}',
        structuredPlate: region.signature,
      );
      await _developerDebugBeat();
      _appendLog(
        'weak region 발견 signature=${region.signature} sourceKind=${region.sourceKind} '
            'box=${_rectForLog(region.box)} sourceText=${region.sourceText.replaceAll('\n', ' ')}',
      );

      final cropRect = _expandWeakPlateRect(region.box, decoded.imageSize);
      _ocrDebugCropBox = cropRect;
      _ocrDebugPerspectiveQuad = region.quad;
      _ocrDebugPerspectiveAngle = region.quad?.angleDegrees;
      _ocrDebugRectifiedSize = null;
      _ocrDebugPerspectiveText = null;
      _setOcrDebugStage(
        _OcrDebugStage.cropPrepared,
        detail: _rectForLog(cropRect),
        structuredPlate: region.signature,
      );
      await _developerDebugBeat();

      final x = cropRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
      final y = cropRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
      final right = cropRect.right.ceil().clamp(x + 1, decoded.image.width).toInt();
      final bottom = cropRect.bottom.ceil().clamp(y + 1, decoded.image.height).toInt();
      final width = right - x;
      final height = bottom - y;

      var sourcePreview = img.copyCrop(
        decoded.image,
        x: x,
        y: y,
        width: width,
        height: height,
      );
      sourcePreview.exif.imageIfd.orientation = null;
      final sourcePreviewBytes = Uint8List.fromList(
        img.encodeJpg(sourcePreview, quality: 92),
      );
      _ocrDebugSourcePlateBytes = sourcePreviewBytes;
      _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.plateDetected;
      _ocrDebugRevision++;
      if (mounted) {
        setState(() {});
      }
      var perspectiveApplied = false;
      img.Image? rectified;
      if (region.quad != null && decoded.geometryReliable) {
        rectified = _rectifyPlatePerspective(decoded.image, region.quad!);
      }
      var crop = rectified ?? sourcePreview;
      crop.exif.imageIfd.orientation = null;
      perspectiveApplied = rectified != null;
      _ocrDebugPerspectiveApplied = perspectiveApplied;

      if (!perspectiveApplied) {
        final targetHeight = 300.0;
        final scale = (targetHeight / math.max(1, crop.height))
            .clamp(1.0, 4.0)
            .toDouble();
        if (scale > 1.04) {
          crop = img.copyResize(
            crop,
            width: math.max(1, (crop.width * scale).round()).toInt(),
            height: math.max(1, (crop.height * scale).round()).toInt(),
            interpolation: img.Interpolation.cubic,
          );
        }
      }
      _ocrDebugRectifiedSize = perspectiveApplied
          ? Size(crop.width.toDouble(), crop.height.toDouble())
          : null;
      if (perspectiveApplied) {
        _appendLog(
          'perspective 적용 signature=${region.signature} '
          'angle=${region.quad!.angleDegrees.toStringAsFixed(1)} '
          'quad=${_quadForLog(region.quad!)} '
          'rectified=${crop.width}x${crop.height}',
        );
      } else {
        _appendLog(
          'perspective fallback signature=${region.signature} '
          'reason=${region.quad == null ? 'quadUnavailable' : decoded.geometryReliable ? 'rectifyFailed' : 'geometryUnreliable'}',
        );
      }

      final cropBytes = Uint8List.fromList(
        img.encodeJpg(crop, quality: 96),
      );
      _ocrDebugRectifiedPlateBytes = perspectiveApplied ? cropBytes : null;
      _ocrRecoveryPreviewPhase = perspectiveApplied
          ? _OcrRecoveryPreviewPhase.plateRectified
          : _OcrRecoveryPreviewPhase.plateDetected;
      _ocrDebugRevision++;
      if (mounted) {
        setState(() {});
      }
      final cropPath = '$capturedPath.live_ocr_crop.jpg';
      tempCropPath = cropPath;
      await File(cropPath).writeAsBytes(cropBytes, flush: true);

      _ocrDebugCropBytes = cropBytes;
      _ocrDebugCropText = null;
      _ocrDebugCropOcrMs = null;
      _setOcrDebugStage(
        _OcrDebugStage.cropOcr,
        detail: 'crop=${crop.width}x${crop.height}',
        structuredPlate: region.signature,
      );

      final cropInput = InputImage.fromFilePath(cropPath);
      final cropWatch = Stopwatch()..start();
      final cropResult = await _recognizer.processImage(cropInput);
      cropWatch.stop();
      final cropFile = File(cropPath);
      if (cropFile.existsSync()) {
        cropFile.deleteSync();
      }
      tempCropPath = null;
      final cropText = cropResult.text;
      final cropOcrMs = cropWatch.elapsedMilliseconds;
      _ocrDebugCropText = cropText.replaceAll('\n', ' ');
      _ocrDebugPerspectiveText = perspectiveApplied
          ? cropText.replaceAll('\n', ' ')
          : null;
      _ocrDebugCropOcrMs = cropOcrMs;

      final expected = weakCandidates.firstWhere(
            (candidate) => candidate.signature == region.signature,
        orElse: () => weakCandidates.first,
      );
      var plate = _recoverExpectedModernPlateFromCrop(
        cropResult: cropResult,
        cropText: cropText,
        cropImageSize: Size(crop.width.toDouble(), crop.height.toDouble()),
        expected: expected,
        expectedCandidates: weakCandidates,
        onUseLearningMid: onUseLearningMid,
      );
      _MicroCropRecovery? microRecovery;
      _LocalBoundaryEvidence? boundaryRecovery;
      final localBudget = _LocalOcrBudget(maxAttempts: 2);
      final uncertainty = _analyzeSlotUncertainty(
        region: region,
        weakCandidates: weakCandidates,
      );
      final localLatencyAllowed = _localRecoveryFitsLatencyBudget(region.signature);
      _appendLog(
        'local recovery plan front=${uncertainty.front} '
            'mid=${uncertainty.mid} back=${uncertainty.back} '
            'signature=${region.signature} fastMidOnly=$fastMidOnly '
            'baseBudget=1 conditionalMax=${localBudget.maxAttempts} '
            'latencyAllowed=$localLatencyAllowed '
            'lastLocalWallMs=${_lastLocalStageSignature == region.signature ? (_lastLocalStageWallMs ?? '-') : '-'} '
            'nextFrameEstimateMs=$_estimatedNextFrameWallMs',
      );

      List<_StructuredWeakCandidate> rankedForBack(String back) {
        final ranked = weakCandidates
            .where((candidate) => candidate.back == back)
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));
        return ranked;
      }

      Future<void> runMidOnce() async {
        if (plate != null ||
            !uncertainty.mid ||
            !localBudget.canRun ||
            !localLatencyAllowed) {
          return;
        }
        microRecovery = await _tryRecoverFromMidContextMicroCrops(
          capturedPath: capturedPath,
          decoded: decoded,
          sourceResult: result,
          region: region,
          weakCandidates: weakCandidates,
          onUseLearningMid: onUseLearningMid,
          budget: localBudget,
          maxAttempts: 1,
        );
        plate = microRecovery?.plate;
      }

      Future<void> runBoundaryOnce(_PlateRecoverySlot slot) async {
        if (plate != null || !localBudget.canRun) return;
        final ranked = slot == _PlateRecoverySlot.front
            ? rankedForBack(region.back)
            : (List<_StructuredWeakCandidate>.from(weakCandidates)
              ..sort((a, b) => b.score.compareTo(a.score)));
        if (ranked.isEmpty) return;
        boundaryRecovery = await _runBoundaryLocalOcr(
          capturedPath: capturedPath,
          decoded: decoded,
          sourceResult: result,
          region: region,
          candidate: ranked.first,
          weakCandidates: weakCandidates,
          slot: slot,
          onUseLearningMid: onUseLearningMid,
          budget: localBudget,
          maxAttempts: 1,
        );
        if (boundaryRecovery != null) {
          plate = _fuseBoundaryRecovery(
            region: region,
            weakCandidates: weakCandidates,
            evidence: boundaryRecovery!,
          );
        }
      }

      if (plate == null && uncertainty.mid) {
        if (!localLatencyAllowed) {
          _appendLog(
            'local recovery latency skip signature=${region.signature} '
            'lastLocalWallMs=${_lastLocalStageWallMs ?? '-'} '
            'nextFrameEstimateMs=$_estimatedNextFrameWallMs',
          );
        }
        await runMidOnce();
      }

      final canUseConditionalSecond = !fastMidOnly &&
          plate == null &&
          microRecovery?.hasUsefulEvidence == true &&
          localBudget.canRun &&
          _localRecoveryFitsLatencyBudget(region.signature);
      if (canUseConditionalSecond && uncertainty.front) {
        _appendLog(
          'local 2차 조건부 허용 signature=${region.signature} '
          'reason=validMidEvidence target=front',
        );
        await runBoundaryOnce(_PlateRecoverySlot.front);
      } else if (canUseConditionalSecond && uncertainty.back) {
        _appendLog(
          'local 2차 조건부 허용 signature=${region.signature} '
          'reason=validMidEvidence target=back',
        );
        await runBoundaryOnce(_PlateRecoverySlot.back);
      }

      if (plate == null && localBudget.used >= 1 &&
          microRecovery?.hasUsefulEvidence != true) {
        _appendLog(
          'local 2차 중단 signature=${region.signature} '
          'reason=noUsefulFirstLocalEvidence budget=${localBudget.used}/${localBudget.maxAttempts}',
        );
      }
      final focusPoint = _normalizedFocusPoint(region.box, decoded.imageSize);
      final localTexts = <String>[];
      if (boundaryRecovery?.text.isNotEmpty == true) {
        localTexts.add(boundaryRecovery!.text.replaceAll('\n', ' '));
      }
      if (microRecovery?.text.isNotEmpty == true &&
          !localTexts.contains(microRecovery!.text.replaceAll('\n', ' '))) {
        localTexts.add(microRecovery!.text.replaceAll('\n', ' '));
      }
      final combinedText = localTexts.isEmpty
          ? cropText
          : '$cropText | LOCAL ${localTexts.join(' | ')}';
      final combinedOcrMs = cropOcrMs + localBudget.totalOcrMs;
      _ocrDebugLocalOcrMs = localBudget.totalOcrMs == 0
          ? null
          : localBudget.totalOcrMs;
      recoveryWatch.stop();
      _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
      final midOnlyUncertain =
          !uncertainty.front && uncertainty.mid && !uncertainty.back;

      _appendLog(
        'crop OCR signature=${region.signature} '
            'sourceBox=${_rectForLog(region.box)} cropBox=${_rectForLog(cropRect)} '
            'cropSize=${crop.width}x${crop.height} cropOcrMs=$cropOcrMs '
            'localOcrMs=${localBudget.totalOcrMs} wallMs=${recoveryWatch.elapsedMilliseconds} '
            'cropText=${cropText.replaceAll('\n', ' ')} plate=${plate ?? '-'}',
      );

      if (_developerMode && mounted) {
        _ocrDebugRevision++;
        setState(() {});
      }

      return _CropRecoveryOutcome(
        signature: microRecovery?.signature ?? region.signature,
        plate: plate,
        cropText: combinedText,
        sourceRegion: region.box,
        cropRegion: boundaryRecovery?.rect ?? microRecovery?.rect ?? cropRect,
        sourceImageSize: decoded.imageSize,
        cropBytes: boundaryRecovery?.bytes ?? microRecovery?.bytes ?? cropBytes,
        focusPoint: focusPoint,
        cropOcrMs: combinedOcrMs,
        recoveryWallMs: recoveryWatch.elapsedMilliseconds,
        allowRefocus: !fastMidOnly && !midOnlyUncertain,
      );
    } catch (e, stackTrace) {
      if (tempCropPath != null) {
        try {
          final cropFile = File(tempCropPath);
          if (cropFile.existsSync()) {
            cropFile.deleteSync();
          }
        } catch (_) {}
      }
      if (recoveryWatch.isRunning) recoveryWatch.stop();
      _ocrDebugRecoveryWallMs = recoveryWatch.elapsedMilliseconds;
      _appendLog('동적 crop 복구 오류 $e wallMs=${recoveryWatch.elapsedMilliseconds}');
      _appendLog('동적 crop stack=$stackTrace');
      _setOcrDebugStage(
        _OcrDebugStage.fallback,
        detail: 'cropError:$e',
        structuredPlate:
        weakCandidates.isEmpty ? null : weakCandidates.first.signature,
      );
      return null;
    }
  }

  _MidRecoveryLayout _buildSlotMidRecoveryLayout({
    required Rect plateBox,
    required _StructuredWeakCandidate candidate,
    required Size imageSize,
  }) {
    final totalSlots = candidate.frontLen + 1 + 4;
    final safeSlots = math.max(7, totalSlots);
    final charWidth = plateBox.width / safeSlots;
    final slotTop = plateBox.top - math.max(plateBox.height * .10, 4.0);
    final slotBottom = plateBox.bottom + math.max(plateBox.height * .10, 4.0);

    Rect slotRect(int slotIndex, double widthFactor) {
      final centerRatio = (slotIndex + .5) / totalSlots;
      final centerX = plateBox.left + (plateBox.width * centerRatio);
      final halfWidth = charWidth * widthFactor * .5;
      return _clampRecoveryRect(
        Rect.fromLTRB(
          centerX - halfWidth,
          slotTop,
          centerX + halfWidth,
          slotBottom,
        ),
        imageSize,
      );
    }

    final leftAnchorRect = slotRect(candidate.frontLen - 1, 1.08);
    final glyphRect = slotRect(candidate.frontLen, 1.18);
    final rightAnchorRect = slotRect(candidate.frontLen + 1, 1.08);
    final contextCenterX = glyphRect.center.dx;
    final halfWidth = math.max(charWidth * 1.65, plateBox.height * .65);
    final padY = math.max(plateBox.height * .22, 8.0);
    final contextRect = _clampRecoveryRect(
      Rect.fromLTRB(
        contextCenterX - halfWidth,
        plateBox.top - padY,
        contextCenterX + halfWidth,
        plateBox.bottom + padY,
      ),
      imageSize,
    );
    return _MidRecoveryLayout(
      contextRect: contextRect,
      leftAnchorRect: leftAnchorRect,
      glyphRect: glyphRect,
      rightAnchorRect: rightAnchorRect,
      sourceKind: 'slotFallback',
      geometryBacked: false,
    );
  }

  Rect _subCharacterBox(
      Rect box,
      int characterCount,
      int characterIndex,
      ) {
    final count = math.max(1, characterCount).toInt();
    final index = characterIndex.clamp(0, count - 1).toInt();
    final width = box.width / count;
    return Rect.fromLTRB(
      box.left + width * index,
      box.top,
      box.left + width * (index + 1),
      box.bottom,
    );
  }

  _MidRecoveryLayout? _findAdaptiveMidLayout({
    required RecognizedText result,
    required _WeakPlateRegion region,
    required _StructuredWeakCandidate candidate,
    required Size imageSize,
  }) {
    final options = <({ _MidRecoveryLayout layout, double score})>[];
    final searchPad = math.max(region.box.height * 1.3, 28.0);
    final searchRect = Rect.fromLTRB(
      region.box.left - searchPad,
      region.box.top - searchPad,
      region.box.right + searchPad,
      region.box.bottom + searchPad,
    );

    void addPair(Rect frontBox, Rect backBox, String kind, double bonus) {
      if (frontBox.width <= 0 ||
          frontBox.height <= 0 ||
          backBox.width <= 0 ||
          backBox.height <= 0) {
        return;
      }
      final meanHeight = (frontBox.height + backBox.height) / 2;
      final verticalDelta = (frontBox.center.dy - backBox.center.dy).abs();
      if (verticalDelta > math.max(meanHeight * .9, 18.0)) return;
      final frontUnit = frontBox.width / math.max(1, candidate.front.length);
      final backUnit = backBox.width / math.max(1, candidate.back.length);
      final unit = math.max(4.0, (frontUnit + backUnit) / 2).toDouble();
      final leftDigit = _subCharacterBox(
        frontBox,
        candidate.front.length,
        candidate.front.length - 1,
      );
      final rightDigit = _subCharacterBox(backBox, candidate.back.length, 0);
      final gap = rightDigit.left - leftDigit.right;
      if (gap < -unit * .8 || gap > unit * 3.4) return;
      final midCenterX = gap >= 0
          ? (leftDigit.right + rightDigit.left) / 2
          : (leftDigit.center.dx + rightDigit.center.dx) / 2;
      final verticalUnion = Rect.fromLTRB(
        math.min(frontBox.left, backBox.left),
        math.min(frontBox.top, backBox.top),
        math.max(frontBox.right, backBox.right),
        math.max(frontBox.bottom, backBox.bottom),
      );
      final contextHalfWidth = math.max(unit * 1.85, meanHeight * .72);
      final contextPadY = math.max(verticalUnion.height * .32, 8.0);
      final glyphHalfWidth = math.max(unit * .60, meanHeight * .34);
      final glyphPadY = math.max(verticalUnion.height * .14, 4.0);
      final contextRect = _clampRecoveryRect(
        Rect.fromLTRB(
          midCenterX - contextHalfWidth,
          verticalUnion.top - contextPadY,
          midCenterX + contextHalfWidth,
          verticalUnion.bottom + contextPadY,
        ),
        imageSize,
      );
      final glyphRect = _clampRecoveryRect(
        Rect.fromLTRB(
          midCenterX - glyphHalfWidth,
          verticalUnion.top - glyphPadY,
          midCenterX + glyphHalfWidth,
          verticalUnion.bottom + glyphPadY,
        ),
        imageSize,
      );
      final regionDistance = (contextRect.center - region.box.center).distance;
      final score = bonus -
          verticalDelta * .02 -
          regionDistance * .001 -
          gap.abs() * .002;
      options.add((
        layout: _MidRecoveryLayout(
          contextRect: contextRect,
          leftAnchorRect: _clampRecoveryRect(leftDigit, imageSize),
          glyphRect: glyphRect,
          rightAnchorRect: _clampRecoveryRect(rightDigit, imageSize),
          sourceKind: kind,
          geometryBacked: true,
        ),
        score: score,
      ));
    }

    for (final block in result.blocks) {
      for (final line in block.lines) {
        final lineBox = line.boundingBox;
        if (!searchRect.overlaps(lineBox) &&
            !searchRect.contains(lineBox.center)) {
          continue;
        }
        final frontElements = <TextElement>[];
        final backElements = <TextElement>[];
        for (final element in line.elements) {
          final normalized = _normalizeWeakSource(element.text);
          final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits == candidate.front) {
            frontElements.add(element);
          }
          if (digits == candidate.back) {
            backElements.add(element);
          }
        }
        for (final frontElement in frontElements) {
          for (final backElement in backElements) {
            if (identical(frontElement, backElement)) continue;
            addPair(
              frontElement.boundingBox,
              backElement.boundingBox,
              'elementPair',
              4.0,
            );
          }
        }

        final frontSpan = _estimatedLiteralSpanBox(line, candidate.front);
        final backSpan = _estimatedLiteralSpanBox(line, candidate.back);
        if (frontSpan != null && backSpan != null) {
          final normalized = _normalizeWeakSource(line.text);
          final compactLength = normalized.replaceAll(' ', '').length;
          if (compactLength > candidate.front.length + candidate.back.length + 2) {
            continue;
          }
          final frontIndex = normalized.indexOf(candidate.front);
          final backIndex = normalized.lastIndexOf(candidate.back);
          if (frontIndex >= 0 &&
              backIndex >= frontIndex + candidate.front.length) {
            final between = normalized.substring(
              frontIndex + candidate.front.length,
              backIndex,
            );
            if (between.isNotEmpty) {
              addPair(frontSpan, backSpan, 'lineAnchors', 2.6);
            }
          }
        }
      }
    }

    final frontLines = <TextLine>[];
    final backLines = <TextLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final lineBox = line.boundingBox;
        if (!searchRect.overlaps(lineBox) &&
            !searchRect.contains(lineBox.center)) {
          continue;
        }
        final normalized = _normalizeWeakSource(line.text);
        final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.contains(candidate.front)) frontLines.add(line);
        if (digits.contains(candidate.back)) backLines.add(line);
      }
    }
    for (final frontLine in frontLines) {
      for (final backLine in backLines) {
        if (identical(frontLine, backLine)) continue;
        final frontBox =
            _estimatedLiteralSpanBox(frontLine, candidate.front) ??
                frontLine.boundingBox;
        final backBox = _estimatedLiteralSpanBox(backLine, candidate.back) ??
            backLine.boundingBox;
        addPair(frontBox, backBox, 'adjacentLineAnchors', 1.8);
      }
    }

    if (options.isEmpty) return null;
    options.sort((a, b) => b.score.compareTo(a.score));
    return options.first.layout;
  }

  _MidRecoveryLayout _buildMidRecoveryLayout({
    required RecognizedText result,
    required Rect plateBox,
    required _WeakPlateRegion region,
    required _StructuredWeakCandidate candidate,
    required Size imageSize,
  }) {
    return _findAdaptiveMidLayout(
          result: result,
          region: region,
          candidate: candidate,
          imageSize: imageSize,
        ) ??
        _buildSlotMidRecoveryLayout(
          plateBox: plateBox,
          candidate: candidate,
          imageSize: imageSize,
        );
  }

  ({String? digit, double score}) _bestDigitObservationForRect(
    RecognizedText result,
    Rect target,
  ) {
    String? bestDigit;
    var bestScore = -double.infinity;
    final targetArea = math.max(1.0, target.width * target.height);
    final targetScale = math.max(1.0, math.max(target.width, target.height));
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final runes = element.text.runes.toList(growable: false);
          if (runes.isEmpty || element.boundingBox.width <= 0 || element.boundingBox.height <= 0) {
            continue;
          }
          for (var index = 0; index < runes.length; index++) {
            final char = String.fromCharCode(runes[index]);
            if (!RegExp(r'[0-9]').hasMatch(char)) continue;
            final charBox = _subCharacterBox(
              element.boundingBox,
              runes.length,
              index,
            );
            final intersection = target.intersect(charBox);
            final intersectionArea = intersection.width > 0 && intersection.height > 0
                ? intersection.width * intersection.height
                : 0.0;
            final charArea = math.max(1.0, charBox.width * charBox.height);
            final overlap = intersectionArea / math.min(targetArea, charArea);
            final distance = (charBox.center - target.center).distance / targetScale;
            final score = overlap * 2.2 - distance * .35;
            if (score > bestScore) {
              bestScore = score;
              bestDigit = char;
            }
          }
        }
      }
    }
    return (digit: bestDigit, score: bestScore);
  }

  _MidAnchorEvidence _validateMidAnchors({
    required RecognizedText sourceResult,
    required _MidRecoveryLayout layout,
    required _StructuredWeakCandidate candidate,
  }) {
    final expectedLeft = candidate.front.substring(candidate.front.length - 1);
    final expectedRight = candidate.back.substring(0, 1);
    if (layout.geometryBacked) {
      return _MidAnchorEvidence(
        expectedLeft: expectedLeft,
        expectedRight: expectedRight,
        observedLeft: expectedLeft,
        observedRight: expectedRight,
        leftMatched: true,
        rightMatched: true,
        sourceKind: layout.sourceKind,
        geometryBacked: true,
      );
    }
    final left = _bestDigitObservationForRect(
      sourceResult,
      layout.leftAnchorRect,
    );
    final right = _bestDigitObservationForRect(
      sourceResult,
      layout.rightAnchorRect,
    );
    final leftMatched = left.digit == expectedLeft && left.score >= .10;
    final rightMatched = right.digit == expectedRight && right.score >= .10;
    return _MidAnchorEvidence(
      expectedLeft: expectedLeft,
      expectedRight: expectedRight,
      observedLeft: left.digit,
      observedRight: right.digit,
      leftMatched: leftMatched,
      rightMatched: rightMatched,
      sourceKind: layout.sourceKind,
      geometryBacked: false,
    );
  }

  _MidGlyphEvidence? _selectMidFromGlyphCropResult(
      RecognizedText result,
      Size imageSize, {
        required _StructuredWeakCandidate expected,
        required VoidCallback onUseLearningMid,
      }) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return null;
    final candidates = <_MidGlyphEvidence>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final box = element.boundingBox;
          if (box.width <= 0 || box.height <= 0) continue;
          final nx = box.center.dx / imageSize.width;
          final ny = box.center.dy / imageSize.height;
          final nh = box.height / imageSize.height;
          if (nx < .08 || nx > .92 || ny < .05 || ny > .95 || nh < .10) {
            continue;
          }
          for (final char in element.text.split('')) {
            if (!RegExp(r'[가-힣]').hasMatch(char)) continue;
            final normalized = _normalizeMidToken(
              char,
              onUseLearningMid: onUseLearningMid,
            );
            if (!_KoreanPlatePolicy.allowedNewMids.contains(normalized)) {
              continue;
            }
            final hints =
                _genericWeakMidHints[expected.observedToken] ?? const <String>[];
            final hintRank = hints.indexOf(normalized);
            final centerPenalty = (nx - .5).abs() + ((ny - .5).abs() * .45);
            final sizePenalty = (nh - .58).abs() * .10;
            final hintBonus = hintRank < 0
                ? 0.0
                : math.max(.03, .12 - (hintRank * .02));
            candidates.add(
              _MidGlyphEvidence(
                mid: normalized,
                score: centerPenalty + sizePenalty - hintBonus,
                text: line.text.trim(),
              ),
            );
          }
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates.first;
  }

  Rect _buildMidContextOcrRect({
    required _MidRecoveryLayout layout,
    required Size imageSize,
  }) {
    final union = Rect.fromLTRB(
      math.min(layout.leftAnchorRect.left, math.min(layout.glyphRect.left, layout.rightAnchorRect.left)),
      math.min(layout.leftAnchorRect.top, math.min(layout.glyphRect.top, layout.rightAnchorRect.top)),
      math.max(layout.leftAnchorRect.right, math.max(layout.glyphRect.right, layout.rightAnchorRect.right)),
      math.max(layout.leftAnchorRect.bottom, math.max(layout.glyphRect.bottom, layout.rightAnchorRect.bottom)),
    );
    final padX = math.max(2.0, union.width * .04).toDouble();
    final padY = math.max(3.0, union.height * .10).toDouble();
    final maxLeft = math.max(0.0, imageSize.width - 1.0).toDouble();
    final maxTop = math.max(0.0, imageSize.height - 1.0).toDouble();
    final left = (union.left - padX).clamp(0.0, maxLeft).toDouble();
    final top = (union.top - padY).clamp(0.0, maxTop).toDouble();
    final right =
        (union.right + padX).clamp(left + 1.0, imageSize.width).toDouble();
    final bottom =
        (union.bottom + padY).clamp(top + 1.0, imageSize.height).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _mapSourceRectToCropImage({
    required Rect sourceRect,
    required Rect cropRect,
    required Size cropImageSize,
  }) {
    if (cropRect.width <= 0 || cropRect.height <= 0) return Rect.zero;
    final scaleX = cropImageSize.width / cropRect.width;
    final scaleY = cropImageSize.height / cropRect.height;
    final left = (sourceRect.left - cropRect.left) * scaleX;
    final top = (sourceRect.top - cropRect.top) * scaleY;
    final right = (sourceRect.right - cropRect.left) * scaleX;
    final bottom = (sourceRect.bottom - cropRect.top) * scaleY;
    return Rect.fromLTRB(
      left.clamp(0.0, cropImageSize.width).toDouble(),
      top.clamp(0.0, cropImageSize.height).toDouble(),
      right.clamp(0.0, cropImageSize.width).toDouble(),
      bottom.clamp(0.0, cropImageSize.height).toDouble(),
    );
  }

  _MidGlyphEvidence? _selectMidFromContextCropResult(
    RecognizedText result,
    Size imageSize, {
    required Rect targetGlyphRect,
    required _StructuredWeakCandidate expected,
    required VoidCallback onUseLearningMid,
  }) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        targetGlyphRect.width <= 0 ||
        targetGlyphRect.height <= 0) {
      return null;
    }
    final candidates = <_MidGlyphEvidence>[];
    final targetArea = math.max(1.0, targetGlyphRect.width * targetGlyphRect.height);
    final targetScale = math.max(1.0, math.max(targetGlyphRect.width, targetGlyphRect.height));
    final tolerance = targetGlyphRect.inflate(math.max(3.0, targetGlyphRect.width * .18));
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final runes = element.text.runes.toList(growable: false);
          if (runes.isEmpty ||
              element.boundingBox.width <= 0 ||
              element.boundingBox.height <= 0) {
            continue;
          }
          for (var index = 0; index < runes.length; index++) {
            final char = String.fromCharCode(runes[index]);
            if (!RegExp(r'[가-힣]').hasMatch(char)) continue;
            final normalized = _normalizeMidToken(
              char,
              onUseLearningMid: onUseLearningMid,
            );
            if (!_KoreanPlatePolicy.allowedNewMids.contains(normalized)) {
              continue;
            }
            final charBox = _subCharacterBox(
              element.boundingBox,
              runes.length,
              index,
            );
            final intersection = targetGlyphRect.intersect(charBox);
            final intersectionArea = intersection.width > 0 && intersection.height > 0
                ? intersection.width * intersection.height
                : 0.0;
            final charArea = math.max(1.0, charBox.width * charBox.height);
            final overlapTarget = intersectionArea / targetArea;
            final overlapChar = intersectionArea / charArea;
            final overlap = math.max(overlapTarget, overlapChar);
            final centerInside = tolerance.contains(charBox.center);
            if (!centerInside && overlap < .18) continue;
            final centerDistance =
                (charBox.center - targetGlyphRect.center).distance / targetScale;
            final sizeRatio = charBox.height / math.max(1.0, targetGlyphRect.height);
            final sizePenalty = (sizeRatio - .82).abs() * .12;
            final hints =
                _genericWeakMidHints[expected.observedToken] ?? const <String>[];
            final hintRank = hints.indexOf(normalized);
            final hintBonus = hintRank < 0
                ? 0.0
                : math.max(.03, .12 - (hintRank * .02));
            candidates.add(
              _MidGlyphEvidence(
                mid: normalized,
                score: centerDistance + sizePenalty - overlap * .75 - hintBonus,
                text: line.text.trim(),
              ),
            );
          }
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates.first;
  }

  Future<_MicroCropRecovery?> _tryRecoverFromMidContextMicroCrops({
    required String capturedPath,
    required _DecodedCapture decoded,
    required RecognizedText sourceResult,
    required _WeakPlateRegion region,
    required List<_StructuredWeakCandidate> weakCandidates,
    required VoidCallback onUseLearningMid,
    required _LocalOcrBudget budget,
    int maxAttempts = 2,
  }) async {
    final resolvedFront = _resolveFrontFromEvidence(
      region.back,
      weakCandidates,
    );
    final ranked = List<_StructuredWeakCandidate>.from(weakCandidates)
      ..sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    var tried = 0;
    _MicroCropRecovery? bestNear;

    for (final candidate in ranked) {
      if (candidate.back != region.back) continue;
      if (resolvedFront != null && candidate.front != resolvedFront) continue;
      final key = '${candidate.front}|${candidate.back}|${candidate.frontLen}';
      if (!seen.add(key)) continue;
      if (tried >= maxAttempts || !budget.canRun) break;

      final layout = _buildMidRecoveryLayout(
        result: sourceResult,
        plateBox: region.box,
        region: region,
        candidate: candidate,
        imageSize: decoded.imageSize,
      );
      if (layout.contextRect.width < 4 ||
          layout.contextRect.height < 4 ||
          layout.glyphRect.width < 4 ||
          layout.glyphRect.height < 4) {
        continue;
      }
      final anchors = _validateMidAnchors(
        sourceResult: sourceResult,
        layout: layout,
        candidate: candidate,
      );
      _ocrDebugLocalSlot = _PlateRecoverySlot.mid;
      _ocrDebugLocalCropBox = layout.contextRect;
      _ocrDebugMidContextBox = layout.contextRect;
      _ocrDebugMidLeftBox = layout.leftAnchorRect;
      _ocrDebugMidGlyphBox = layout.glyphRect;
      _ocrDebugMidRightBox = layout.rightAnchorRect;
      _ocrDebugMidAnchorStatus =
          'expected=${anchors.expectedLeft}|${anchors.expectedRight} '
          'observed=${anchors.observedLeft ?? '-'}|${anchors.observedRight ?? '-'} '
          'left=${anchors.leftMatched} right=${anchors.rightMatched} '
          'strong=${anchors.strong} kind=${anchors.sourceKind} quality=${anchors.quality}';

      final contextX = layout.contextRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
      final contextY = layout.contextRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
      final contextRight = layout.contextRect.right.ceil().clamp(contextX + 1, decoded.image.width).toInt();
      final contextBottom = layout.contextRect.bottom.ceil().clamp(contextY + 1, decoded.image.height).toInt();
      var contextImage = img.copyCrop(
        decoded.image,
        x: contextX,
        y: contextY,
        width: contextRight - contextX,
        height: contextBottom - contextY,
      );
      contextImage.exif.imageIfd.orientation = null;
      final contextScale = (260.0 / math.max(1, contextImage.height)).clamp(1.0, 4.0).toDouble();
      if (contextScale > 1.02) {
        contextImage = img.copyResize(
          contextImage,
          width: math.max(1, (contextImage.width * contextScale).round()).toInt(),
          height: math.max(1, (contextImage.height * contextScale).round()).toInt(),
          interpolation: img.Interpolation.cubic,
        );
      }
      final contextBytes = Uint8List.fromList(img.encodeJpg(contextImage, quality: 96));
      _ocrDebugMidContextBytes = contextBytes;
      _ocrDebugMidGlyphBytes = null;
      _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.midContext;
      _ocrDebugLocalCropText = null;
      _ocrDebugMidGlyphText = null;
      _appendLog(
        'mid layout signature=${candidate.signature} kind=${layout.sourceKind} '
            'context=${_rectForLog(layout.contextRect)} '
            'left=${_rectForLog(layout.leftAnchorRect)} '
            'glyph=${_rectForLog(layout.glyphRect)} '
            'right=${_rectForLog(layout.rightAnchorRect)} '
            'geometryBacked=${layout.geometryBacked}',
      );
      _appendLog(
        'mid anchors signature=${candidate.signature} '
            'expected=${anchors.expectedLeft}|${anchors.expectedRight} '
            'observed=${anchors.observedLeft ?? '-'}|${anchors.observedRight ?? '-'} '
            'leftMatch=${anchors.leftMatched} rightMatch=${anchors.rightMatched} '
            'strong=${anchors.strong} kind=${anchors.sourceKind} quality=${anchors.quality}',
      );
      _setOcrDebugStage(
        _OcrDebugStage.localCropPrepared,
        detail:
        '${candidate.signature} context=${layout.sourceKind} anchorStrong=${anchors.strong} rect=${_rectForLog(layout.contextRect)}',
        structuredPlate: candidate.signature,
      );
      await _developerDebugBeat(const Duration(milliseconds: 80));
      final localStageWatch = Stopwatch()..start();

      final glyphX = layout.glyphRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
      final glyphY = layout.glyphRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
      final glyphRight = layout.glyphRect.right.ceil().clamp(glyphX + 1, decoded.image.width).toInt();
      final glyphBottom = layout.glyphRect.bottom.ceil().clamp(glyphY + 1, decoded.image.height).toInt();
      var glyphImage = img.copyCrop(
        decoded.image,
        x: glyphX,
        y: glyphY,
        width: glyphRight - glyphX,
        height: glyphBottom - glyphY,
      );
      glyphImage.exif.imageIfd.orientation = null;
      final scale = (420.0 / math.max(1, glyphImage.height)).clamp(1.0, 6.0).toDouble();
      if (scale > 1.02) {
        glyphImage = img.copyResize(
          glyphImage,
          width: math.max(1, (glyphImage.width * scale).round()).toInt(),
          height: math.max(1, (glyphImage.height * scale).round()).toInt(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final bytes = Uint8List.fromList(img.encodeJpg(glyphImage, quality: 98));
      final microPath =
          '$capturedPath.live_ocr_mid_glyph_${candidate.frontLen}_${candidate.front}_${candidate.back}.jpg';
      final file = File(microPath);
      try {
        await file.writeAsBytes(bytes, flush: true);
        _ocrDebugLocalCropBytes = bytes;
        _ocrDebugMidGlyphBytes = bytes;
        _ocrDebugLocalCropBox = layout.contextRect;
        _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.midGlyph;
        _ocrDebugLocalCropText = null;
        if (!budget.consume()) break;
        tried++;
        _setOcrDebugStage(
          _OcrDebugStage.localCropOcr,
          detail:
          '${candidate.signature} glyph=${_rectForLog(layout.glyphRect)} crop=${glyphImage.width}x${glyphImage.height} anchorStrong=${anchors.strong}',
          structuredPlate: candidate.signature,
        );

        final watch = Stopwatch()..start();
        final glyphResult = await _recognizer.processImage(
          InputImage.fromFilePath(microPath),
        );
        watch.stop();
        final text = glyphResult.text;
        final ocrMs = watch.elapsedMilliseconds;
        budget.addOcrMs(ocrMs);
        localStageWatch.stop();
        _recordLocalStageWall(candidate.signature, localStageWatch.elapsedMilliseconds);
        _ocrDebugLocalCropText = text.replaceAll('\n', ' ');
        _ocrDebugMidGlyphText = text.replaceAll('\n', ' ');
        _ocrDebugLocalOcrMs = budget.totalOcrMs;

        final glyph = _selectMidFromGlyphCropResult(
          glyphResult,
          Size(glyphImage.width.toDouble(), glyphImage.height.toDouble()),
          expected: candidate,
          onUseLearningMid: onUseLearningMid,
        );
        if (glyph != null && (anchors.leftMatched || anchors.rightMatched)) {
          _recordLocalMidEvidence(
            candidate.front,
            candidate.back,
            glyph,
            anchors,
          );
          bestNear = _MicroCropRecovery(
            plate: null,
            text: text,
            rect: layout.glyphRect,
            bytes: bytes,
            ocrMs: ocrMs,
            signature: candidate.signature,
            hasUsefulEvidence: true,
          );
        }
        final ambiguousFronts = _ambiguousFrontSegmentations(
          candidate,
          weakCandidates,
        );
        final frontResolved = resolvedFront == candidate.front;
        _appendLog(
          'mid glyph signature=${candidate.signature} '
              'rect=${_rectForLog(layout.glyphRect)} crop=${glyphImage.width}x${glyphImage.height} '
              'ocrMs=$ocrMs localWallMs=${localStageWatch.elapsedMilliseconds} '
              'localOcrTotalMs=${budget.totalOcrMs} '
              'budget=${budget.used}/${budget.maxAttempts} '
              'text=${text.replaceAll('\n', ' ')} mid=${glyph?.mid ?? '-'} '
              'anchorStrong=${anchors.strong} anchorQuality=${anchors.quality} '
              'leftMatch=${anchors.leftMatched} rightMatch=${anchors.rightMatched} '
              'frontResolved=$frontResolved ambiguous=${ambiguousFronts.join('|')}',
        );

        if (glyph != null && anchors.strong) {
          final plate = '${candidate.front}${glyph.mid}${candidate.back}';
          if (_isModernPlate(plate)) {
            _appendLog(
              'micro crop 복구 성공 plate=$plate '
                  'signature=${candidate.signature} anchorStrong=${anchors.strong} '
                  'anchorQuality=${anchors.quality} layout=${layout.sourceKind} '
                  'source=glyph glyph=${glyph.mid}',
            );
            return _MicroCropRecovery(
              plate: plate,
              text: text,
              rect: layout.glyphRect,
              bytes: bytes,
              ocrMs: ocrMs,
              signature: candidate.signature,
              hasUsefulEvidence: true,
            );
          }
        }

        if (glyph == null && anchors.strong && budget.canRun) {
          final contextStageWatch = Stopwatch()..start();
          final contextOcrRect = _buildMidContextOcrRect(
            layout: layout,
            imageSize: decoded.imageSize,
          );
          final contextX = contextOcrRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
          final contextY = contextOcrRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
          final contextRight = contextOcrRect.right.ceil().clamp(contextX + 1, decoded.image.width).toInt();
          final contextBottom = contextOcrRect.bottom.ceil().clamp(contextY + 1, decoded.image.height).toInt();
          var contextOcrImage = img.copyCrop(
            decoded.image,
            x: contextX,
            y: contextY,
            width: contextRight - contextX,
            height: contextBottom - contextY,
          );
          contextOcrImage.exif.imageIfd.orientation = null;
          final contextOcrScale =
              (320.0 / math.max(1, contextOcrImage.height)).clamp(1.0, 5.0).toDouble();
          if (contextOcrScale > 1.02) {
            contextOcrImage = img.copyResize(
              contextOcrImage,
              width: math.max(1, (contextOcrImage.width * contextOcrScale).round()).toInt(),
              height: math.max(1, (contextOcrImage.height * contextOcrScale).round()).toInt(),
              interpolation: img.Interpolation.cubic,
            );
          }
          final contextOcrBytes =
              Uint8List.fromList(img.encodeJpg(contextOcrImage, quality: 98));
          final contextPath =
              '$capturedPath.live_ocr_mid_context_${candidate.frontLen}_${candidate.front}_${candidate.back}.jpg';
          final contextFile = File(contextPath);
          try {
            await contextFile.writeAsBytes(contextOcrBytes, flush: true);
            _ocrDebugLocalCropBytes = contextOcrBytes;
            _ocrDebugMidContextBytes = contextOcrBytes;
            _ocrDebugLocalCropBox = contextOcrRect;
            _ocrDebugMidContextBox = contextOcrRect;
            _ocrRecoveryPreviewPhase = _OcrRecoveryPreviewPhase.midContext;
            _ocrDebugMidContextText = null;
            _setOcrDebugStage(
              _OcrDebugStage.localCropPrepared,
              detail:
                  '${candidate.signature} contextFallback=${_rectForLog(contextOcrRect)} anchorQuality=${anchors.quality}',
              structuredPlate: candidate.signature,
            );
            _appendLog(
              'mid context fallback start signature=${candidate.signature} '
                  'rect=${_rectForLog(contextOcrRect)} '
                  'anchorStrong=${anchors.strong} anchorQuality=${anchors.quality} '
                  'primaryText=${text.replaceAll('\n', ' ')}',
            );
            if (budget.consume()) {
              _setOcrDebugStage(
                _OcrDebugStage.localCropOcr,
                detail:
                    '${candidate.signature} contextFallback crop=${contextOcrImage.width}x${contextOcrImage.height} anchorQuality=${anchors.quality}',
                structuredPlate: candidate.signature,
              );
              final contextWatch = Stopwatch()..start();
              final contextResult = await _recognizer.processImage(
                InputImage.fromFilePath(contextPath),
              );
              contextWatch.stop();
              final contextText = contextResult.text;
              final contextOcrMs = contextWatch.elapsedMilliseconds;
              budget.addOcrMs(contextOcrMs);
              if (contextStageWatch.isRunning) contextStageWatch.stop();
              _recordLocalStageWall(
                candidate.signature,
                contextStageWatch.elapsedMilliseconds,
              );
              _ocrDebugLocalOcrMs = budget.totalOcrMs;
              _ocrDebugLocalCropText = contextText.replaceAll('\n', ' ');
              _ocrDebugMidContextText = contextText.replaceAll('\n', ' ');
              final mappedGlyphRect = _mapSourceRectToCropImage(
                sourceRect: layout.glyphRect,
                cropRect: contextOcrRect,
                cropImageSize: Size(
                  contextOcrImage.width.toDouble(),
                  contextOcrImage.height.toDouble(),
                ),
              );
              final contextGlyph = _selectMidFromContextCropResult(
                contextResult,
                Size(
                  contextOcrImage.width.toDouble(),
                  contextOcrImage.height.toDouble(),
                ),
                targetGlyphRect: mappedGlyphRect,
                expected: candidate,
                onUseLearningMid: onUseLearningMid,
              );
              _appendLog(
                'mid context fallback result signature=${candidate.signature} '
                    'rect=${_rectForLog(contextOcrRect)} '
                    'targetM=${_rectForLog(mappedGlyphRect)} '
                    'crop=${contextOcrImage.width}x${contextOcrImage.height} '
                    'ocrMs=$contextOcrMs localWallMs=${contextStageWatch.elapsedMilliseconds} '
                    'localOcrTotalMs=${budget.totalOcrMs} '
                    'budget=${budget.used}/${budget.maxAttempts} '
                    'text=${contextText.replaceAll('\n', ' ')} '
                    'mid=${contextGlyph?.mid ?? '-'} spatialMatch=${contextGlyph != null} '
                    'anchorStrong=${anchors.strong} anchorQuality=${anchors.quality}',
              );
              if (contextGlyph != null &&
                  (anchors.leftMatched || anchors.rightMatched)) {
                _recordLocalMidEvidence(
                  candidate.front,
                  candidate.back,
                  contextGlyph,
                  anchors,
                );
                bestNear = _MicroCropRecovery(
                  plate: null,
                  text: contextText,
                  rect: contextOcrRect,
                  bytes: contextOcrBytes,
                  ocrMs: ocrMs + contextOcrMs,
                  signature: candidate.signature,
                  hasUsefulEvidence: true,
                );
              }
              if (contextGlyph != null && anchors.strong) {
                final plate =
                    '${candidate.front}${contextGlyph.mid}${candidate.back}';
                if (_isModernPlate(plate)) {
                  _appendLog(
                    'micro crop 복구 성공 plate=$plate '
                        'signature=${candidate.signature} anchorStrong=${anchors.strong} '
                        'anchorQuality=${anchors.quality} layout=${layout.sourceKind} '
                        'source=contextFallback glyph=${contextGlyph.mid}',
                  );
                  return _MicroCropRecovery(
                    plate: plate,
                    text: '$text | CONTEXT $contextText',
                    rect: contextOcrRect,
                    bytes: contextOcrBytes,
                    ocrMs: ocrMs + contextOcrMs,
                    signature: candidate.signature,
                    hasUsefulEvidence: true,
                  );
                }
              }
            }
          } finally {
            try {
              if (contextFile.existsSync()) contextFile.deleteSync();
            } catch (_) {}
          }
        }
      } finally {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    }
    _appendLog(
      'micro crop 복구 실패 back=${region.back} tried=$tried '
          'budget=${budget.used}/${budget.maxAttempts} '
          'resolvedFront=${resolvedFront ?? '-'} useful=${bestNear != null}',
    );
    return bestNear;
  }

  String? _recoverExpectedModernPlateFromCrop({
    required RecognizedText cropResult,
    required String cropText,
    required Size cropImageSize,
    required _StructuredWeakCandidate expected,
    required List<_StructuredWeakCandidate> expectedCandidates,
    required VoidCallback onUseLearningMid,
  }) {
    final direct = _extractStrictKoreanPlate(cropText);
    if (direct != null &&
        _cropPlateMatchesAnyWeakEvidence(direct, expectedCandidates)) {
      _appendLog(
        'crop 완전번호판 채택 plate=$direct '
            'expected=${expected.signature} reason=weakSegmentationOverride',
      );
      return direct;
    }

    final loose = _extractLooseKoreanPlate(
      cropText,
      onUseLearningMid: onUseLearningMid,
    );
    if (loose != null &&
        _cropPlateMatchesAnyWeakEvidence(loose, expectedCandidates)) {
      _appendLog(
        'crop 완화번호판 채택 plate=$loose '
            'expected=${expected.signature} reason=weakSegmentationOverride',
      );
      return loose;
    }

    final resolvedFront = _resolveFrontFromEvidence(
      expected.back,
      expectedCandidates,
    );
    if (resolvedFront != null && expected.front != resolvedFront) {
      _appendLog(
        'crop mid-only 후보 제외 signature=${expected.signature} '
            'resolvedFront=$resolvedFront evidence=${expected.segmentationEvidence.name}',
      );
      return null;
    }

    final ambiguousFronts = _ambiguousFrontSegmentations(
      expected,
      expectedCandidates,
    );
    if (ambiguousFronts.length > 1) {
      _appendLog(
        'crop mid-only 자동확정 차단 signature=${expected.signature} '
            'raw=${expected.rawValue} back=${expected.back} '
            'fronts=${ambiguousFronts.join('|')} reason=ambiguousFrontSegmentation',
      );
      return null;
    }

    final mid = _selectMidFromCropResult(
      cropResult,
      cropImageSize,
      expected: expected,
      onUseLearningMid: onUseLearningMid,
    );
    if (mid == null) return null;
    final candidate = '${expected.front}$mid${expected.back}';
    return _isModernPlate(candidate) ? candidate : null;
  }

  double _segmentationEvidenceWeight(_WeakSegmentationEvidence evidence) {
    switch (evidence) {
      case _WeakSegmentationEvidence.explicit:
        return 4.0;
      case _WeakSegmentationEvidence.observedSlot:
        return 3.0;
      case _WeakSegmentationEvidence.numericSlot:
        return 1.0;
      case _WeakSegmentationEvidence.persistentBridge:
        return 0.5;
      case _WeakSegmentationEvidence.inferred:
        return 0.0;
    }
  }

  bool _isDiscriminativeSegmentationEvidence(
    _WeakSegmentationEvidence evidence,
  ) {
    return evidence == _WeakSegmentationEvidence.explicit ||
        evidence == _WeakSegmentationEvidence.observedSlot;
  }

  void _observeSegmentationEvidence(
    List<_StructuredWeakCandidate> candidates,
  ) {
    final frame = <String, Map<String, double>>{};
    final discriminativeFrame = <String, Set<String>>{};
    for (final candidate in candidates) {
      final weight = _segmentationEvidenceWeight(
        candidate.segmentationEvidence,
      );
      if (weight > 0) {
        final fronts = frame.putIfAbsent(
          candidate.back,
          () => <String, double>{},
        );
        final previous = fronts[candidate.front] ?? 0.0;
        if (weight > previous) {
          fronts[candidate.front] = weight;
        }
      }
      if (_isDiscriminativeSegmentationEvidence(
        candidate.segmentationEvidence,
      )) {
        discriminativeFrame
            .putIfAbsent(candidate.back, () => <String>{})
            .add(candidate.front);
      }
    }
    _segmentationEvidenceFrames.add(frame);
    _discriminativeSegmentationFrames.add(discriminativeFrame);
    if (_segmentationEvidenceFrames.length > _voteWindow) {
      _segmentationEvidenceFrames.removeAt(0);
    }
    if (_discriminativeSegmentationFrames.length > _voteWindow) {
      _discriminativeSegmentationFrames.removeAt(0);
    }
  }

  Map<String, double> _segmentationScoresForBack(
    String back,
    List<_StructuredWeakCandidate> candidates,
  ) {
    final scores = <String, double>{};
    for (final frame in _segmentationEvidenceFrames) {
      final fronts = frame[back];
      if (fronts == null) continue;
      for (final entry in fronts.entries) {
        scores[entry.key] = (scores[entry.key] ?? 0.0) + entry.value;
      }
    }
    for (final candidate in candidates) {
      if (candidate.back != back) continue;
      final weight = _segmentationEvidenceWeight(
        candidate.segmentationEvidence,
      );
      if (weight <= 0) continue;
      scores[candidate.front] = math.max(
        scores[candidate.front] ?? 0.0,
        weight,
      );
    }
    return scores;
  }

  Set<String> _discriminativeSegmentationFrontsForBack(
    String back,
    List<_StructuredWeakCandidate> candidates,
  ) {
    final fronts = <String>{};
    for (final frame in _discriminativeSegmentationFrames) {
      fronts.addAll(frame[back] ?? const <String>{});
    }
    for (final candidate in candidates) {
      if (candidate.back != back) continue;
      if (!_isDiscriminativeSegmentationEvidence(
        candidate.segmentationEvidence,
      )) {
        continue;
      }
      fronts.add(candidate.front);
    }
    return fronts;
  }

  bool _hasDiscriminativeSegmentationEvidence(
    String back,
    String front,
    List<_StructuredWeakCandidate> candidates,
  ) {
    return _discriminativeSegmentationFrontsForBack(
      back,
      candidates,
    ).contains(front);
  }

  String _segmentationDiscriminativeSummary(
    String back,
    List<_StructuredWeakCandidate> candidates,
  ) {
    final fronts = _discriminativeSegmentationFrontsForBack(
      back,
      candidates,
    ).toList()
      ..sort((a, b) {
        final lengthCompare = b.length.compareTo(a.length);
        if (lengthCompare != 0) return lengthCompare;
        return a.compareTo(b);
      });
    return fronts.isEmpty ? '-' : fronts.join('|');
  }

  String _segmentationEvidenceMode(
    String back,
    List<_StructuredWeakCandidate> candidates,
  ) {
    return _discriminativeSegmentationFrontsForBack(
      back,
      candidates,
    ).isEmpty
        ? 'numeric_only'
        : 'discriminative';
  }

  String _segmentationScoreSummary(
    String back,
    List<_StructuredWeakCandidate> candidates,
  ) {
    final scores = _segmentationScoresForBack(back, candidates);
    if (scores.isEmpty) return '-';
    final ranked = scores.entries.toList()
      ..sort((a, b) {
        final scoreCompare = b.value.compareTo(a.value);
        if (scoreCompare != 0) return scoreCompare;
        return a.key.compareTo(b.key);
      });
    return ranked
        .map((entry) => '${entry.key}:${entry.value.toStringAsFixed(1)}')
        .join('|');
  }

  String? _resolveFrontFromEvidence(
    String back,
    List<_StructuredWeakCandidate> candidates,
  ) {
    final scores = _segmentationScoresForBack(back, candidates);
    if (scores.isEmpty) return null;
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    if (!_hasDiscriminativeSegmentationEvidence(
      back,
      best.key,
      candidates,
    )) {
      return null;
    }
    final second = ranked.length > 1 ? ranked[1].value : 0.0;
    if (best.value >= 3.0 && best.value >= second + 1.5) {
      return best.key;
    }
    if (ranked.length == 1 && best.value >= 3.0) {
      return best.key;
    }
    return null;
  }

  bool _isFastRecoverySegmentationResolved(
    _StructuredWeakCandidate candidate,
    List<_StructuredWeakCandidate> candidates,
  ) {
    final resolvedFront = _resolveFrontFromEvidence(
      candidate.back,
      candidates,
    );
    return resolvedFront == candidate.front;
  }

  List<String> _ambiguousFrontSegmentations(
      _StructuredWeakCandidate expected,
      List<_StructuredWeakCandidate> expectedCandidates,
      ) {
    final resolvedFront = _resolveFrontFromEvidence(
      expected.back,
      expectedCandidates,
    );
    if (resolvedFront != null) {
      return <String>[resolvedFront];
    }
    final raw = _normalizeWeakEvidenceValue(expected.rawValue);
    final fronts = <String>{};
    for (final candidate in expectedCandidates) {
      if (candidate.back != expected.back) continue;
      if (_normalizeWeakEvidenceValue(candidate.rawValue) != raw) continue;
      fronts.add(candidate.front);
    }
    final sorted = fronts.toList()
      ..sort((a, b) {
        final lengthCompare = a.length.compareTo(b.length);
        if (lengthCompare != 0) return lengthCompare;
        return a.compareTo(b);
      });
    return sorted;
  }

  bool _cropPlateMatchesAnyWeakEvidence(
      String plate,
      List<_StructuredWeakCandidate> expectedCandidates,
      ) {
    final normalized = _normalizeCandidateKey(plate);
    final match = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$')
        .firstMatch(normalized);
    if (match == null || !_isModernPlate(normalized)) return false;
    final plateFront = match.group(1)!;
    final plateBack = match.group(3)!;

    for (final expected in expectedCandidates) {
      if (expected.back != plateBack) continue;
      if (expected.front == plateFront) return true;
      final raw = _normalizeWeakEvidenceValue(expected.rawValue);
      if (raw.startsWith(plateFront) && raw.endsWith(plateBack)) {
        final middleStart = plateFront.length;
        final middleEnd = raw.length - plateBack.length;
        if (middleEnd >= middleStart) {
          final middle = raw.substring(middleStart, middleEnd);
          if (middle.length <= 2) {
            return true;
          }
        }
      }
    }
    return false;
  }

  String _normalizeWeakEvidenceValue(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final code = rune;
      if (code >= 0xFF10 && code <= 0xFF19) {
        buffer.write(String.fromCharCode(0x30 + (code - 0xFF10)));
        continue;
      }
      if (RegExp(r'[0-9A-Za-z가-힣○#|]').hasMatch(char)) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  String? _selectMidFromCropResult(
      RecognizedText result,
      Size cropImageSize, {
        required _StructuredWeakCandidate expected,
        required VoidCallback onUseLearningMid,
      }) {
    if (cropImageSize.width <= 0 || cropImageSize.height <= 0) {
      return null;
    }

    final candidates = <({
    String mid,
    double score,
    double nx,
    double ny,
    double nh,
    bool digitAligned,
    int hintRank,
    String lineText,
    })>[];
    final expectedMidX = expected.frontLen >= 3 ? .43 : .37;
    final cropCenterY = cropImageSize.height / 2;

    for (final block in result.blocks) {
      for (final line in block.lines) {
        final lineBox = line.boundingBox;
        if (lineBox.width <= 0 || lineBox.height <= 0) continue;
        final lineText = line.text.trim();
        final lineDigits =
        lineText.replaceAll(RegExp(r'[^0-9]'), '');
        final digitAligned = lineDigits.contains(expected.front) ||
            lineDigits.contains(expected.back) ||
            lineDigits.contains('${expected.front}${expected.back}');
        final lineCenterOffset =
            (lineBox.center.dy - cropCenterY).abs() / cropImageSize.height;
        final lineHeightRatio = lineBox.height / cropImageSize.height;
        final geometricLineAligned =
            lineCenterOffset <= .20 && lineHeightRatio >= .10;

        for (final element in line.elements) {
          final box = element.boundingBox;
          if (box.width <= 0 || box.height <= 0) continue;
          final nx = box.center.dx / cropImageSize.width;
          final ny = box.center.dy / cropImageSize.height;
          final nh = box.height / cropImageSize.height;
          final xDistance = (nx - expectedMidX).abs();
          final yDistance = (ny - .5).abs();
          final xAligned = nx >= .17 && nx <= .70 && xDistance <= .28;
          final yAligned = ny >= .18 && ny <= .82 && yDistance <= .32;
          final sizeAligned = nh >= .10 && nh <= .78;
          final lineAligned = digitAligned
              ? lineCenterOffset <= .28
              : geometricLineAligned &&
              xDistance <= .18 &&
              yDistance <= .22;
          if (!xAligned || !yAligned || !sizeAligned || !lineAligned) {
            continue;
          }

          for (final char in element.text.split('')) {
            if (!RegExp(r'[가-힣]').hasMatch(char)) continue;
            final normalized = _normalizeMidToken(
              char,
              onUseLearningMid: onUseLearningMid,
            );
            if (!_KoreanPlatePolicy.allowedNewMids.contains(normalized)) {
              continue;
            }
            final hints =
                _genericWeakMidHints[expected.observedToken] ?? const <String>[];
            final hintRank = hints.indexOf(normalized);
            final hintBonus = hintRank < 0
                ? 0.0
                : math.max(0.04, 0.16 - (hintRank * 0.025));
            final score = xDistance +
                (yDistance * .55) +
                ((nh - .34).abs() * .10) -
                (digitAligned ? .18 : 0) -
                hintBonus;
            candidates.add((
            mid: normalized,
            score: score,
            nx: nx,
            ny: ny,
            nh: nh,
            digitAligned: digitAligned,
            hintRank: hintRank,
            lineText: lineText,
            ));
          }
        }
      }
    }

    if (candidates.isEmpty) {
      _appendLog(
        'crop mid 후보 없음 signature=${expected.signature} geometry=strict',
      );
      return null;
    }

    candidates.sort((a, b) => a.score.compareTo(b.score));
    final selected = candidates.first;
    _appendLog(
      'crop mid 선택 signature=${expected.signature} mid=${selected.mid} '
          'score=${selected.score.toStringAsFixed(3)} '
          'nx=${selected.nx.toStringAsFixed(3)} ny=${selected.ny.toStringAsFixed(3)} '
          'nh=${selected.nh.toStringAsFixed(3)} '
          'digitAligned=${selected.digitAligned} hintRank=${selected.hintRank} '
          'line=${selected.lineText.replaceAll('\n', ' ')}',
    );
    return selected.mid;
  }

  String _rectForLog(Rect rect) {
    return '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},'
        '${rect.width.toStringAsFixed(1)},${rect.height.toStringAsFixed(1)}';
  }

  String get _debugPrintCode {
    final lines = <String>[
      '[STATUS] ${_developerStatusDescription.replaceAll('\n', ' | ')}',
      ..._sessionLogs,
    ];
    return lines.map((line) {
      final message = '[LIVE-OCR][${widget.sessionId}] $line';
      return 'debugPrint(${jsonEncode(message)});';
    }).join('\n');
  }

  String get _developerStatusDescription {
    return 'profile=${widget.coordinator.profile.name}\n'
        'coordinator=${widget.coordinator.debugStatus}\n'
        'stage=${_ocrDebugStage.name}\n'
        'detail=${_ocrDebugStageDetail ?? '-'}\n'
        'attempt=$_attempt\n'
        'structured=${_ocrDebugStructuredPlate ?? '-'}\n'
        'cropText=${_ocrDebugCropText ?? '-'}\n'
        'localSlot=${_ocrDebugLocalSlot?.name ?? '-'}\n'
        'localText=${_ocrDebugLocalCropText ?? '-'}\n'
        'midAnchor=${_ocrDebugMidAnchorStatus ?? '-'}\n'
        'midGlyph=${_ocrDebugMidGlyphText ?? '-'}\n'
        'midContext=${_ocrDebugMidContextText ?? '-'}\n'
        'midContextBox=${_ocrDebugMidContextBox == null ? '-' : _rectForLog(_ocrDebugMidContextBox!)}\n'
        'midGlyphBox=${_ocrDebugMidGlyphBox == null ? '-' : _rectForLog(_ocrDebugMidGlyphBox!)}\n'
        'recovered=${_ocrDebugRecoveredPlate ?? '-'}\n'
        'captureMs=${_ocrDebugCaptureMs ?? '-'}\n'
        'fullOcrMs=${_ocrDebugFullOcrMs ?? '-'}\n'
        'cropOcrMs=${_ocrDebugCropOcrMs ?? '-'}\n'
        'recoveryMode=${_recoveryMode.name}\n'
        'fastRecoveryIdentity=${_fastRecoveryIdentity ?? '-'}\n'
        'fastRecoveryCandidate=${_fastRecoveryCandidateSnapshot?.signature ?? '-'}\n'
        'fastRecoveryExecuted=${_fastRecoveryIdentity == null ? false : _hasFastRecoveryExecuted(_fastRecoveryIdentity!)}\n'
        'fastRecoveryAbandoned=${_fastRecoveryIdentity == null ? false : _hasFastRecoveryAbandoned(_fastRecoveryIdentity!)}\n'
        'fastRecoveryDeferred=${_fastRecoveryIdentity == null ? 0 : _fastRecoveryDeferredCount(_fastRecoveryIdentity!)}\n'
        'segmentation=${_lastSegmentationDecision ?? '-'}\n'
        'topology=${_lastTopologyDecision ?? '-'}\n'
        'frameDecision=${_lastFrameDecision ?? '-'}\n'
        'completeDecision=${_lastCompleteDecision ?? '-'}\n'
        'previewPhase=${_ocrRecoveryPreviewPhase.name}\n'
        'perspective=${_ocrDebugPerspectiveApplied ? 'applied' : (_ocrDebugPerspectiveQuad == null ? 'off' : 'quad_only')}\n'
        'perspectiveAngle=${_ocrDebugPerspectiveAngle?.toStringAsFixed(1) ?? '-'}\n'
        'perspectiveQuad=${_ocrDebugPerspectiveQuad == null ? '-' : _quadForLog(_ocrDebugPerspectiveQuad!)}\n'
        'rectifiedSize=${_ocrDebugRectifiedSize == null ? '-' : '${_ocrDebugRectifiedSize!.width.toInt()}x${_ocrDebugRectifiedSize!.height.toInt()}'}\n'
        'rectifiedText=${_ocrDebugPerspectiveText ?? '-'}\n'
        'localOcrMs=${_ocrDebugLocalOcrMs ?? '-'}\n'
        'localWallMs=${_ocrDebugLocalWallMs ?? '-'}\n'
        'recoveryWallMs=${_ocrDebugRecoveryWallMs ?? '-'}\n'
        'refocusPending=${_pendingRefocusSignature ?? '-'}\n'
        'refocusRetry=$_pendingRefocusRetryCount/$_refocusRetryLimit\n'
        'refocusIdentity=${_lastAutoRefocusIdentity ?? '-'}\n'
        'refocusCooldownMs=$_refocusCooldownRemainingMs\n'
        'refocusDecision=${_lastRefocusDecision ?? '-'}\n'
        'logLines=${_sessionLogs.length}';
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final line = '[$ts] $message';
    _sessionLogs.add(line);
    if (_sessionLogs.length > _maxSessionLogLines) {
      _sessionLogs.removeAt(0);
    }
    debugPrint('[LIVE-OCR][${widget.sessionId}] $line');
  }

  String _joinForLog(List<String> values) {
    if (values.isEmpty) return '';
    return values.join('|');
  }

  void _pushVoteFrame(
      List<Set<String>> frames, Map<String, int> votes, Set<String> frame) {
    frames.add(frame);
    for (final v in frame) {
      votes[v] = (votes[v] ?? 0) + 1;
    }
    if (frames.length > _voteWindow) {
      final removed = frames.removeAt(0);
      for (final v in removed) {
        final next = (votes[v] ?? 1) - 1;
        if (next <= 0) {
          votes.remove(v);
        } else {
          votes[v] = next;
        }
      }
    }
  }

  void _pushWeakStructuredCandidateFrame(
    List<_StructuredWeakCandidate> frame,
  ) {
    _weakStructuredCandidateFrames.add(
      List<_StructuredWeakCandidate>.unmodifiable(frame),
    );
    if (_weakStructuredCandidateFrames.length > _voteWindow) {
      _weakStructuredCandidateFrames.removeAt(0);
    }
  }

  List<String> _topologyObservationsForBack(
    String back,
    Set<String> signatures,
  ) {
    final observations = <String>[];
    for (final frame in _weakStructuredCandidateFrames) {
      final coverage = <String, Set<String>>{};
      for (final candidate in frame) {
        if (candidate.back != back ||
            !signatures.contains(candidate.signature) ||
            !RegExp(r'^\d{8}$').hasMatch(candidate.rawValue) ||
            !candidate.rawValue.endsWith(back)) {
          continue;
        }
        coverage
            .putIfAbsent(candidate.rawValue, () => <String>{})
            .add(candidate.signature);
      }
      if (coverage.isEmpty) continue;
      final ranked = coverage.entries.toList()
        ..sort((a, b) {
          final byCoverage = b.value.length.compareTo(a.value.length);
          if (byCoverage != 0) return byCoverage;
          return a.key.compareTo(b.key);
        });
      observations.add(ranked.first.key);
    }
    return observations;
  }

  _TopologyProbeDecision? _selectTopologyProbeDecision(
    List<_StructuredWeakCandidate> currentFrame,
  ) {
    final eligible = <_StructuredWeakCandidate>[];
    final seen = <String>{};
    for (final candidate in _rankStructuredWeakCandidates(currentFrame)) {
      if (!seen.add(candidate.signature)) continue;
      if (candidate.segmentationEvidence !=
          _WeakSegmentationEvidence.numericSlot) {
        continue;
      }
      if (!RegExp(r'^\d{8}$').hasMatch(candidate.rawValue)) continue;
      if (_exactWeakEvidenceIncludingCurrent(
            candidate.signature,
            currentFrame,
          ) <
          _weakStructuredVoteThreshold) {
        continue;
      }
      if (_resolveFrontFromEvidence(candidate.back, currentFrame) != null) {
        continue;
      }
      eligible.add(candidate);
    }
    if (eligible.length < 2) return null;

    final byBack = <String, List<_StructuredWeakCandidate>>{};
    for (final candidate in eligible) {
      byBack
          .putIfAbsent(candidate.back, () => <_StructuredWeakCandidate>[])
          .add(candidate);
    }

    List<_StructuredWeakCandidate>? group;
    for (final candidates in byBack.values) {
      final fronts = candidates.map((e) => e.front).toSet();
      final lengths = candidates.map((e) => e.frontLen).toSet();
      if (fronts.length >= 2 && lengths.contains(2) && lengths.contains(3)) {
        group = candidates;
        break;
      }
    }
    if (group == null) return null;

    final signatures = group.map((e) => e.signature).toSet();
    final observations =
        _topologyObservationsForBack(group.first.back, signatures);
    if (observations.length < _weakStructuredVoteThreshold) return null;

    final scored = <({
      _StructuredWeakCandidate candidate,
      double score,
      bool singleSlot,
      bool stableOuter,
      bool varyingSlot,
      int fittingFrames,
    })>[];

    for (final candidate in group) {
      final tokens = <String>[];
      var fittingFrames = 0;
      for (final raw in observations) {
        if (!raw.startsWith(candidate.front) || !raw.endsWith(candidate.back)) {
          continue;
        }
        final start = candidate.front.length;
        final end = raw.length - candidate.back.length;
        if (end <= start) continue;
        final token = raw.substring(start, end);
        tokens.add(token);
        fittingFrames++;
      }
      final stableOuter = fittingFrames == observations.length;
      final singleSlot =
          stableOuter && tokens.isNotEmpty && tokens.every((e) => e.length == 1);
      final varyingSlot = singleSlot && tokens.toSet().length >= 2;
      final meanTokenWidth = tokens.isEmpty
          ? 9.0
          : tokens.map((e) => e.length).reduce((a, b) => a + b) /
              tokens.length;
      var score = 0.0;
      if (stableOuter) score += 4.0;
      if (singleSlot) score += 8.0;
      if (varyingSlot) score += 4.0;
      score += fittingFrames * 0.8;
      score += _exactWeakEvidenceIncludingCurrent(
            candidate.signature,
            currentFrame,
          ) *
          0.6;
      score -= math.max(0.0, meanTokenWidth - 1.0) * 3.5;
      score += candidate.score * 0.05;
      scored.add((
        candidate: candidate,
        score: score,
        singleSlot: singleSlot,
        stableOuter: stableOuter,
        varyingSlot: varyingSlot,
        fittingFrames: fittingFrames,
      ));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byFrontLen = b.candidate.frontLen.compareTo(a.candidate.frontLen);
      if (byFrontLen != 0) return byFrontLen;
      return a.candidate.signature.compareTo(b.candidate.signature);
    });
    final best = scored.first;
    final second = scored.length > 1 ? scored[1] : null;
    final scoreMargin =
        second == null ? best.score : best.score - second.score;
    final stableSingleSlotAllowed =
        widget.coordinator.profile.allowStableSingleSlotProbe;
    final probeEligible = best.singleSlot &&
        best.stableOuter &&
        (best.varyingSlot || stableSingleSlotAllowed) &&
        best.fittingFrames >= _weakStructuredVoteThreshold &&
        scoreMargin >= 2.0;
    final reason = probeEligible
        ? (best.varyingSlot
            ? 'stableFrontBack+singleSlotVariation'
            : 'stableFrontBack+singleSlotStable')
        : (best.singleSlot
            ? 'singleSlotTopologyAutoSelect'
            : 'structuredTopologyAutoSelect');
    final ranking = scored
        .map(
          (entry) =>
              '${entry.candidate.signature}:${entry.score.toStringAsFixed(1)}',
        )
        .join('|');
    return _TopologyProbeDecision(
      selected: best.candidate,
      alternatives:
          scored.map((entry) => entry.candidate).toList(growable: false),
      probeEligible: probeEligible,
      reason: reason,
      observations: observations.join('|'),
      ranking: ranking,
    );
  }

  Future<bool> _finishWhenProfileAttemptLimitReached() async {
    final profile = widget.coordinator.profile;
    if (profile.maxAttempts <= 0 || _attempt < profile.maxAttempts) {
      return false;
    }
    final best = widget.coordinator.bestStructuredObservation;
    _appendLog(
      'profile attempt limit reached profile=${profile.name} attempt=$_attempt/${profile.maxAttempts} best=${best?.signature ?? '-'} returnIncomplete=${profile.returnBestIncompleteOnLimit}',
    );
    if (profile.returnBestIncompleteOnLimit && best != null) {
      final candidate = _StructuredWeakCandidate(
        signature: best.signature,
        front: best.front,
        back: best.back,
        observedToken: best.observedToken,
        rawValue: best.rawValue,
        frontLen: best.frontLen,
        tokenMissing: best.observedToken.isEmpty,
        segmentationEvidence: _WeakSegmentationEvidence.numericSlot,
        score: best.score,
      );
      await _finishAutoStructuredSelection(
        front: best.front,
        back: best.back,
        observedValue: best.rawValue,
        suggestions: _inferWeakMidSuggestions(candidate),
        alternatives: <String>[best.signature],
        reason: 'profileAttemptLimit',
      );
      return true;
    }
    await _finishAndPop(exitType: LiveOcrExitType.sensorTrackExhausted);
    return true;
  }

  Future<void> _finishAutoStructuredSelection({
    required String front,
    required String back,
    required String observedValue,
    required List<String> suggestions,
    required List<String> alternatives,
    required String reason,
  }) async {
    final selected = '$front?$back';
    _candidateChips = List<String>.from(alternatives, growable: false);
    _displayChips = const [];
    _lastFailureReason = 'auto_structured_selection';
    _currentFailureReason = _lastFailureReason;
    _setOcrDebugStage(
      _OcrDebugStage.fallback,
      detail: 'autoStructuredSelected:$selected',
      structuredPlate: selected,
    );
    _appendLog(
      'structured auto selection alternatives=${_joinForLog(alternatives)} '
      'selected=$selected observed=$observedValue reason=$reason '
      'requiresMidCompletion=true',
    );
    await _finishAndPop(
      exitType: LiveOcrExitType.autoStructuredSelected,
      weakFront: front,
      weakBack: back,
      weakObservedValue: observedValue,
      requiresMidCompletion: true,
      weakMidSuggestions: suggestions,
    );
  }

  void _pushWeakStructuredFrame(List<_StructuredWeakCandidate> frame) {
    final signatures = frame.map((e) => e.signature).toSet();
    _weakStructuredFrames.add(signatures);

    for (final sig in signatures) {
      _weakStructuredVotes[sig] = (_weakStructuredVotes[sig] ?? 0) + 1;
    }

    for (final c in frame) {
      final prev = _weakStructuredBest[c.signature];
      if (prev == null || c.score >= prev.score) {
        _weakStructuredBest[c.signature] = c;
      }
    }

    if (_weakStructuredFrames.length > _voteWindow) {
      final removed = _weakStructuredFrames.removeAt(0);
      for (final sig in removed) {
        final next = (_weakStructuredVotes[sig] ?? 1) - 1;
        if (next <= 0) {
          _weakStructuredVotes.remove(sig);
          _weakStructuredBest.remove(sig);
        } else {
          _weakStructuredVotes[sig] = next;
        }
      }
    }
  }

  _StructuredWeakCandidate? _bestStoredStableWeakCandidate(
    String signature,
  ) {
    final candidates = _weakStructuredBest.entries
        .where((entry) => _sameStableWeakIdentity(signature, entry.key))
        .map((entry) => entry.value)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byVotes = _exactWeakVoteCount(b.signature)
          .compareTo(_exactWeakVoteCount(a.signature));
      if (byVotes != 0) return byVotes;
      return b.score.compareTo(a.score);
    });
    return candidates.first;
  }

  void _pushObservedWeakMidEvidence(
      String text, List<_StructuredWeakCandidate> frame) {
    if (frame.isEmpty) return;

    final norm = _normalizeFlat(text);
    final unique = _rankStructuredWeakCandidates(frame);

    for (final candidate in unique) {
      final front = RegExp.escape(candidate.front);
      final back = RegExp.escape(candidate.back);
      final backPrefix3 = RegExp.escape(candidate.back.substring(0, 3));

      final patterns = <RegExp>[
        RegExp('(?<!\\d)' +
            front +
            _plateSepPattern +
            '([가-힣])' +
            _plateSepPattern +
            back +
            '(?!\\d)'),
        RegExp('(?<!\\d)' +
            front +
            _plateSepPattern +
            '([가-힣])' +
            _plateSepPattern +
            backPrefix3 +
            r'[\d가-힣A-Za-z]'),
      ];

      for (final reg in patterns) {
        for (final match in reg.allMatches(norm)) {
          final observedMid = match.group(1);
          if (observedMid == null) continue;
          if (!_KoreanPlatePolicy.allowedNewMids.contains(observedMid)) {
            continue;
          }

          final bucket = _weakStructuredObservedHangulVotes.putIfAbsent(
              candidate.signature, () => <String, int>{});
          bucket[observedMid] = (bucket[observedMid] ?? 0) + 1;
        }
      }
    }
  }

  bool _shouldSuppressWeakChip(
      _DisplayChip chip,
      String signature,
      ) {
    if (chip.tier != _ChipTier.weak && !chip.requiresMidCompletion) {
      return false;
    }
    final signatureDigits = signature.replaceAll(RegExp(r'[^0-9]'), '');
    final chipDigits = chip.value.replaceAll(RegExp(r'[^0-9]'), '');
    return signatureDigits.isNotEmpty && chipDigits == signatureDigits;
  }

  List<_DisplayChip> _buildDisplayChips(
      Set<String> stableFrame,
      Set<String> tentativeFrame,
      Set<String> weakFrame,
      List<_StructuredWeakCandidate> structuredWeakFrame,
      ) {
    final stable = stableFrame.toList()
      ..sort((a, b) => (_stableVotes[b] ?? 0).compareTo(_stableVotes[a] ?? 0));
    final votedStable = stable
        .where((e) => (_stableVotes[e] ?? 0) >= _stableVoteThreshold)
        .toList();
    if (votedStable.isNotEmpty) {
      return votedStable
          .take(3)
          .map((e) => _DisplayChip(value: e, label: e, tier: _ChipTier.stable))
          .toList();
    }
    if (stable.isNotEmpty) {
      return stable
          .take(2)
          .map((e) => _DisplayChip(value: e, label: e, tier: _ChipTier.stable))
          .toList();
    }

    final tentative = tentativeFrame.toList()
      ..sort((a, b) =>
          (_tentativeVotes[b] ?? 0).compareTo(_tentativeVotes[a] ?? 0));
    final votedTentative = tentative
        .where((e) => (_tentativeVotes[e] ?? 0) >= _tentativeVoteThreshold)
        .toList();
    if (votedTentative.isNotEmpty) {
      return votedTentative
          .take(2)
          .map((e) =>
          _DisplayChip(value: e, label: '추정 $e', tier: _ChipTier.tentative))
          .toList();
    }
    if (tentative.isNotEmpty) {
      return tentative
          .take(1)
          .map((e) =>
          _DisplayChip(value: e, label: '추정 $e', tier: _ChipTier.tentative))
          .toList();
    }

    if (structuredWeakFrame.isNotEmpty) {
      return _buildStructuredWeakChips(structuredWeakFrame);
    }

    final weak = weakFrame.toList()..sort();
    if (weak.isNotEmpty) {
      return weak
          .take(1)
          .map((e) =>
          _DisplayChip(value: e, label: '보정필요 $e', tier: _ChipTier.weak))
          .toList();
    }
    return const [];
  }

  List<_DisplayChip> _buildStructuredWeakChips(
      List<_StructuredWeakCandidate> structuredWeakFrame) {
    final ranked = _rankStructuredWeakCandidates(structuredWeakFrame);
    if (ranked.isEmpty) return const [];

    final resolved = ranked
        .where(
          (candidate) =>
              _exactWeakVoteCount(candidate.signature) >=
                  _weakStructuredVoteThreshold &&
              _isFastRecoverySegmentationResolved(
                candidate,
                structuredWeakFrame,
              ),
        )
        .toList(growable: false);

    List<_StructuredWeakCandidate> source = resolved;
    if (source.isEmpty) {
      final voted = ranked
          .where(
            (candidate) =>
                _exactWeakVoteCount(candidate.signature) >=
                _weakStructuredVoteThreshold,
          )
          .toList(growable: false);
      final byBack = <String, List<_StructuredWeakCandidate>>{};
      for (final candidate in voted) {
        if (_resolveFrontFromEvidence(
              candidate.back,
              structuredWeakFrame,
            ) !=
            null) {
          continue;
        }
        final scores = _segmentationScoresForBack(
          candidate.back,
          structuredWeakFrame,
        );
        if ((scores[candidate.front] ?? 0.0) <= 0) continue;
        byBack
            .putIfAbsent(
              candidate.back,
              () => <_StructuredWeakCandidate>[],
            )
            .add(candidate);
      }
      for (final group in byBack.values) {
        final distinctFronts = group.map((e) => e.front).toSet();
        if (distinctFronts.length < 2) continue;
        source = group;
        break;
      }
    }
    if (source.isEmpty) return const [];

    final selected = <_StructuredWeakCandidate>[];
    final evidenceKeys = <String>{};
    for (final candidate in source) {
      final evidenceKey =
          '${candidate.rawValue}|${candidate.back}|${candidate.front}';
      if (!evidenceKeys.add(evidenceKey)) continue;
      selected.add(candidate);
      if (selected.length >= 2) break;
    }

    return selected.map((e) {
      final suggestions = _inferWeakMidSuggestions(e);
      return _DisplayChip(
        value: e.signature,
        label: '보정필요 ${e.front}?${e.back}',
        tier: _ChipTier.weak,
        weakFront: e.front,
        weakBack: e.back,
        weakObservedValue: e.rawValue,
        requiresMidCompletion: true,
        weakMidSuggestions: suggestions,
      );
    }).toList();
  }

  String _applyCharMap(String text) {
    var t = text;
    _charMap.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  String _normalizePreserveNewlines(String text) {
    final src = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = src.split('\n');
    final out = <String>[];
    for (final line in lines) {
      var t = _applyCharMap(line);
      t = t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      out.add(t);
    }
    return out.join('\n');
  }

  String _normalizeFlat(String text) {
    final t = _normalizePreserveNewlines(text).replaceAll('\n', ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeCandidateKey(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp(r'[\s\.\-·•_]+'), '');
    return t;
  }

  bool _isModernPlate(String s) {
    final t = _normalizeCandidateKey(s);
    final allowed = _KoreanPlatePolicy.newMidCharClass();
    return RegExp('^\\d{2,3}[$allowed]\\d{4}\$').hasMatch(t);
  }

  bool _isLegacyRegionPlate(String s) {
    final t = _normalizeCandidateKey(s);
    final regions = _KoreanPlatePolicy.regionAlternation();
    return RegExp('^(?:$regions)\\d{1,2}[가-힣]\\d{4}\$').hasMatch(t);
  }

  bool _isValidKoreanPlate(String s) {
    return _isModernPlate(s) || _isLegacyRegionPlate(s);
  }

  _KoreanPlateFormat? _plateFormatOf(String s) {
    if (_isModernPlate(s)) return _KoreanPlateFormat.modern;
    if (_isLegacyRegionPlate(s)) return _KoreanPlateFormat.legacyRegion;
    return null;
  }

  bool _isLikelyStableCandidate(String s) {
    if (_isLegacyRegionPlate(s)) return true;
    if (!_isModernPlate(s)) return false;
    if (_preferredFrontLen == null) return true;
    return _inferModernFrontLen(s) == _preferredFrontLen;
  }

  int? _inferModernFrontLen(String s) {
    final t = _normalizeCandidateKey(s);
    final m = RegExp(r'^(\d{2,3})[가-힣](\d{4})$').firstMatch(t);
    if (m == null) return null;
    return m.group(1)?.length;
  }

  String _normalizeMidToken(String raw,
      {required VoidCallback onUseLearningMid}) {
    final dyn = _dynMidMap[raw];
    if (dyn != null && dyn.isNotEmpty) {
      onUseLearningMid();
      return dyn;
    }
    final stat = _KoreanPlatePolicy.staticMidNormalize[raw];
    if (stat != null && stat.isNotEmpty) {
      return stat;
    }
    return raw;
  }

  Set<String> _applyLearnedCandidateMap(Set<String> set) {
    final prioritized = <String>{};
    if (_dynCandidateMap.isEmpty) return prioritized;
    final snapshot = set.toList(growable: false);
    for (final cand in snapshot) {
      final key = _normalizeCandidateKey(cand);
      final mapped = _dynCandidateMap[key];
      if (mapped == null || mapped.isEmpty) continue;
      final normalized = _normalizeCandidateKey(mapped);
      if (!_isValidKoreanPlate(normalized)) continue;
      prioritized.add(normalized);
      set.remove(cand);
      set.add(normalized);
    }
    return prioritized;
  }

  String? _extractStrictModernPlate(String text) {
    final normLines = _normalizePreserveNewlines(text);
    final allowed = _KoreanPlatePolicy.newMidCharClass();
    final reg = RegExp(
      '(?<!\\d)(\\d{2,3})$_plateSepPattern([$allowed])$_plateSepPattern(\\d{4})(?!\\d)',
    );
    final lines = normLines.split('\n');
    for (final line in lines) {
      final m = reg.firstMatch(line);
      if (m != null) {
        return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
      }
    }
    for (int i = 0; i + 1 < lines.length; i++) {
      final m = reg.firstMatch('${lines[i]} ${lines[i + 1]}');
      if (m != null) {
        return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
      }
    }
    final m = reg.firstMatch(normLines.replaceAll('\n', ' '));
    if (m != null) {
      return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
    }
    return null;
  }

  String? _extractStrictLegacyRegionPlate(String text) {
    final normLines = _normalizePreserveNewlines(text);
    final regions = _KoreanPlatePolicy.regionAlternation();
    final reg = RegExp(
      '($regions)$_plateSepPattern(\\d{1,2})$_plateSepPattern([가-힣])$_plateSepPattern(\\d{4})',
    );
    final lines = normLines.split('\n');
    for (final line in lines) {
      final m = reg.firstMatch(line);
      if (m != null) {
        return '${m.group(1)!}${m.group(2)!}${m.group(3)!}${m.group(4)!}';
      }
    }
    for (int i = 0; i + 1 < lines.length; i++) {
      final m = reg.firstMatch('${lines[i]} ${lines[i + 1]}');
      if (m != null) {
        return '${m.group(1)!}${m.group(2)!}${m.group(3)!}${m.group(4)!}';
      }
    }
    final m = reg.firstMatch(normLines.replaceAll('\n', ' '));
    if (m != null) {
      return '${m.group(1)!}${m.group(2)!}${m.group(3)!}${m.group(4)!}';
    }
    return null;
  }

  String? _extractStrictKoreanPlate(String text) {
    final modern = _extractStrictModernPlate(text);
    if (modern != null) return modern;
    return _extractStrictLegacyRegionPlate(text);
  }

  String? _extractLooseModernPlate(String text,
      {required VoidCallback onUseLearningMid}) {
    final norm = _normalizeFlat(text);
    final reg = RegExp(
      '(?<!\\d)(\\d{2,3})$_plateSepPattern([가-힣])$_plateSepPattern(\\d{4})(?!\\d)',
    );
    for (final m in reg.allMatches(norm)) {
      final mid =
      _normalizeMidToken(m.group(2)!, onUseLearningMid: onUseLearningMid);
      if (!_KoreanPlatePolicy.allowedNewMids.contains(mid)) continue;
      return '${m.group(1)!}$mid${m.group(3)!}';
    }
    return null;
  }

  String? _extractLooseLegacyRegionPlate(String text,
      {required VoidCallback onUseLearningMid}) {
    final norm = _normalizeFlat(text);
    final regions = _KoreanPlatePolicy.regionAlternation();
    final reg = RegExp(
      '($regions)$_plateSepPattern(\\d{1,2})$_plateSepPattern([가-힣])$_plateSepPattern(\\d{4})',
    );
    for (final m in reg.allMatches(norm)) {
      final mid =
      _normalizeMidToken(m.group(3)!, onUseLearningMid: onUseLearningMid);
      if (!RegExp(r'^[가-힣]$').hasMatch(mid)) continue;
      return '${m.group(1)!}${m.group(2)!}$mid${m.group(4)!}';
    }
    return null;
  }

  String? _extractLooseKoreanPlate(String text,
      {required VoidCallback onUseLearningMid}) {
    final modern =
    _extractLooseModernPlate(text, onUseLearningMid: onUseLearningMid);
    if (modern != null) return modern;
    return _extractLooseLegacyRegionPlate(text,
        onUseLearningMid: onUseLearningMid);
  }

  List<String> _extractModernCandidatesAnyChar(String text,
      {required VoidCallback onUseLearningMid}) {
    final norm = _normalizeFlat(text);
    final reg = RegExp(r'(\d{2,3})\s*(.{1,2})\s*(\d{4})');
    final out = <String>{};
    for (final m in reg.allMatches(norm)) {
      final front = m.group(1)!;
      final token = _normalizeCandidateKey(m.group(2)!);
      final back = m.group(3)!;
      if (token.isEmpty || token.length > 2) continue;

      final directKey = '$front$token$back';
      final mapped = _dynCandidateMap[directKey];
      if (mapped != null && _isModernPlate(mapped)) {
        out.add(_normalizeCandidateKey(mapped));
      }

      final mid = _normalizeMidToken(token, onUseLearningMid: onUseLearningMid);
      if (_KoreanPlatePolicy.allowedNewMids.contains(mid)) {
        out.add('$front$mid$back');
      }
    }
    return out.toList();
  }

  List<String> _extractLegacyRegionCandidates(String text) {
    final norm = _normalizeFlat(text);
    final regions = _KoreanPlatePolicy.regionAlternation();
    final reg = RegExp('($regions)\\s*(\\d{1,2})\\s*([가-힣])\\s*(\\d{4})');
    final out = <String>{};
    for (final m in reg.allMatches(norm)) {
      final plate = '${m.group(1)!}${m.group(2)!}${m.group(3)!}${m.group(4)!}';
      if (_isLegacyRegionPlate(plate)) {
        out.add(plate);
      }
    }
    return out.toList();
  }

  List<String> _extractDigitsOnlyNoMidCandidates(
      List<_StructuredWeakCandidate> candidates,
      ) {
    final out = <String>{};
    for (final candidate in candidates) {
      if (RegExp(r'^\d{6,8}$').hasMatch(candidate.rawValue)) {
        out.add(candidate.rawValue);
      }
    }
    return out.toList();
  }

  List<String> _extractByGeometryCandidates(RecognizedText result) {
    final outs = <String>{};
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final els = line.elements;
        if (els.length < 6) continue;
        final digits = <(TextElement el, Rect box)>[];
        for (final el in els) {
          if (RegExp(r'^\d$').hasMatch(el.text)) {
            digits.add((el, el.boundingBox));
          }
        }
        if (digits.length < 6) continue;
        final centers = digits.map((entry) => entry.$2.center).toList();
        final fit = _fitLine(centers);
        final slope = fit?.slope.clamp(-1.0, 1.0).toDouble() ?? 0.0;
        final axisLength = math.sqrt(1 + slope * slope);
        final axis = Offset(1 / axisLength, slope / axisLength);
        double projection(Rect box) =>
            box.center.dx * axis.dx + box.center.dy * axis.dy;
        digits.sort((a, b) => projection(a.$2).compareTo(projection(b.$2)));
        for (int i = digits.length - 4; i >= 0; i--) {
          final win = digits.sublist(i, i + 4);
          final heights = win.map((e) => e.$2.height).toList();
          final hMax = heights.reduce(math.max);
          final hMin = heights.reduce(math.min);
          if (hMin <= 0 || hMax / hMin > 2.15) continue;
          var smoothHeight = true;
          for (var j = 1; j < heights.length; j++) {
            final ratio = heights[j] / heights[j - 1];
            if (ratio < .56 || ratio > 1.78) {
              smoothHeight = false;
              break;
            }
          }
          if (!smoothHeight) continue;
          final projectedCenters = win.map((e) => projection(e.$2)).toList();
          var gapOk = true;
          for (var j = 1; j < projectedCenters.length; j++) {
            final gap = projectedCenters[j] - projectedCenters[j - 1];
            if (gap < hMin * .12 || gap > hMax * 1.75) {
              gapOk = false;
              break;
            }
          }
          if (!gapOk) continue;
          final back = win.map((e) => e.$1.text).join();
          final left = digits.sublist(0, i);
          if (left.length == 2 || left.length == 3) {
            final front = left.map((e) => e.$1.text).join();
            outs.add('$front$back');
          }
        }
      }
    }
    return outs.toList();
  }

  List<String> _extractWeakRecoverableCandidates(
      List<_StructuredWeakCandidate> candidates, {
        required VoidCallback onUseLearningMid,
      }) {
    final out = <String>{};
    for (final candidate in candidates) {
      final mapped = _dynCandidateMap[candidate.rawValue];
      if (mapped != null && _isModernPlate(mapped)) {
        out.add(_normalizeCandidateKey(mapped));
      }

      if (candidate.observedToken.isNotEmpty) {
        final mid = _normalizeMidToken(
          candidate.observedToken,
          onUseLearningMid: onUseLearningMid,
        );
        if (_KoreanPlatePolicy.allowedNewMids.contains(mid)) {
          out.add('${candidate.front}$mid${candidate.back}');
        }
      } else {
        final learnedMissingMid = _dynMidMap[''];
        if (learnedMissingMid != null &&
            _KoreanPlatePolicy.allowedNewMids.contains(learnedMissingMid)) {
          out.add('${candidate.front}$learnedMissingMid${candidate.back}');
          onUseLearningMid();
        }
      }
    }
    return out.toList();
  }

  List<String> _weakParseSources(RecognizedText result) {
    final out = <String>[];
    final seen = <String>{};

    void add(String value) {
      final normalized = _normalizeWeakSource(value);
      if (normalized.isEmpty || !seen.add(normalized)) return;
      out.add(normalized);
    }

    for (final block in result.blocks) {
      final lines = block.lines;
      for (var i = 0; i < lines.length; i++) {
        add(lines[i].text);
        if (i + 1 < lines.length) {
          add('${lines[i].text} ${lines[i + 1].text}');
        }
      }
    }
    return out;
  }

  List<String> _extractWeakDigitSequences(String source) {
    final sep = r'[\s\.\-·•_]*';
    final reg = RegExp(
      '(?<![0-9A-Za-z])(\\d(?:$sep\\d){5,7})(?![0-9A-Za-z])',
    );
    final out = <String>{};
    for (final match in reg.allMatches(source)) {
      final digits = match.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 6 && digits.length <= 8) {
        out.add(digits);
      }
    }
    return out.toList();
  }

  List<_StructuredWeakCandidate> _extractStructuredWeakCandidates(
      RecognizedText result,
      ) {
    final out = <_StructuredWeakCandidate>[];
    final seen = <String>{};

    void addCandidate({
      required String front,
      required String back,
      required String observedToken,
      required String rawValue,
      required int frontLen,
      required bool tokenMissing,
      required _WeakSegmentationEvidence segmentationEvidence,
    }) {
      if (back.length != 4) return;
      if (front.length < 2 || front.length > 3) return;
      final signature = '$front?$back';
      final score = _scoreStructuredWeakCandidate(
        front: front,
        back: back,
        observedToken: observedToken,
        frontLen: frontLen,
        tokenMissing: tokenMissing,
        segmentationEvidence: segmentationEvidence,
      );
      final key = '$signature|$rawValue|$observedToken';
      if (!seen.add(key)) return;
      out.add(
        _StructuredWeakCandidate(
          signature: signature,
          front: front,
          back: back,
          observedToken: observedToken,
          rawValue: rawValue,
          frontLen: frontLen,
          tokenMissing: tokenMissing,
          segmentationEvidence: segmentationEvidence,
          score: score,
        ),
      );
    }

    void addObservedTokenHypotheses({
      required String front,
      required String back,
      required String token,
      required String raw,
      required _WeakSegmentationEvidence mainEvidence,
      required _WeakSegmentationEvidence alternateEvidence,
      required bool includeAlternate,
    }) {
      addCandidate(
        front: front,
        back: back,
        observedToken: token,
        rawValue: raw,
        frontLen: front.length,
        tokenMissing: false,
        segmentationEvidence: mainEvidence,
      );
      if (!includeAlternate || front.length != 3 || token.length != 1) {
        return;
      }
      final alternateFront = front.substring(0, 2);
      final alternateToken = '${front.substring(2)}$token';
      addCandidate(
        front: alternateFront,
        back: back,
        observedToken: alternateToken,
        rawValue: raw,
        frontLen: 2,
        tokenMissing: false,
        segmentationEvidence: alternateEvidence,
      );
    }

    final sep = r'[\s\.\-·•_]*';
    final requiredSep = r'[\s\.\-·•_]+';
    final strongUnresolvedTokenReg = RegExp(
      '(?<![0-9A-Za-z])(\\d{2,3})$requiredSep([A-Za-z○#|]{1,2})$requiredSep(\\d{4})(?![0-9A-Za-z])',
    );
    final strongUnknownMidTokenReg = RegExp(
      '(?<![0-9A-Za-z가-힣])(\\d{2,3})$requiredSep([^0-9A-Za-z가-힣\\s\\.\\-·•_]{1,2})$requiredSep(\\d{4})(?![0-9A-Za-z가-힣])',
    );
    final strongUnresolvedHangulReg = RegExp(
      '(?<![0-9A-Za-z가-힣])(\\d{2,3})$requiredSep([가-힣])$requiredSep(\\d{4})(?![0-9A-Za-z가-힣])',
    );
    final unresolvedTokenReg = RegExp(
      '(?<![0-9A-Za-z])(\\d{2,3})$sep([A-Za-z○#|]{1,2})$sep(\\d{4})(?![0-9A-Za-z])',
    );
    final unknownMidTokenReg = RegExp(
      '(?<![0-9A-Za-z가-힣])(\\d{2,3})$sep([^0-9A-Za-z가-힣\\s\\.\\-·•_]{1,2})$sep(\\d{4})(?![0-9A-Za-z가-힣])',
    );
    final unresolvedHangulReg = RegExp(
      '(?<![0-9A-Za-z가-힣])(\\d{2,3})$sep([가-힣])$sep(\\d{4})(?![0-9A-Za-z가-힣])',
    );
    final separatedMissingMidReg = RegExp(
      '(?<![0-9A-Za-z])(\\d{2,3})$requiredSep(\\d{4})(?![0-9A-Za-z])',
    );

    for (final source in _weakParseSources(result)) {
      final explicitMissingRuns = <String>{};

      for (final match in strongUnresolvedTokenReg.allMatches(source)) {
        final front = match.group(1)!;
        final token = match.group(2)!;
        final back = match.group(3)!;
        addCandidate(
          front: front,
          back: back,
          observedToken: token,
          rawValue: '$front$token$back',
          frontLen: front.length,
          tokenMissing: false,
          segmentationEvidence: _WeakSegmentationEvidence.explicit,
        );
      }

      for (final match in strongUnknownMidTokenReg.allMatches(source)) {
        final front = match.group(1)!;
        final token = match.group(2)!;
        final back = match.group(3)!;
        addCandidate(
          front: front,
          back: back,
          observedToken: token,
          rawValue: '$front$token$back',
          frontLen: front.length,
          tokenMissing: false,
          segmentationEvidence: _WeakSegmentationEvidence.explicit,
        );
      }

      for (final match in strongUnresolvedHangulReg.allMatches(source)) {
        final front = match.group(1)!;
        final token = match.group(2)!;
        final back = match.group(3)!;
        final normalized = _normalizeMidToken(
          token,
          onUseLearningMid: () {},
        );
        if (_KoreanPlatePolicy.allowedNewMids.contains(normalized)) {
          continue;
        }
        addCandidate(
          front: front,
          back: back,
          observedToken: token,
          rawValue: '$front$token$back',
          frontLen: front.length,
          tokenMissing: false,
          segmentationEvidence: _WeakSegmentationEvidence.explicit,
        );
      }

      for (final match in unresolvedTokenReg.allMatches(source)) {
        final front = match.group(1)!;
        final token = match.group(2)!;
        final back = match.group(3)!;
        addObservedTokenHypotheses(
          front: front,
          back: back,
          token: token,
          raw: '$front$token$back',
          mainEvidence: _WeakSegmentationEvidence.observedSlot,
          alternateEvidence: _WeakSegmentationEvidence.inferred,
          includeAlternate: true,
        );
      }

      for (final match in unknownMidTokenReg.allMatches(source)) {
        final front = match.group(1)!;
        final token = match.group(2)!;
        final back = match.group(3)!;
        addObservedTokenHypotheses(
          front: front,
          back: back,
          token: token,
          raw: '$front$token$back',
          mainEvidence: _WeakSegmentationEvidence.numericSlot,
          alternateEvidence: _WeakSegmentationEvidence.numericSlot,
          includeAlternate: true,
        );
      }

      for (final match in separatedMissingMidReg.allMatches(source)) {
        final front = match.group(1)!;
        final back = match.group(2)!;
        final raw = '$front$back';
        explicitMissingRuns.add(raw);
        addCandidate(
          front: front,
          back: back,
          observedToken: '',
          rawValue: raw,
          frontLen: front.length,
          tokenMissing: true,
          segmentationEvidence: _WeakSegmentationEvidence.explicit,
        );
      }

      for (final match in unresolvedHangulReg.allMatches(source)) {
        final front = match.group(1)!;
        final token = match.group(2)!;
        final back = match.group(3)!;
        final normalized = _normalizeMidToken(
          token,
          onUseLearningMid: () {},
        );
        if (_KoreanPlatePolicy.allowedNewMids.contains(normalized)) {
          continue;
        }
        addObservedTokenHypotheses(
          front: front,
          back: back,
          token: token,
          raw: '$front$token$back',
          mainEvidence: _WeakSegmentationEvidence.observedSlot,
          alternateEvidence: _WeakSegmentationEvidence.inferred,
          includeAlternate: true,
        );
      }

      for (final digits in _extractWeakDigitSequences(source)) {
        if (digits.length == 8) {
          addCandidate(
            front: digits.substring(0, 3),
            back: digits.substring(4),
            observedToken: digits.substring(3, 4),
            rawValue: digits,
            frontLen: 3,
            tokenMissing: false,
            segmentationEvidence: _WeakSegmentationEvidence.numericSlot,
          );
          addCandidate(
            front: digits.substring(0, 2),
            back: digits.substring(4),
            observedToken: digits.substring(2, 4),
            rawValue: digits,
            frontLen: 2,
            tokenMissing: false,
            segmentationEvidence: _WeakSegmentationEvidence.numericSlot,
          );
          continue;
        }

        if (digits.length == 7) {
          if (explicitMissingRuns.contains(digits)) {
            continue;
          }
          addCandidate(
            front: digits.substring(0, 3),
            back: digits.substring(3),
            observedToken: '',
            rawValue: digits,
            frontLen: 3,
            tokenMissing: true,
            segmentationEvidence: _WeakSegmentationEvidence.inferred,
          );
          addCandidate(
            front: digits.substring(0, 2),
            back: digits.substring(3),
            observedToken: digits.substring(2, 3),
            rawValue: digits,
            frontLen: 2,
            tokenMissing: false,
            segmentationEvidence: _WeakSegmentationEvidence.inferred,
          );
          continue;
        }

        if (digits.length == 6) {
          if (explicitMissingRuns.contains(digits)) {
            continue;
          }
          addCandidate(
            front: digits.substring(0, 2),
            back: digits.substring(2),
            observedToken: '',
            rawValue: digits,
            frontLen: 2,
            tokenMissing: true,
            segmentationEvidence: _WeakSegmentationEvidence.inferred,
          );
        }
      }
    }

    return out;
  }

  List<_StructuredWeakCandidate>
      _augmentStructuredWeakCandidatesWithPersistentIdentity(
    RecognizedText result,
    List<_StructuredWeakCandidate> current,
  ) {
    if (_weakStructuredFrames.isEmpty) return current;
    final out = List<_StructuredWeakCandidate>.from(current);
    final seen = <String>{
      for (final candidate in current)
        '${candidate.signature}|${candidate.rawValue}|${candidate.observedToken}',
    };
    final identities = <String>{..._weakStructuredBest.keys};
    for (final frame in _weakStructuredFrames) {
      identities.addAll(frame);
    }
    final sources = _weakParseSources(result);

    void addCandidate(
      String signature,
      String front,
      String back,
      String token,
      String raw,
    ) {
      if (token.length > 2) return;
      final evidence = _WeakSegmentationEvidence.persistentBridge;
      final key = '$signature|$raw|$token';
      if (!seen.add(key)) return;
      out.add(
        _StructuredWeakCandidate(
          signature: signature,
          front: front,
          back: back,
          observedToken: token,
          rawValue: raw,
          frontLen: front.length,
          tokenMissing: token.isEmpty,
          segmentationEvidence: evidence,
          score: _scoreStructuredWeakCandidate(
            front: front,
            back: back,
            observedToken: token,
            frontLen: front.length,
            tokenMissing: token.isEmpty,
            segmentationEvidence: evidence,
          ) + .65,
        ),
      );
    }

    for (final signature in identities) {
      if (_exactWeakVoteCount(signature) < 1) continue;
      final split = _splitRefocusSignature(signature);
      if (split == null) continue;
      final front = split.front;
      final back = split.back;
      for (final source in sources) {
        for (final match in RegExp(r'\d{6,8}').allMatches(source)) {
          final digits = match.group(0)!;
          if (!digits.startsWith(front) || !digits.endsWith(back)) continue;
          final middleStart = front.length;
          final middleEnd = digits.length - back.length;
          if (middleEnd < middleStart) continue;
          final token = digits.substring(middleStart, middleEnd);
          if (token.length > 2) continue;
          addCandidate(signature, front, back, token, digits);
        }

        final compact = source.replaceAll(RegExp(r'[\s\.\-·•_]+'), '');
        final pattern = RegExp(
          '${RegExp.escape(front)}([0-9A-Za-z○#|]{1,2})${RegExp.escape(back)}',
        );
        for (final match in pattern.allMatches(compact)) {
          final token = match.group(1)!;
          final raw = '$front$token$back';
          addCandidate(signature, front, back, token, raw);
        }
      }
    }

    return out;
  }

  double _scoreStructuredWeakCandidate({
    required String front,
    required String back,
    required String observedToken,
    required int frontLen,
    required bool tokenMissing,
    required _WeakSegmentationEvidence segmentationEvidence,
  }) {
    var score = 1.0;
    switch (segmentationEvidence) {
      case _WeakSegmentationEvidence.explicit:
        score += 3.0;
        break;
      case _WeakSegmentationEvidence.observedSlot:
        score += 2.0;
        break;
      case _WeakSegmentationEvidence.numericSlot:
        score += 0.7;
        break;
      case _WeakSegmentationEvidence.persistentBridge:
        score += 0.35;
        break;
      case _WeakSegmentationEvidence.inferred:
        break;
    }
    if (frontLen == 3) {
      score += 0.8;
    } else {
      score += 0.5;
    }
    if (_preferredFrontLen != null && _preferredFrontLen == frontLen) {
      score += 0.9;
    }
    if (tokenMissing) {
      score += 0.5;
    }
    if (observedToken.isNotEmpty && observedToken.length <= 2) {
      score += 0.4;
    }
    if (_genericWeakMidHints.containsKey(observedToken)) {
      score += 0.6;
    }
    final dynSuggestions = _dynamicWeakMidSuggestions(
        front: front, back: back, observedToken: observedToken);
    if (dynSuggestions.isNotEmpty) {
      score += 1.2;
    }
    return score;
  }

  List<String> _dynamicWeakMidSuggestions({
    required String front,
    required String back,
    required String observedToken,
  }) {
    final mids = <String>{};
    if (observedToken.isNotEmpty) {
      final mapped = _dynMidMap[observedToken];
      if (mapped != null &&
          _KoreanPlatePolicy.allowedNewMids.contains(mapped)) {
        mids.add(mapped);
      }
    }
    for (final entry in _dynCandidateMap.entries) {
      final mapped = _normalizeCandidateKey(entry.value);
      final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(mapped);
      if (m == null) continue;
      if (m.group(1) == front && m.group(3) == back) {
        mids.add(m.group(2)!);
      }
    }
    return mids.toList()..sort();
  }

  List<String> _inferWeakMidSuggestions(_StructuredWeakCandidate candidate) {
    final scoreMap = <String, double>{};

    void bump(String mid, double delta) {
      if (!_KoreanPlatePolicy.allowedNewMids.contains(mid)) return;
      scoreMap[mid] = (scoreMap[mid] ?? 0) + delta;
    }

    final observedEvidence =
    _weakStructuredObservedHangulVotes[candidate.signature];
    if (observedEvidence != null && observedEvidence.isNotEmpty) {
      final observedEntries = observedEvidence.entries.toList()
        ..sort((a, b) {
          final c = b.value.compareTo(a.value);
          if (c != 0) return c;
          return a.key.compareTo(b.key);
        });
      for (var i = 0; i < observedEntries.length; i++) {
        final entry = observedEntries[i];
        bump(entry.key, 12.0 + (entry.value * 3.0) - (i * 0.2));
      }
    }

    final dynamicSuggestions = _dynamicWeakMidSuggestions(
      front: candidate.front,
      back: candidate.back,
      observedToken: candidate.observedToken,
    );
    for (var i = 0; i < dynamicSuggestions.length; i++) {
      bump(dynamicSuggestions[i], 3.6 - (i * 0.25));
    }

    final genericSuggestions =
        _genericWeakMidHints[candidate.observedToken] ?? const <String>[];
    for (var i = 0; i < genericSuggestions.length; i++) {
      bump(genericSuggestions[i], 2.4 - (i * 0.45));
    }

    if (candidate.tokenMissing) {
      final missingSuggestions = _genericWeakMidHints[''] ?? const <String>[];
      for (var i = 0; i < missingSuggestions.length; i++) {
        bump(missingSuggestions[i], 1.6 - (i * 0.25));
      }
    }

    if (_preferredFrontLen != null &&
        _preferredFrontLen == candidate.frontLen) {
      for (final mid in scoreMap.keys.toList()) {
        scoreMap[mid] = (scoreMap[mid] ?? 0) + 0.35;
      }
    }

    if (scoreMap.isEmpty) {
      for (final fallback in ['러', '부', '누', '육', '조', '허', '어', '저']) {
        bump(fallback, 0.5);
      }
    }

    final ranked = scoreMap.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });

    return ranked.take(5).map((e) => e.key).toList();
  }

  bool _looksLikeWeakModernPattern(String normalized) {
    if (RegExp(r'^\d{6,8}$').hasMatch(normalized)) return true;
    if (RegExp(r'^\d{2,3}[^가-힣]\d{4}$').hasMatch(normalized)) return true;
    return false;
  }

  String? _extractForceInsertCandidate(String text) {
    final modern = _extractForceInsertModern(text);
    if (modern != null) return modern;
    final legacy = _extractStrictLegacyRegionPlate(text);
    if (legacy != null) return legacy;
    return null;
  }

  String? _extractForceInsertModern(String text) {
    final norm = _normalizeFlat(text);
    final m = RegExp(r'(\d{2,3})\s*(.{1,2})\s*(\d{4})').firstMatch(norm);
    if (m == null) return null;
    final front = m.group(1)!;
    final token = _normalizeCandidateKey(m.group(2)!);
    final back = m.group(3)!;
    final mapped = _dynCandidateMap['$front$token$back'];
    if (mapped != null && _isModernPlate(mapped)) {
      return _normalizeCandidateKey(mapped);
    }
    if (RegExp(r'^[가-힣]$').hasMatch(token)) {
      return '$front$token$back';
    }
    return null;
  }

  List<String> _rankAllCandidates(List<String> list,
      {Set<String> prioritized = const {}}) {
    final uniq = list.map(_normalizeCandidateKey).toSet().toList();
    double score(String s) {
      if (prioritized.contains(s)) return -1;
      if (_isModernPlate(s)) return 0;
      if (_isLegacyRegionPlate(s)) return 0.2;
      if (RegExp(r'^\d{6,8}$').hasMatch(s)) return 1;
      return 9;
    }

    uniq.sort((a, b) {
      final c = score(a).compareTo(score(b));
      if (c != 0) return c;
      return a.compareTo(b);
    });
    return uniq;
  }

  List<String> _rankStructuredWeakLogs(List<_StructuredWeakCandidate> frame) {
    final ranked = _rankStructuredWeakCandidates(frame);
    return ranked
        .map((e) {
          final resolved = _resolveFrontFromEvidence(e.back, frame);
          final discriminative = _hasDiscriminativeSegmentationEvidence(
            e.back,
            e.front,
            frame,
          );
          return '${e.front}?${e.back}:${e.rawValue}:'
              'token=${e.observedToken.isEmpty ? '-' : e.observedToken}:'
              'evidence=${e.segmentationEvidence.name}:'
              'discriminative=$discriminative:'
              'votes=${_exactWeakVoteCount(e.signature)}:'
              'resolved=${resolved ?? '-'}';
        })
        .toList();
  }

  List<_StructuredWeakCandidate> _rankStructuredWeakCandidates(
      List<_StructuredWeakCandidate> frame) {
    final merged = <String, _StructuredWeakCandidate>{};
    for (final c in frame) {
      final prev = merged[c.signature];
      if (prev == null || c.score > prev.score) {
        merged[c.signature] = c;
      }
    }
    final out = merged.values.toList();
    out.sort((a, b) {
      final aResolved = _resolveFrontFromEvidence(a.back, frame) == a.front;
      final bResolved = _resolveFrontFromEvidence(b.back, frame) == b.front;
      if (aResolved != bResolved) return bResolved ? 1 : -1;
      final voteCmp = _exactWeakVoteCount(b.signature)
          .compareTo(_exactWeakVoteCount(a.signature));
      if (voteCmp != 0) return voteCmp;
      final evidenceCmp = _segmentationEvidenceWeight(b.segmentationEvidence)
          .compareTo(_segmentationEvidenceWeight(a.segmentationEvidence));
      if (evidenceCmp != 0) return evidenceCmp;
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return a.signature.compareTo(b.signature);
    });
    return out;
  }

  String _deriveFailureReason({
    required String allText,
    required Set<String> stableFrame,
    required Set<String> tentativeFrame,
    required Set<String> weakFrame,
  }) {
    if (stableFrame.isNotEmpty) return 'candidate_ready';
    if (tentativeFrame.isNotEmpty) return 'tentative_candidate_ready';
    if (weakFrame.isNotEmpty) return 'weak_candidate_ready';
    if (_extractStrictLegacyRegionPlate(allText) == null &&
        RegExp(_KoreanPlatePolicy.regionAlternation())
            .hasMatch(_normalizeFlat(allText))) {
      return 'legacy_format_detected_but_unstable';
    }
    if (RegExp(r'(?<!\d)\d{8}(?!\d)')
        .hasMatch(_normalizeCandidateKey(allText))) {
      return 'mid_missing_from_8digit_pattern';
    }
    if (RegExp(r'(?<!\d)\d{2,3}[A-Za-z\|1IlL4]{1,2}\d{4}(?!\d)')
        .hasMatch(_normalizeFlat(allText))) {
      return 'mid_non_hangul_repeated';
    }
    if (RegExp(r'(?<!\d)\d{6,8}(?!\d)').hasMatch(_normalizeFlat(allText))) {
      return 'mid_missing_or_non_hangul';
    }
    return 'no_reliable_candidate';
  }

  List<String> _compressCandidatesForLearning(List<String> values) {
    final out = <String>{};
    for (final v in values) {
      final n = _normalizeCandidateKey(v);
      if (_isValidKoreanPlate(n) || RegExp(r'^\d{6,8}$').hasMatch(n)) {
        out.add(n);
      }
    }
    return out.toList()..sort();
  }

  String _learningFormatTag(String plate) {
    final normalized = _normalizeCandidateKey(plate);
    final format = _plateFormatOf(normalized);
    switch (format) {
      case _KoreanPlateFormat.modern:
        return 'modern';
      case _KoreanPlateFormat.legacyRegion:
        return 'legacyRegion';
      default:
        return 'unknown';
    }
  }

  Future<LiveOcrCompleteAction> _handleCompleteCandidate({
    required String plate,
    required LiveOcrCompleteSource source,
    required LiveOcrExitType exitType,
    required String detail,
    required bool? geometryReliable,
  }) async {
    final normalizedPlate = _normalizeCandidateKey(plate);
    if (!_isValidKoreanPlate(normalizedPlate)) {
      _lastCompleteDecision =
          'plate=$normalizedPlate source=${source.name} action=reject reason=invalidPlate';
      _appendLog(
        'complete candidate reject plate=$normalizedPlate '
        'source=${source.name} reason=invalidPlate',
      );
      return LiveOcrCompleteAction.reject;
    }

    final decision = widget.coordinator.evaluateCompleteCandidate(
      LiveOcrCompleteObservation(
        plate: normalizedPlate,
        attempt: _attempt,
        source: source,
        geometryReliable: geometryReliable,
        capturedAt: DateTime.now(),
      ),
    );
    _lastCompleteDecision =
        'plate=$normalizedPlate source=${source.name} '
        'action=${decision.action.name} reason=${decision.reason} '
        'completeVotes=${decision.completeVotes} '
        'identityFrames=${decision.identityFrames}';
    _appendLog(
      'complete candidate plate=$normalizedPlate source=${source.name} '
      'action=${decision.action.name} reason=${decision.reason} '
      'completeVotes=${decision.completeVotes} '
      'identityFrames=${decision.identityFrames}',
    );

    if (decision.action == LiveOcrCompleteAction.reject) {
      _ocrDebugRecoveredPlate = null;
      _setOcrDebugStage(
        _OcrDebugStage.fallback,
        detail: 'completeRejected:$normalizedPlate',
        structuredPlate: normalizedPlate,
      );
      return decision.action;
    }

    if (decision.action == LiveOcrCompleteAction.defer) {
      _ocrDebugRecoveredPlate = null;
      _setOcrDebugStage(
        _OcrDebugStage.fallback,
        detail: 'temporalPending:$normalizedPlate',
        structuredPlate: normalizedPlate,
      );
      return decision.action;
    }

    _setOcrDebugStage(
      _OcrDebugStage.recovered,
      detail: detail,
      recoveredPlate: normalizedPlate,
    );
    await _holdDeveloperVisualization();
    await _finishAndPop(
      plate: normalizedPlate,
      exitType: exitType,
    );
    return decision.action;
  }

  Future<void> _finishAndPop({
    required LiveOcrExitType exitType,
    String? plate,
    String? selectedChipLabel,
    String? weakFront,
    String? weakBack,
    String? weakObservedValue,
    bool requiresMidCompletion = false,
    List<String> weakMidSuggestions = const [],
  }) async {
    if (_completed) return;
    _completed = true;
    _stopAuto();

    final normalizedPlate =
    plate == null ? null : _normalizeCandidateKey(plate);
    final validForLearning =
        normalizedPlate != null && _isValidKoreanPlate(normalizedPlate);

    try {
      if (validForLearning) {
        final learningKey = [
          _normalizeCandidateKey(_lastText ?? ''),
          normalizedPlate,
          _learningFormatTag(normalizedPlate),
        ].join('|');
        if (_lastSavedLearningKey != learningKey) {
          await _learningRepo.upsertPending(
            sessionId: widget.sessionId,
            lastText: _lastText,
            candidates: _compressCandidatesForLearning(_candidateChips),
            selectedCandidate: normalizedPlate,
            attemptCount: _attempt,
            torchOn: _torch,
            forceInsertOn: _allowForceInsert,
            usedLearningMid: _usedLearningMidLast,
            usedLearningRank: _usedLearningRankLast,
          );
          _lastSavedLearningKey = learningKey;
          _appendLog('학습 저장 selected=$normalizedPlate');
        } else {
          _appendLog('학습 저장 생략 duplicate=$normalizedPlate');
        }
      } else {
        _appendLog('학습 저장 생략 invalidPlate=${normalizedPlate ?? '-'}');
      }
    } catch (e) {
      _appendLog('학습 저장 오류 $e');
    }

    if (!mounted) return;
    final result = LiveOcrSessionResult(
      sessionId: widget.sessionId,
      plate: normalizedPlate,
      exitType: exitType,
      logs: List<String>.from(_sessionLogs, growable: false),
      candidateValues: List<String>.from(_candidateChips, growable: false),
      selectedChipLabel: selectedChipLabel,
      lastOcrText: _lastText,
      lastFailureReason: _lastFailureReason,
      attemptCount: _attempt,
      usedLearningMid: _usedLearningMidLast,
      usedLearningRank: _usedLearningRankLast,
      weakFront: weakFront,
      weakBack: weakBack,
      weakObservedValue: weakObservedValue,
      requiresMidCompletion: requiresMidCompletion,
      weakMidSuggestions:
          List<String>.from(weakMidSuggestions, growable: false),
    );
    final onExitPreparing = widget.onExitPreparing;
    if (onExitPreparing != null) {
      try {
        _appendLog('종료 전 목적 화면 준비 시작 type=${exitType.name}');
        await onExitPreparing(result);
        _appendLog('종료 전 목적 화면 준비 완료 type=${exitType.name}');
      } catch (error, stackTrace) {
        _appendLog('종료 전 목적 화면 준비 오류 $error');
        debugPrint(
          '[LiveOCR] exit_prepare_failed type=${exitType.name} error=$error\n$stackTrace',
        );
      }
    }
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  void _showLearningDialog() {
    final committed = _learningSummary?.committedCount ?? 0;
    final pending = _learningSummary?.pendingCount ?? 0;
    final dynCnt = _dynMidMap.length;
    final pref = _preferredFrontLen;
    final lastMs = _learningSummary?.lastCommittedAtMs;
    final lastText = lastMs == null
        ? '없음'
        : DateTime.fromMillisecondsSinceEpoch(lastMs).toLocal().toString();

    showCommonOverlayDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        final textTheme = Theme.of(dialogContext).textTheme;
        Widget row(String label, String value) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }

        return CommonDialogFrame(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: tokens.infoContainer,
                        borderRadius: BorderRadius.circular(CommonUiShapes.control),
                        border: Border.all(color: tokens.info.withOpacity(.36)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.school_rounded, color: tokens.info),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '학습 데이터 상태',
                        style: textTheme.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                row('커밋', '$committed건'),
                row('대기', '$pending건'),
                row('동적 mid 보정맵', '$dynCnt개'),
                row('후보 보정맵', '${_dynCandidateMap.length}개'),
                row('선호 앞자리 길이', '${pref ?? '-'}'),
                row('마지막 커밋', lastText),
                const SizedBox(height: 4),
                Text(
                  '한국 차량 번호판 형식으로 검증된 값만 학습 저장에 반영합니다.',
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                CommonButton(
                  label: '닫기',
                  expand: true,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLogsDialog() {
    if (_developerMode) {
      unawaited(
        StatusDialog.showSuccess(
          context,
          title: 'Live OCR 개발자 상태',
          description: _developerStatusDescription,
          copyText: _debugPrintCode,
          copyButtonLabel: 'debugPrint 코드 복사',
          visibleDuration: const Duration(minutes: 5),
          useCommonUi: true,
        ),
      );
      return;
    }

    final logText = _sessionLogs.join('\n');
    showCommonOverlayDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        return CommonDialogFrame(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: tokens.infoContainer,
                        borderRadius: BorderRadius.circular(CommonUiShapes.control),
                        border: Border.all(color: tokens.info.withOpacity(.36)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.article_outlined, color: tokens.info),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '인식 로그',
                        style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceOverlay,
                      borderRadius: BorderRadius.circular(CommonUiShapes.control),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        logText.isEmpty ? '로그가 없습니다.' : logText,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '복사',
                        icon: Icons.copy_rounded,
                        variant: CommonButtonVariant.secondary,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: logText));
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CommonButton(
                        label: '닫기',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(builder: _buildCommonOcrPage),
    );
  }

  Widget _buildCommonOcrPage(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final cameraForeground =
    tokens.isDark ? tokens.textPrimary : tokens.onAccent;

    final cam = _controller;
    final preview = (!(_initialized && cam != null && cam.value.isInitialized))
        ? Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
      ),
    )
        : LayoutBuilder(
      builder: (ctx, constraints) {
        _previewSizeLogical =
            Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            if (_previewSizeLogical == null) return;
            final s = _previewSizeLogical!;
            final dx = (d.localPosition.dx / s.width).clamp(0.0, 1.0);
            final dy = (d.localPosition.dy / s.height).clamp(0.0, 1.0);
            final point = Offset(dx, dy);
            final revision = _tapFocusRevision + 1;
            setState(() {
              _tapFocusPoint = point;
              _tapFocusRevision = revision;
            });
            unawaited(_meterTo(point));
            unawaited(Future<void>.delayed(const Duration(milliseconds: 760), () {
              if (!mounted || _tapFocusRevision != revision) return;
              setState(() => _tapFocusPoint = null);
            }));
          },
          child: CameraPreview(
            cam,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _OcrPublicOverlay(
                  revision: _ocrDebugRevision,
                  stage: _ocrDebugStage,
                  sourcePlateBytes: _ocrDebugSourcePlateBytes,
                  rectifiedPlateBytes: _ocrDebugRectifiedPlateBytes,
                  cropBytes: _ocrDebugCropBytes,
                  localCropBytes: _ocrDebugLocalCropBytes,
                  midContextBytes: _ocrDebugMidContextBytes,
                  midGlyphBytes: _ocrDebugMidGlyphBytes,
                  previewPhase: _ocrRecoveryPreviewPhase,
                  localSlot: _ocrDebugLocalSlot,
                  focusPoint: _tapFocusPoint,
                  focusRevision: _tapFocusRevision,
                  showOperationCaption:
                      widget.coordinator.profile.showOperationCaption,
                ),
                if (_developerMode)
                  _OcrDebugOverlay(
                    revision: _ocrDebugRevision,
                    stage: _ocrDebugStage,
                    lineBoxes: _ocrDebugLineBoxes,
                    sourceImageSize: _ocrDebugSourceImageSize,
                    weakBox: _ocrDebugWeakBox,
                    cropBox: _ocrDebugCropBox,
                    localCropBox: _ocrDebugLocalCropBox,
                    midContextBox: _ocrDebugMidContextBox,
                    midLeftBox: _ocrDebugMidLeftBox,
                    midGlyphBox: _ocrDebugMidGlyphBox,
                    midRightBox: _ocrDebugMidRightBox,
                    localSlot: _ocrDebugLocalSlot,
                    focusPoint: _ocrDebugFocusPoint,
                    cropText: _ocrDebugCropText,
                    localCropText: _ocrDebugLocalCropText,
                    structuredPlate: _ocrDebugStructuredPlate,
                    recoveredPlate: _ocrDebugRecoveredPlate,
                    detail: _ocrDebugStageDetail,
                    captureMs: _ocrDebugCaptureMs,
                    fullOcrMs: _ocrDebugFullOcrMs,
                    cropOcrMs: _ocrDebugCropOcrMs,
                    localOcrMs: _ocrDebugLocalOcrMs,
                  ),
              ],
            ),
          ),
        );
      },
    );

    final hasLearning =
        (_learningSummary?.committedCount ?? 0) > 0 || _dynMidMap.isNotEmpty;
    final usedLearningNow = _usedLearningMidLast || _usedLearningRankLast;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final candidateAnimationKey = _displayChips.isEmpty
        ? 'empty:${_currentFailureReason ?? '-'}'
        : _displayChips
        .map((chip) =>
    '${chip.tier.name}:${chip.value}:${chip.requiresMidCompletion}')
        .join('|');

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        _appendLog('시스템 뒤로가기 종료');
        await _finishAndPop(exitType: LiveOcrExitType.userAborted);
      },
      child: Scaffold(
        backgroundColor: tokens.scrim,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: tokens.scrim,
          foregroundColor: cameraForeground,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          elevation: 0,
          surfaceTintColor: tokens.transparent,
          actions: [
            IconButton(
              tooltip: _developerMode ? '개발자 상태' : '인식 로그',
              onPressed: _showLogsDialog,
              icon: const Icon(Icons.article_outlined),
            ),
            IconButton(
              tooltip: hasLearning ? '학습 데이터 있음' : '학습 데이터 없음',
              onPressed: _learningLoaded ? _showLearningDialog : null,
              icon: Icon(hasLearning ? Icons.school : Icons.school_outlined),
            ),
            if (usedLearningNow)
              IconButton(
                tooltip: '학습 보정 적용 중',
                onPressed: _learningLoaded ? _showLearningDialog : null,
                icon: const Icon(Icons.auto_awesome),
              ),
            IconButton(
              tooltip: _allowForceInsert ? '강제삽입 ON' : '강제삽입 OFF',
              onPressed: () {
                setState(() => _allowForceInsert = !_allowForceInsert);
                _appendLog('강제삽입 ${_allowForceInsert ? 'ON' : 'OFF'}');
              },
              icon: Icon(_allowForceInsert
                  ? Icons.fact_check
                  : Icons.fact_check_outlined),
            ),
            IconButton(
              tooltip: _torch ? '토치 끄기' : '토치 켜기',
              onPressed: () async {
                try {
                  _torch = !_torch;
                  await _controller
                      ?.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
                  _appendLog('토치 ${_torch ? 'ON' : 'OFF'}');
                  if (mounted) {
                    setState(() {});
                  }
                } catch (_) {}
              },
              icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            ),
            IconButton(
              tooltip: _autoRunning ? '일시정지' : '재생',
              onPressed: () {
                if (_autoRunning) {
                  _stopAuto();
                } else {
                  _startAuto(resetSession: false);
                }
                if (mounted) {
                  setState(() {});
                }
              },
              icon: Icon(_autoRunning
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill),
            ),
            IconButton(
              tooltip: '닫기',
              onPressed: () async {
                _appendLog('사용자 종료');
                await _finishAndPop(exitType: LiveOcrExitType.userAborted);
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: preview),
            if (_debugText != null || _lastText != null || _learningLoaded)
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: tokens.scrim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_debugText != null)
                      Text(
                        _debugText!,
                        style: TextStyle(
                            color: cameraForeground.withOpacity(0.88), fontSize: 12),
                      ),
                    if (_lastText != null && _lastText!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '최근: $_lastText',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cameraForeground.withOpacity(0.72),
                              fontSize: 12),
                        ),
                      ),
                    if (_learningLoaded)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            _infoPill(
                              icon: hasLearning
                                  ? Icons.school
                                  : Icons.school_outlined,
                              text:
                              '학습 ${_learningSummary?.committedCount ?? 0}건',
                            ),
                            _infoPill(
                              icon: Icons.tune,
                              text: '보정맵 ${_dynMidMap.length}개',
                            ),
                            _infoPill(
                              icon: Icons.receipt_long,
                              text: '로그 ${_sessionLogs.length}줄',
                            ),
                            if (usedLearningNow)
                              _infoPill(
                                icon: Icons.auto_awesome,
                                text: '보정 적용',
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            CommonAnimatedReveal(
              delay: const Duration(milliseconds: 80),
              offset: const Offset(0, .035),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: true,
                minimum: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  color: tokens.scrim,
                  child: AnimatedSwitcher(
                    duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    reverseDuration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) {
                      final scale = Tween<double>(begin: 0.97, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: CommonUiMotion.enter,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<String>(candidateAnimationKey),
                      child: _buildCandidates(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPill({
    required IconData icon,
    required String text,
  }) {
    final tokens = CommonUiTheme.of(context);
    final foreground = tokens.isDark ? tokens.textPrimary : tokens.onAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised.withOpacity(tokens.isDark ? .72 : .16),
        border: Border.all(color: foreground.withOpacity(.28)),
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground.withOpacity(.92)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: foreground.withOpacity(.92),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidates() {
    final tokens = CommonUiTheme.of(context);
    if (_displayChips.isEmpty) {
      return const SizedBox(height: _chipBottomSpacer);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _displayChips.map((chip) {
            final backgroundColor = switch (chip.tier) {
              _ChipTier.stable => tokens.accent,
              _ChipTier.tentative => tokens.info,
              _ChipTier.weak => tokens.surfaceRaised,
            };
            final labelColor = switch (chip.tier) {
              _ChipTier.stable => tokens.onAccent,
              _ChipTier.tentative => tokens.onInfo,
              _ChipTier.weak => tokens.textPrimary,
            };
            return ActionChip(
              label: Text(chip.label),
              labelStyle:
              TextStyle(color: labelColor, fontWeight: FontWeight.w600),
              backgroundColor: backgroundColor,
              tooltip: '이 값으로 삽입',
              onPressed: () async {
                _appendLog('후보칩 선택 label=${chip.label} value=${chip.value}');
                if (chip.requiresMidCompletion) {
                  await _finishAndPop(
                    exitType: LiveOcrExitType.candidateChipSelected,
                    selectedChipLabel: chip.label,
                    weakFront: chip.weakFront,
                    weakBack: chip.weakBack,
                    weakObservedValue: chip.weakObservedValue ?? chip.value,
                    requiresMidCompletion: true,
                    weakMidSuggestions: chip.weakMidSuggestions,
                  );
                  return;
                }
                await _finishAndPop(
                  plate: chip.value,
                  exitType: LiveOcrExitType.candidateChipSelected,
                  selectedChipLabel: chip.label,
                );
              },
            );
          }).toList(),
        ),
        const SizedBox(height: _chipBottomSpacer),
      ],
    );
  }
}


class _OcrPublicOverlay extends StatelessWidget {
  const _OcrPublicOverlay({
    required this.revision,
    required this.stage,
    required this.sourcePlateBytes,
    required this.rectifiedPlateBytes,
    required this.cropBytes,
    required this.localCropBytes,
    required this.midContextBytes,
    required this.midGlyphBytes,
    required this.previewPhase,
    required this.localSlot,
    required this.focusPoint,
    required this.focusRevision,
    required this.showOperationCaption,
  });

  final int revision;
  final _OcrDebugStage stage;
  final Uint8List? sourcePlateBytes;
  final Uint8List? rectifiedPlateBytes;
  final Uint8List? cropBytes;
  final Uint8List? localCropBytes;
  final Uint8List? midContextBytes;
  final Uint8List? midGlyphBytes;
  final _OcrRecoveryPreviewPhase previewPhase;
  final _PlateRecoverySlot? localSlot;
  final Offset? focusPoint;
  final int focusRevision;
  final bool showOperationCaption;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
    reduceMotion ? Duration.zero : const Duration(milliseconds: 320);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (focusPoint != null)
            _OcrFocusReticle(
              key: ValueKey<String>('focus-$focusRevision'),
              point: focusPoint!,
              reduceMotion: reduceMotion,
            ),
          if (sourcePlateBytes != null ||
              rectifiedPlateBytes != null ||
              cropBytes != null ||
              localCropBytes != null ||
              midContextBytes != null ||
              midGlyphBytes != null)
            Positioned(
              right: 12,
              bottom: 78,
              child: _OcrRecoveryPreviewDock(
                sourcePlateBytes: sourcePlateBytes,
                rectifiedPlateBytes: rectifiedPlateBytes,
                cropBytes: cropBytes,
                localCropBytes: localCropBytes,
                midContextBytes: midContextBytes,
                midGlyphBytes: midGlyphBytes,
                previewPhase: previewPhase,
                localSlot: localSlot,
                reduceMotion: reduceMotion,
              ),
            ),
          if (showOperationCaption)
            Positioned(
              left: 18,
              right: 18,
              bottom: 14,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: const Offset(0, .24),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: offset,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .98, end: 1).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: _OcrOperationCaption(
                    key: ValueKey<String>('caption-${stage.name}-$revision'),
                    stage: stage,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OcrFocusReticle extends StatelessWidget {
  const _OcrFocusReticle({
    super.key,
    required this.point,
    required this.reduceMotion,
  });

  final Offset point;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment(
        point.dx * 2 - 1,
        point.dy * 2 - 1,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final pulse = reduceMotion
              ? 1.0
              : 1.18 - (.18 * Curves.easeOutBack.transform(value));
          return Opacity(
            opacity: (1 - value * .28).clamp(0.0, 1.0),
            child: Transform.scale(scale: pulse, child: child),
          );
        },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.primary.withOpacity(.94),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.24),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OcrRecoveryPreviewDock extends StatefulWidget {
  const _OcrRecoveryPreviewDock({
    required this.sourcePlateBytes,
    required this.rectifiedPlateBytes,
    required this.cropBytes,
    required this.localCropBytes,
    required this.midContextBytes,
    required this.midGlyphBytes,
    required this.previewPhase,
    required this.localSlot,
    required this.reduceMotion,
  });

  final Uint8List? sourcePlateBytes;
  final Uint8List? rectifiedPlateBytes;
  final Uint8List? cropBytes;
  final Uint8List? localCropBytes;
  final Uint8List? midContextBytes;
  final Uint8List? midGlyphBytes;
  final _OcrRecoveryPreviewPhase previewPhase;
  final _PlateRecoverySlot? localSlot;
  final bool reduceMotion;

  @override
  State<_OcrRecoveryPreviewDock> createState() =>
      _OcrRecoveryPreviewDockState();
}

class _OcrRecoveryPreviewDockState extends State<_OcrRecoveryPreviewDock> {
  Timer? _transitionTimer;
  Uint8List? _displayBytes;
  _OcrRecoveryPreviewPhase _displayPhase = _OcrRecoveryPreviewPhase.none;
  int? _lastRectifiedIdentity;
  int? _lastMidGlyphIdentity;

  @override
  void initState() {
    super.initState();
    _syncPreview(notify: false);
  }

  @override
  void didUpdateWidget(covariant _OcrRecoveryPreviewDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPreview(notify: true);
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    super.dispose();
  }

  void _applyPreview(
    Uint8List? bytes,
    _OcrRecoveryPreviewPhase phase, {
    required bool notify,
  }) {
    if (!notify) {
      _displayBytes = bytes;
      _displayPhase = phase;
      return;
    }
    if (!mounted) return;
    setState(() {
      _displayBytes = bytes;
      _displayPhase = phase;
    });
  }

  void _syncPreview({required bool notify}) {
    final incomingRectified = widget.rectifiedPlateBytes ?? widget.cropBytes;
    final incomingRectifiedIdentity =
        incomingRectified == null ? null : identityHashCode(incomingRectified);
    if (_transitionTimer?.isActive == true &&
        widget.previewPhase == _OcrRecoveryPreviewPhase.plateRectified &&
        widget.localCropBytes == null &&
        incomingRectifiedIdentity == _lastRectifiedIdentity) {
      return;
    }
    _transitionTimer?.cancel();
    _transitionTimer = null;

    if (widget.previewPhase == _OcrRecoveryPreviewPhase.midGlyph &&
        widget.midGlyphBytes != null) {
      final glyphIdentity = identityHashCode(widget.midGlyphBytes!);
      final shouldAnimateMid = !widget.reduceMotion &&
          widget.midContextBytes != null &&
          _lastMidGlyphIdentity != glyphIdentity;
      _lastMidGlyphIdentity = glyphIdentity;
      if (shouldAnimateMid) {
        _applyPreview(
          widget.midContextBytes,
          _OcrRecoveryPreviewPhase.midContext,
          notify: notify,
        );
        _transitionTimer = Timer(const Duration(milliseconds: 105), () {
          if (!mounted) return;
          _applyPreview(
            widget.midGlyphBytes,
            _OcrRecoveryPreviewPhase.midGlyph,
            notify: true,
          );
        });
      } else {
        _applyPreview(
          widget.midGlyphBytes,
          _OcrRecoveryPreviewPhase.midGlyph,
          notify: notify,
        );
      }
      return;
    }

    if (widget.previewPhase == _OcrRecoveryPreviewPhase.midContext &&
        widget.midContextBytes != null) {
      _applyPreview(
        widget.midContextBytes,
        _OcrRecoveryPreviewPhase.midContext,
        notify: notify,
      );
      return;
    }

    if (widget.previewPhase == _OcrRecoveryPreviewPhase.midFocused &&
        widget.localCropBytes != null) {
      _applyPreview(
        widget.localCropBytes,
        _OcrRecoveryPreviewPhase.midFocused,
        notify: notify,
      );
      return;
    }

    final rectified = incomingRectified;
    final source = widget.sourcePlateBytes;
    if (widget.previewPhase == _OcrRecoveryPreviewPhase.plateRectified &&
        rectified != null) {
      final rectifiedIdentity = identityHashCode(rectified);
      final shouldAnimateTransition = !widget.reduceMotion &&
          source != null &&
          _lastRectifiedIdentity != rectifiedIdentity;
      _lastRectifiedIdentity = rectifiedIdentity;
      if (shouldAnimateTransition) {
        _applyPreview(
          source,
          _OcrRecoveryPreviewPhase.plateDetected,
          notify: notify,
        );
        _transitionTimer = Timer(const Duration(milliseconds: 90), () {
          if (!mounted) return;
          _applyPreview(
            rectified,
            _OcrRecoveryPreviewPhase.plateRectified,
            notify: true,
          );
        });
      } else {
        _applyPreview(
          rectified,
          _OcrRecoveryPreviewPhase.plateRectified,
          notify: notify,
        );
      }
      return;
    }

    if (source != null) {
      _applyPreview(
        source,
        _OcrRecoveryPreviewPhase.plateDetected,
        notify: notify,
      );
      return;
    }

    _applyPreview(
      rectified,
      rectified == null
          ? _OcrRecoveryPreviewPhase.none
          : _OcrRecoveryPreviewPhase.plateRectified,
      notify: notify,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final duration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final isMidContext =
        _displayPhase == _OcrRecoveryPreviewPhase.midContext;
    final isMidGlyph =
        _displayPhase == _OcrRecoveryPreviewPhase.midGlyph;
    final isMidFocused =
        _displayPhase == _OcrRecoveryPreviewPhase.midFocused;
    final isMid = isMidContext || isMidGlyph || isMidFocused;
    final width = isMidGlyph ? 112.0 : (isMid ? 142.0 : 154.0);
    final height = isMidGlyph ? 78.0 : (isMid ? 76.0 : 84.0);
    final borderColor = isMid ? colorScheme.primary : colorScheme.secondary;
    final keyPrefix = isMid
        ? '${_displayPhase.name}-${widget.localSlot?.name ?? 'unknown'}'
        : _displayPhase.name;

    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomRight,
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final slide = Tween<Offset>(
            begin: const Offset(.06, .05),
            end: Offset.zero,
          ).animate(curved);
          final scale = Tween<double>(begin: .92, end: 1).animate(curved);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(
                scale: scale,
                alignment: Alignment.bottomRight,
                child: child,
              ),
            ),
          );
        },
        child: _displayBytes == null
            ? const SizedBox.shrink(key: ValueKey<String>('preview-empty'))
            : _OcrRecoveryPreviewCard(
                key: ValueKey<String>(
                  '$keyPrefix-${identityHashCode(_displayBytes)}',
                ),
                bytes: _displayBytes!,
                width: width,
                height: height,
                borderColor: borderColor,
                reduceMotion: widget.reduceMotion,
              ),
      ),
    );
  }
}

class _OcrRecoveryPreviewCard extends StatelessWidget {
  const _OcrRecoveryPreviewCard({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.borderColor,
    required this.reduceMotion,
  });

  final Uint8List bytes;
  final double width;
  final double height;
  final Color borderColor;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration:
      reduceMotion ? Duration.zero : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: .94 + (.06 * t),
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor.withOpacity(.82),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            height: height,
            width: double.infinity,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class _OcrOperationCaption extends StatelessWidget {
  const _OcrOperationCaption({
    super.key,
    required this.stage,
  });

  final _OcrDebugStage stage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.primary.withOpacity(.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OcrOperationPulse(stage: stage),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _caption(stage),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _caption(_OcrDebugStage stage) {
    switch (stage) {
      case _OcrDebugStage.idle:
        return '번호판 인식을 준비하고 있어요';
      case _OcrDebugStage.capturing:
        return '카메라 화면을 확인하고 있어요';
      case _OcrDebugStage.fullOcr:
        return '화면에서 번호와 글자를 읽고 있어요';
      case _OcrDebugStage.weakPlateDetected:
        return '번호판으로 보이는 영역을 찾았어요';
      case _OcrDebugStage.cropPrepared:
        return '번호판 부분을 확대하고 있어요';
      case _OcrDebugStage.cropOcr:
        return '확대한 번호판을 다시 읽고 있어요';
      case _OcrDebugStage.localCropPrepared:
        return '번호판의 세부 영역을 더 크게 살펴보고 있어요';
      case _OcrDebugStage.localCropOcr:
        return '확대한 세부 영역을 다시 읽고 있어요';
      case _OcrDebugStage.refocusing:
        return '더 선명하게 보기 위해 초점을 다시 맞추고 있어요';
      case _OcrDebugStage.recovered:
        return '번호판을 확인했어요';
      case _OcrDebugStage.fallback:
        return '다음 화면에서 다시 확인하고 있어요';
    }
  }
}

class _OcrOperationPulse extends StatelessWidget {
  const _OcrOperationPulse({required this.stage});

  final _OcrDebugStage stage;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    if (stage == _OcrDebugStage.recovered) {
      return Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: colorScheme.primary,
      );
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('pulse-${stage.name}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0).toDouble();
        return Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.primary.withOpacity(.45 + (.45 * t)),
              width: 1.2,
            ),
          ),
          child: Container(
            width: 5 + (3 * t),
            height: 5 + (3 * t),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class _OcrDebugOverlay extends StatelessWidget {
  const _OcrDebugOverlay({
    required this.revision,
    required this.stage,
    required this.lineBoxes,
    required this.sourceImageSize,
    required this.weakBox,
    required this.cropBox,
    required this.localCropBox,
    required this.midContextBox,
    required this.midLeftBox,
    required this.midGlyphBox,
    required this.midRightBox,
    required this.localSlot,
    required this.focusPoint,
    required this.cropText,
    required this.localCropText,
    required this.structuredPlate,
    required this.recoveredPlate,
    required this.detail,
    required this.captureMs,
    required this.fullOcrMs,
    required this.cropOcrMs,
    required this.localOcrMs,
  });

  final int revision;
  final _OcrDebugStage stage;
  final List<_OcrDebugLineBox> lineBoxes;
  final Size? sourceImageSize;
  final Rect? weakBox;
  final Rect? cropBox;
  final Rect? localCropBox;
  final Rect? midContextBox;
  final Rect? midLeftBox;
  final Rect? midGlyphBox;
  final Rect? midRightBox;
  final _PlateRecoverySlot? localSlot;
  final Offset? focusPoint;
  final String? cropText;
  final String? localCropText;
  final String? structuredPlate;
  final String? recoveredPlate;
  final String? detail;
  final int? captureMs;
  final int? fullOcrMs;
  final int? cropOcrMs;
  final int? localOcrMs;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final source = sourceImageSize;
          final mappedLines = source == null
              ? const <_OcrDebugLineBox>[]
              : lineBoxes
              .map(
                (item) => _OcrDebugLineBox(
              box: _mapDebugRect(
                item.box,
                source,
                viewport,
              ),
              text: item.text,
            ),
          )
              .toList(growable: false);
          final mappedWeak = source == null || weakBox == null
              ? null
              : _mapDebugRect(weakBox!, source, viewport);
          final mappedCrop = source == null || cropBox == null
              ? null
              : _mapDebugRect(cropBox!, source, viewport);
          final mappedLocal = source == null || localCropBox == null
              ? null
              : _mapDebugRect(localCropBox!, source, viewport);
          final mappedMidContext = source == null || midContextBox == null
              ? null
              : _mapDebugRect(midContextBox!, source, viewport);
          final mappedMidLeft = source == null || midLeftBox == null
              ? null
              : _mapDebugRect(midLeftBox!, source, viewport);
          final mappedMidGlyph = source == null || midGlyphBox == null
              ? null
              : _mapDebugRect(midGlyphBox!, source, viewport);
          final mappedMidRight = source == null || midRightBox == null
              ? null
              : _mapDebugRect(midRightBox!, source, viewport);
          final focus = focusPoint == null
              ? null
              : Offset(
            focusPoint!.dx * viewport.width,
            focusPoint!.dy * viewport.height,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey<String>('lines-$revision-${mappedLines.length}'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return CustomPaint(
                    painter: _OcrDebugLinesPainter(
                      boxes: mappedLines,
                      opacity: value,
                      color: colorScheme.primary,
                    ),
                  );
                },
              ),
              if (mappedWeak != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('weak-$revision-${mappedWeak.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: mappedWeak,
                        opacity: value,
                        color: colorScheme.tertiary,
                        dashed: true,
                        label: structuredPlate ?? 'WEAK',
                      ),
                    );
                  },
                ),
              if (mappedCrop != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('crop-$revision-${mappedCrop.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    final t = value.clamp(0.0, 1.0).toDouble();
                    final start = mappedWeak ?? mappedCrop;
                    final animatedRect = Rect.lerp(
                      start,
                      mappedCrop,
                      t,
                    )!;
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: animatedRect,
                        opacity: .35 + (.65 * t),
                        color: colorScheme.secondary,
                        dashed: false,
                        label: 'DYNAMIC CROP',
                      ),
                    );
                  },
                ),
              if (mappedLocal != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('local-$revision-${mappedLocal.hashCode}-${localSlot?.name ?? 'unknown'}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    final t = value.clamp(0.0, 1.0).toDouble();
                    final start = mappedCrop ?? mappedWeak ?? mappedLocal;
                    final animatedRect = Rect.lerp(
                      start,
                      mappedLocal,
                      t,
                    )!;
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: animatedRect,
                        opacity: .45 + (.55 * t),
                        color: colorScheme.error,
                        dashed: true,
                        label: '${(localSlot ?? _PlateRecoverySlot.mid).name.toUpperCase()} LOCAL',
                      ),
                    );
                  },
                ),
              if (mappedMidContext != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('mid-context-$revision-${mappedMidContext.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: mappedMidContext,
                        opacity: .28 + (.52 * value),
                        color: colorScheme.primary,
                        dashed: true,
                        label: 'MID CONTEXT',
                      ),
                    );
                  },
                ),
              if (mappedMidLeft != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('mid-left-$revision-${mappedMidLeft.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: mappedMidLeft,
                        opacity: .35 + (.65 * value),
                        color: colorScheme.tertiary,
                        dashed: false,
                        label: 'L',
                      ),
                    );
                  },
                ),
              if (mappedMidGlyph != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('mid-glyph-$revision-${mappedMidGlyph.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: duration,
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: mappedMidGlyph,
                        opacity: .40 + (.60 * value),
                        color: colorScheme.error,
                        dashed: false,
                        label: 'M',
                      ),
                    );
                  },
                ),
              if (mappedMidRight != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('mid-right-$revision-${mappedMidRight.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: mappedMidRight,
                        opacity: .35 + (.65 * value),
                        color: colorScheme.tertiary,
                        dashed: false,
                        label: 'R',
                      ),
                    );
                  },
                ),
              if (focus != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('focus-$revision-${focus.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 520),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _OcrDebugFocusPainter(
                        point: focus,
                        progress: value,
                        color: colorScheme.error,
                      ),
                    );
                  },
                ),
              Positioned(
                left: 10,
                top: 10,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: .97, end: 1).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: _OcrDebugStagePanel(
                    key: ValueKey<String>(
                      '${stage.name}-$revision-${structuredPlate ?? '-'}-${recoveredPlate ?? '-'}',
                    ),
                    stage: stage,
                    structuredPlate: structuredPlate,
                    recoveredPlate: recoveredPlate,
                    cropText: localCropText ?? cropText,
                    detail: detail,
                    captureMs: captureMs,
                    fullOcrMs: fullOcrMs,
                    cropOcrMs: (cropOcrMs ?? 0) + (localOcrMs ?? 0),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Rect _mapDebugRect(
      Rect sourceRect,
      Size sourceSize,
      Size viewport,
      ) {
    if (sourceSize.width <= 0 ||
        sourceSize.height <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return Rect.zero;
    }
    final scale = math.max(
      viewport.width / sourceSize.width,
      viewport.height / sourceSize.height,
    );
    final renderedWidth = sourceSize.width * scale;
    final renderedHeight = sourceSize.height * scale;
    final offsetX = (viewport.width - renderedWidth) / 2;
    final offsetY = (viewport.height - renderedHeight) / 2;
    return Rect.fromLTRB(
      offsetX + (sourceRect.left * scale),
      offsetY + (sourceRect.top * scale),
      offsetX + (sourceRect.right * scale),
      offsetY + (sourceRect.bottom * scale),
    );
  }
}

class _OcrDebugStagePanel extends StatelessWidget {
  const _OcrDebugStagePanel({
    super.key,
    required this.stage,
    required this.structuredPlate,
    required this.recoveredPlate,
    required this.cropText,
    required this.detail,
    required this.captureMs,
    required this.fullOcrMs,
    required this.cropOcrMs,
  });

  final _OcrDebugStage stage;
  final String? structuredPlate;
  final String? recoveredPlate;
  final String? cropText;
  final String? detail;
  final int? captureMs;
  final int? fullOcrMs;
  final int? cropOcrMs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = <String>[
      _stageLabel(stage),
      if (structuredPlate != null) 'STRUCTURED $structuredPlate',
      if (cropText != null && cropText!.isNotEmpty) 'CROP OCR $cropText',
      if (recoveredPlate != null) 'RESULT $recoveredPlate',
      if (detail != null && detail!.isNotEmpty) detail!,
      'CAP ${captureMs ?? '-'}ms · OCR ${fullOcrMs ?? '-'}ms · ROI ${cropOcrMs ?? '-'}ms',
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 286),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _stageColor(stage, colorScheme).withOpacity(.9),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map(
                (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          )
              .toList(growable: false),
        ),
      ),
    );
  }

  static String _stageLabel(_OcrDebugStage stage) {
    switch (stage) {
      case _OcrDebugStage.idle:
        return 'IDLE';
      case _OcrDebugStage.capturing:
        return 'CAPTURE';
      case _OcrDebugStage.fullOcr:
        return 'FULL OCR';
      case _OcrDebugStage.weakPlateDetected:
        return 'WEAK PLATE';
      case _OcrDebugStage.cropPrepared:
        return 'DYNAMIC CROP';
      case _OcrDebugStage.cropOcr:
        return 'CROP OCR';
      case _OcrDebugStage.localCropPrepared:
        return 'LOCAL CROP';
      case _OcrDebugStage.localCropOcr:
        return 'LOCAL OCR';
      case _OcrDebugStage.refocusing:
        return 'AF / AE';
      case _OcrDebugStage.recovered:
        return 'RECOVERED';
      case _OcrDebugStage.fallback:
        return 'FALLBACK';
    }
  }

  static Color _stageColor(
      _OcrDebugStage stage,
      ColorScheme colorScheme,
      ) {
    switch (stage) {
      case _OcrDebugStage.recovered:
        return colorScheme.primary;
      case _OcrDebugStage.fallback:
        return colorScheme.error;
      case _OcrDebugStage.refocusing:
        return colorScheme.tertiary;
      default:
        return colorScheme.secondary;
    }
  }
}

class _OcrDebugLinesPainter extends CustomPainter {
  const _OcrDebugLinesPainter({
    required this.boxes,
    required this.opacity,
    required this.color,
  });

  final List<_OcrDebugLineBox> boxes;
  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withOpacity(.7 * opacity);

    for (final item in boxes) {
      if (item.box.isEmpty) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(item.box, const Radius.circular(5)),
        paint,
      );
      final normalized = item.text.replaceAll('\n', ' ').trim();
      if (normalized.isEmpty || item.box.width < 42) continue;
      final visible = normalized.length > 18
          ? '${normalized.substring(0, 18)}…'
          : normalized;
      final textPainter = TextPainter(
        text: TextSpan(
          text: visible,
          style: TextStyle(
            color: color.withOpacity(.95 * opacity),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            backgroundColor: Colors.black.withOpacity(.5 * opacity),
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(40, item.box.width).toDouble());
      final dy = math.max(0.0, item.box.top - textPainter.height - 2);
      textPainter.paint(canvas, Offset(item.box.left, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _OcrDebugLinesPainter oldDelegate) {
    return oldDelegate.boxes != boxes ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
  }
}

class _OcrDebugRegionPainter extends CustomPainter {
  const _OcrDebugRegionPainter({
    required this.rect,
    required this.opacity,
    required this.color,
    required this.dashed,
    required this.label,
  });

  final Rect rect;
  final double opacity;
  final Color color;
  final bool dashed;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = color.withOpacity(opacity.clamp(0.0, 1.0).toDouble());
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    if (dashed) {
      _drawDashedRRect(canvas, rounded, paint);
    } else {
      canvas.drawRRect(rounded, paint);
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withOpacity(opacity.clamp(0.0, 1.0).toDouble()),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          backgroundColor: Colors.black.withOpacity(.62),
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(60, rect.width).toDouble());
    final dy = math.max(0.0, rect.top - textPainter.height - 3);
    textPainter.paint(canvas, Offset(rect.left, dy));
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dash = 8.0;
      const gap = 5.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OcrDebugRegionPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color ||
        oldDelegate.dashed != dashed ||
        oldDelegate.label != label;
  }
}

class _OcrDebugFocusPainter extends CustomPainter {
  const _OcrDebugFocusPainter({
    required this.point,
    required this.progress,
    required this.color,
  });

  final Offset point;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    final radius = 20 - (8 * t);
    final opacity = (.35 + (.65 * t)).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = color.withOpacity(opacity.toDouble());
    canvas.drawCircle(point, radius, paint);
    canvas.drawLine(
      Offset(point.dx - 7, point.dy),
      Offset(point.dx + 7, point.dy),
      paint,
    );
    canvas.drawLine(
      Offset(point.dx, point.dy - 7),
      Offset(point.dx, point.dy + 7),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _OcrDebugFocusPainter oldDelegate) {
    return oldDelegate.point != point ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color;
  }
}
