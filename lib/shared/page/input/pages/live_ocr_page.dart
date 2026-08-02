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

import '../domain/repositories/ocr_learning_repository.dart';

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
  candidateChipSelected,
  userAborted,
  permissionDenied,
  cameraInitFailed,
}

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
  inferred,
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


enum _OcrDebugStage {
  idle,
  capturing,
  fullOcr,
  weakPlateDetected,
  cropPrepared,
  cropOcr,
  microCropPrepared,
  microCropOcr,
  refocusing,
  recovered,
  fallback,
}

class _OcrDebugLineBox {
  final Rect box;
  final String text;

  const _OcrDebugLineBox({
    required this.box,
    required this.text,
  });
}

class _WeakPlateRegion {
  final Rect box;
  final String front;
  final String back;
  final String signature;
  final String sourceText;
  final String sourceKind;
  final double score;

  const _WeakPlateRegion({
    required this.box,
    required this.front,
    required this.back,
    required this.signature,
    required this.sourceText,
    required this.sourceKind,
    required this.score,
  });
}

class _MicroMidEvidence {
  final String mid;
  final double score;
  final bool leftContextMatched;
  final bool rightContextMatched;
  final String text;

  const _MicroMidEvidence({
    required this.mid,
    required this.score,
    required this.leftContextMatched,
    required this.rightContextMatched,
    required this.text,
  });

  bool get strongContext => leftContextMatched && rightContextMatched;
}

class _MicroCropRecovery {
  final String plate;
  final String text;
  final Rect rect;
  final Uint8List bytes;
  final int ocrMs;
  final String signature;

  const _MicroCropRecovery({
    required this.plate,
    required this.text,
    required this.rect,
    required this.bytes,
    required this.ocrMs,
    required this.signature,
  });
}

class _DecodedCapture {
  final img.Image image;
  final Size imageSize;

  const _DecodedCapture({
    required this.image,
    required this.imageSize,
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
  });
}

class LiveOcrPage extends StatefulWidget {
  final String sessionId;

  const LiveOcrPage({
    super.key,
    required this.sessionId,
  });

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
  Rect? _ocrDebugMicroCropBox;
  Offset? _ocrDebugFocusPoint;
  Uint8List? _ocrDebugCropBytes;
  Uint8List? _ocrDebugMicroCropBytes;
  String? _ocrDebugCropText;
  String? _ocrDebugMicroCropText;
  String? _ocrDebugStructuredPlate;
  String? _ocrDebugRecoveredPlate;
  String? _ocrDebugStageDetail;
  int? _ocrDebugCaptureMs;
  int? _ocrDebugFullOcrMs;
  int? _ocrDebugCropOcrMs;
  int? _ocrDebugMicroOcrMs;
  int _ocrDebugRevision = 0;
  String? _pendingRefocusSignature;
  int _pendingRefocusRetryCount = 0;
  DateTime? _lastAutoRefocusAt;
  String? _lastAutoRefocusIdentity;
  Rect? _lastAutoRefocusRegion;
  Size? _lastAutoRefocusImageSize;
  String? _lastRefocusDecision;

  int _autoIntervalMs = 900;
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
  final Map<String, int> _weakStructuredVotes = {};
  final Map<String, Map<String, int>> _weakStructuredObservedHangulVotes = {};
  final Map<String, _StructuredWeakCandidate> _weakStructuredBest = {};
  final List<Map<String, Map<String, double>>> _segmentationEvidenceFrames = [];
  static const int _voteWindow = 4;
  static const int _stableVoteThreshold = 2;
  static const int _tentativeVoteThreshold = 2;
  static const int _weakStructuredVoteThreshold = 2;
  static const int _refocusRetryLimit = 1;
  static const int _refocusRetryIntervalMs = 260;
  static const int _refocusCooldownMs = 10000;
  static const double _refocusMajorCenterShift = .18;
  static const double _refocusMajorScaleRatio = 1.55;

  static const double _chipBottomSpacer = 24;
  static const Duration _developerRecoveredHold = Duration(milliseconds: 720);
  Size? _previewSizeLogical;

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _developerMode = await DevAuth.isDeveloperLoggedIn();
    _appendLog('개발자 모드 ${_developerMode ? 'ON' : 'OFF'}');
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
      _weakStructuredVotes.clear();
      _weakStructuredObservedHangulVotes.clear();
      _weakStructuredBest.clear();
      _segmentationEvidenceFrames.clear();
      _sessionLogs.clear();
      _lastSavedLearningKey = null;
      _ocrDebugStage = _OcrDebugStage.idle;
      _ocrDebugLineBoxes = const [];
      _ocrDebugSourceImageSize = null;
      _ocrDebugWeakBox = null;
      _ocrDebugCropBox = null;
      _ocrDebugMicroCropBox = null;
      _ocrDebugFocusPoint = null;
      _ocrDebugCropBytes = null;
      _ocrDebugMicroCropBytes = null;
      _ocrDebugCropText = null;
      _ocrDebugMicroCropText = null;
      _ocrDebugStructuredPlate = null;
      _ocrDebugRecoveredPlate = null;
      _ocrDebugStageDetail = null;
      _ocrDebugCaptureMs = null;
      _ocrDebugFullOcrMs = null;
      _ocrDebugCropOcrMs = null;
      _ocrDebugMicroOcrMs = null;
      _ocrDebugRevision = 0;
      _pendingRefocusSignature = null;
      _pendingRefocusRetryCount = 0;
      _lastAutoRefocusAt = null;
      _lastAutoRefocusIdentity = null;
      _lastAutoRefocusRegion = null;
      _lastAutoRefocusImageSize = null;
      _lastRefocusDecision = null;
    }

    _autoGen++;
    final gen = _autoGen;
    _appendLog(
      '인식 시작 gen=$gen intervalMs=$_autoIntervalMs '
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
      String? suppressedWeakSignature;
      _DecodedCapture? decodedCapture;

      try {
        _setOcrDebugStage(
          _OcrDebugStage.capturing,
          detail: 'capture',
          clearFrameGeometry: true,
        );

        final captureWatch = Stopwatch()..start();
        final captured = await cam.takePicture();
        captureWatch.stop();
        capturedPath = captured.path;
        _captureErrorStreak = 0;
        _ocrDebugCaptureMs = captureWatch.elapsedMilliseconds;

        final input = InputImage.fromFilePath(captured.path);
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

        if (_developerMode) {
          decodedCapture = await _decodeCaptureForGeometry(
            captured.path,
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
          _appendLog('직접 확정 $direct');
          _setOcrDebugStage(
            _OcrDebugStage.recovered,
            detail: 'strict:$direct',
            recoveredPlate: direct,
          );
          await _holdDeveloperVisualization();
          await _finishAndPop(
            plate: direct,
            exitType: LiveOcrExitType.autoDirect,
          );
          return;
        }

        final loose = _extractLooseKoreanPlate(allText, onUseLearningMid: () {
          usedLearningMidThis = true;
        });
        if (loose != null) {
          _usedLearningMidLast = usedLearningMidThis;
          _usedLearningRankLast = false;
          _appendLog('완화 확정 $loose');
          _setOcrDebugStage(
            _OcrDebugStage.recovered,
            detail: 'loose:$loose',
            recoveredPlate: loose,
          );
          await _holdDeveloperVisualization();
          await _finishAndPop(
            plate: loose,
            exitType: LiveOcrExitType.autoLoose,
          );
          return;
        }

        final structuredWeakFrame = _extractStructuredWeakCandidates(result);
        _observeSegmentationEvidence(structuredWeakFrame);
        final midRecoveryCandidates = _rankStructuredWeakCandidates(
          structuredWeakFrame,
        );

        if (midRecoveryCandidates.isEmpty &&
            _pendingRefocusSignature != null) {
          _appendLog(
            '재초점 대기 해제 signature=$_pendingRefocusSignature reason=unresolvedCandidateGone',
          );
          _pendingRefocusSignature = null;
          _pendingRefocusRetryCount = 0;
        }

        if (midRecoveryCandidates.isNotEmpty) {
          final outcome = await _tryRecoverUnresolvedMidFromDynamicCrop(
            capturedPath: captured.path,
            result: result,
            weakCandidates: midRecoveryCandidates,
            decodedCapture: decodedCapture,
            onUseLearningMid: () {
              usedLearningMidThis = true;
            },
          );

          if (outcome != null) {
            if (outcome.plate != null &&
                _isModernPlate(_normalizeCandidateKey(outcome.plate!))) {
              final recoveredPlate = _normalizeCandidateKey(outcome.plate!);
              _pendingRefocusSignature = null;
              _pendingRefocusRetryCount = 0;
              _usedLearningMidLast = usedLearningMidThis;
              _usedLearningRankLast = false;
              _appendLog(
                '동적 crop 복구 성공 plate=$recoveredPlate '
                'cropOcrMs=${outcome.cropOcrMs} cropText=${outcome.cropText.replaceAll('\n', ' ')}',
              );
              _setOcrDebugStage(
                _OcrDebugStage.recovered,
                detail: 'cropRecovered:$recoveredPlate',
                recoveredPlate: recoveredPlate,
              );
              await _holdDeveloperVisualization();
              await _finishAndPop(
                plate: recoveredPlate,
                exitType: LiveOcrExitType.autoLoose,
              );
              return;
            }

            final samePendingSignature =
                _pendingRefocusSignature == outcome.signature;
            final retryConsumed = samePendingSignature &&
                _pendingRefocusRetryCount >= _refocusRetryLimit;

            if (!retryConsumed) {
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

        var displayChips = _buildDisplayChips(
          stableFrame,
          tentativeFrame,
          weakFrame,
          structuredWeakFrame,
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
            _appendLog('강제 삽입 $force');
            _usedLearningMidLast = usedLearningMidThis;
            _usedLearningRankLast = usedLearningRankThis;
            await _finishAndPop(
              plate: force,
              exitType: LiveOcrExitType.autoForceInsert,
            );
            return;
          }
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

      await Future.delayed(
        Duration(
          milliseconds: fastRefocusRetryRequested
              ? _refocusRetryIntervalMs
              : _autoIntervalMs.clamp(200, 3000).toInt(),
        ),
      );
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
      _ocrDebugMicroCropBox = null;
      _ocrDebugFocusPoint = null;
      _ocrDebugCropBytes = null;
      _ocrDebugMicroCropBytes = null;
      _ocrDebugCropText = null;
      _ocrDebugMicroCropText = null;
      _ocrDebugStructuredPlate = null;
      _ocrDebugRecoveredPlate = null;
      _ocrDebugCropOcrMs = null;
      _ocrDebugMicroOcrMs = null;
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
    _ocrDebugMicroCropBox = null;
    _ocrDebugFocusPoint = null;
    _ocrDebugCropBytes = null;
    _ocrDebugMicroCropBytes = null;
    _ocrDebugCropText = null;
    _ocrDebugMicroCropText = null;
    _ocrDebugCropOcrMs = null;
    _ocrDebugMicroOcrMs = null;
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
      final selected = bakedFits || !decodedFits ? baked : decoded;
      final size = Size(
        selected.width.toDouble(),
        selected.height.toDouble(),
      );
      _appendLog(
        'geometry image size=${selected.width}x${selected.height} '
        'decodedFits=$decodedFits bakedFits=$bakedFits',
      );
      return _DecodedCapture(image: selected, imageSize: size);
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
    }) {
      if (box.width <= 0 || box.height <= 0) return;
      final score = candidate.score + bonus - (box.width * box.height * 0.000002);
      if (best == null || score > best!.score) {
        best = _WeakPlateRegion(
          box: box,
          front: candidate.front,
          back: candidate.back,
          signature: candidate.signature,
          sourceText: text,
          sourceKind: sourceKind,
          score: score,
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
              );
            } else {
              consider(
                box: line.boundingBox,
                text: line.text,
                sourceKind: 'lineFallback',
                candidate: candidate,
                bonus: 1.0,
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
          final dy = (frontBox.center.dy - backBox.center.dy).abs();
          final horizontalGap = backBox.left - frontBox.right;
          if (dy > math.max(averageHeight * 1.15, 18.0)) continue;
          if (horizontalGap < -math.max(frontBox.width, backBox.width) * .28) {
            continue;
          }
          if (horizontalGap > math.max(averageHeight * 4.5, 120.0)) continue;
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

  Future<_CropRecoveryOutcome?> _tryRecoverUnresolvedMidFromDynamicCrop({
    required String capturedPath,
    required RecognizedText result,
    required List<_StructuredWeakCandidate> weakCandidates,
    required _DecodedCapture? decodedCapture,
    required VoidCallback onUseLearningMid,
  }) async {
    String? tempCropPath;
    try {
      _ocrDebugMicroCropBox = null;
      _ocrDebugMicroCropBytes = null;
      _ocrDebugMicroCropText = null;
      _ocrDebugMicroOcrMs = null;
      final decoded = decodedCapture ??
          await _decodeCaptureForGeometry(capturedPath, result);
      if (decoded == null) {
        _appendLog('동적 crop 복구 생략 image decode 실패');
        return null;
      }

      final region = _findWeakPlateRegion(result, weakCandidates);
      if (region == null) {
        _appendLog(
          '동적 crop 복구 생략 weak region 미검출 '
          'candidates=${_joinForLog(weakCandidates.map((e) => e.signature).toList())}',
        );
        _setOcrDebugStage(
          _OcrDebugStage.fallback,
          detail: 'weakRegionNotFound',
          structuredPlate: weakCandidates.first.signature,
        );
        return null;
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

      var crop = img.copyCrop(
        decoded.image,
        x: x,
        y: y,
        width: width,
        height: height,
      );
      crop.exif.imageIfd.orientation = null;

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

      final cropBytes = Uint8List.fromList(
        img.encodeJpg(crop, quality: 96),
      );
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
      if (plate == null) {
        microRecovery = await _tryRecoverFromMidContextMicroCrops(
          capturedPath: capturedPath,
          decoded: decoded,
          sourceResult: result,
          region: region,
          weakCandidates: weakCandidates,
          onUseLearningMid: onUseLearningMid,
        );
        plate = microRecovery?.plate;
      }
      final focusPoint = _normalizedFocusPoint(region.box, decoded.imageSize);
      final combinedText = microRecovery == null
          ? cropText
          : '$cropText | MICRO ${microRecovery.text}';
      final combinedOcrMs =
          cropOcrMs + (microRecovery?.ocrMs ?? _ocrDebugMicroOcrMs ?? 0);

      _appendLog(
        'crop OCR signature=${region.signature} '
        'sourceBox=${_rectForLog(region.box)} cropBox=${_rectForLog(cropRect)} '
        'cropSize=${crop.width}x${crop.height} cropOcrMs=$cropOcrMs '
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
        cropRegion: microRecovery?.rect ?? cropRect,
        sourceImageSize: decoded.imageSize,
        cropBytes: microRecovery?.bytes ?? cropBytes,
        focusPoint: focusPoint,
        cropOcrMs: combinedOcrMs,
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
      _appendLog('동적 crop 복구 오류 $e');
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

  Rect _buildSlotMidContextRect({
    required Rect plateBox,
    required _StructuredWeakCandidate candidate,
    required Size imageSize,
  }) {
    final totalSlots = candidate.frontLen + 1 + 4;
    final safeSlots = math.max(7, totalSlots);
    final charWidth = plateBox.width / safeSlots;
    final midCenterRatio = (candidate.frontLen + .5) / totalSlots;
    final centerX = plateBox.left + (plateBox.width * midCenterRatio);
    final halfWidth = math.max(charWidth * 1.65, plateBox.height * .65);
    final padY = math.max(plateBox.height * .22, 8.0);
    final left = (centerX - halfWidth).clamp(0.0, imageSize.width).toDouble();
    final right = (centerX + halfWidth).clamp(0.0, imageSize.width).toDouble();
    final top = (plateBox.top - padY).clamp(0.0, imageSize.height).toDouble();
    final bottom = (plateBox.bottom + padY).clamp(0.0, imageSize.height).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
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

  ({Rect box, String kind})? _findAdaptiveMidAnchors({
    required RecognizedText result,
    required _WeakPlateRegion region,
    required _StructuredWeakCandidate candidate,
  }) {
    final options = <({Rect box, String kind, double score})>[];
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
      final halfWidth = math.max(unit * 1.85, meanHeight * .72);
      final verticalUnion = Rect.fromLTRB(
        math.min(frontBox.left, backBox.left),
        math.min(frontBox.top, backBox.top),
        math.max(frontBox.right, backBox.right),
        math.max(frontBox.bottom, backBox.bottom),
      );
      final padY = math.max(verticalUnion.height * .32, 8.0);
      final box = Rect.fromLTRB(
        midCenterX - halfWidth,
        verticalUnion.top - padY,
        midCenterX + halfWidth,
        verticalUnion.bottom + padY,
      );
      final regionDistance = (box.center - region.box.center).distance;
      final score = bonus -
          verticalDelta * .02 -
          regionDistance * .001 -
          gap.abs() * .002;
      options.add((box: box, kind: kind, score: score));
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
    return (box: options.first.box, kind: options.first.kind);
  }

  ({Rect rect, String sourceKind}) _buildMidContextRect({
    required RecognizedText result,
    required Rect plateBox,
    required _WeakPlateRegion region,
    required _StructuredWeakCandidate candidate,
    required Size imageSize,
  }) {
    final adaptive = _findAdaptiveMidAnchors(
      result: result,
      region: region,
      candidate: candidate,
    );
    final raw = adaptive?.box ??
        _buildSlotMidContextRect(
          plateBox: plateBox,
          candidate: candidate,
          imageSize: imageSize,
        );
    final left = raw.left.clamp(0.0, imageSize.width).toDouble();
    final right = raw.right.clamp(0.0, imageSize.width).toDouble();
    final top = raw.top.clamp(0.0, imageSize.height).toDouble();
    final bottom = raw.bottom.clamp(0.0, imageSize.height).toDouble();
    final rect = Rect.fromLTRB(left, top, right, bottom);
    if (adaptive != null && rect.width >= 4 && rect.height >= 4) {
      return (rect: rect, sourceKind: adaptive.kind);
    }
    return (
      rect: _buildSlotMidContextRect(
        plateBox: plateBox,
        candidate: candidate,
        imageSize: imageSize,
      ),
      sourceKind: 'slotFallback',
    );
  }

  _MicroMidEvidence? _selectMidFromMicroCropResult(
    RecognizedText result,
    Size imageSize, {
    required _StructuredWeakCandidate expected,
    required VoidCallback onUseLearningMid,
  }) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return null;
    final leftDigit = expected.front.substring(expected.front.length - 1);
    final rightDigit = expected.back.substring(0, 1);
    final candidates = <_MicroMidEvidence>[];
    final allCompact = result.text.replaceAll(RegExp(r'[^0-9가-힣]'), '');

    for (final block in result.blocks) {
      for (final line in block.lines) {
        final compact = line.text.replaceAll(RegExp(r'[^0-9가-힣]'), '');
        for (final element in line.elements) {
          final box = element.boundingBox;
          if (box.width <= 0 || box.height <= 0) continue;
          final nx = box.center.dx / imageSize.width;
          final ny = box.center.dy / imageSize.height;
          final nh = box.height / imageSize.height;
          if (nx < .18 || nx > .82 || ny < .12 || ny > .88 || nh < .12) {
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
            final exactContext = compact.contains('$leftDigit$char$rightDigit') ||
                compact.contains('$leftDigit$normalized$rightDigit') ||
                allCompact.contains('$leftDigit$char$rightDigit') ||
                allCompact.contains('$leftDigit$normalized$rightDigit');
            final evidenceText = compact.contains(char) || compact.contains(normalized)
                ? compact
                : allCompact;
            final charIndex = evidenceText.indexOf(char);
            final normalizedIndex = evidenceText.indexOf(normalized);
            final index = charIndex >= 0 ? charIndex : normalizedIndex;
            final leftMatched = exactContext ||
                (index > 0 &&
                    evidenceText.substring(0, index).contains(leftDigit));
            final rightMatched = exactContext ||
                (index >= 0 &&
                    index + 1 < evidenceText.length &&
                    evidenceText.substring(index + 1).contains(rightDigit));
            final hints =
                _genericWeakMidHints[expected.observedToken] ?? const <String>[];
            final hintRank = hints.indexOf(normalized);
            final centerPenalty = (nx - .5).abs() + ((ny - .5).abs() * .5);
            final sizePenalty = (nh - .42).abs() * .12;
            final contextBonus = exactContext
                ? .62
                : (leftMatched && rightMatched)
                    ? .40
                    : (leftMatched || rightMatched)
                        ? .16
                        : 0.0;
            final hintBonus = hintRank < 0
                ? 0.0
                : math.max(.03, .12 - (hintRank * .02));
            candidates.add(
              _MicroMidEvidence(
                mid: normalized,
                score: centerPenalty + sizePenalty - contextBonus - hintBonus,
                leftContextMatched: leftMatched,
                rightContextMatched: rightMatched,
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
  }) async {
    final resolvedFront = _resolveFrontFromEvidence(
      region.back,
      weakCandidates,
    );
    final ranked = List<_StructuredWeakCandidate>.from(weakCandidates)
      ..sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    var tried = 0;

    for (final candidate in ranked) {
      if (candidate.back != region.back) continue;
      if (resolvedFront != null && candidate.front != resolvedFront) continue;
      final key = '${candidate.front}|${candidate.back}|${candidate.frontLen}';
      if (!seen.add(key)) continue;
      if (tried >= 3) break;
      tried++;

      final microContext = _buildMidContextRect(
        result: sourceResult,
        plateBox: region.box,
        region: region,
        candidate: candidate,
        imageSize: decoded.imageSize,
      );
      final microRect = microContext.rect;
      if (microRect.width < 4 || microRect.height < 4) continue;

      _ocrDebugMicroCropBox = microRect;
      _setOcrDebugStage(
        _OcrDebugStage.microCropPrepared,
        detail:
            '${candidate.signature} evidence=${candidate.segmentationEvidence.name} anchor=${microContext.sourceKind} rect=${_rectForLog(microRect)}',
        structuredPlate: candidate.signature,
      );
      await _developerDebugBeat(const Duration(milliseconds: 110));

      final x = microRect.left.floor().clamp(0, decoded.image.width - 1).toInt();
      final y = microRect.top.floor().clamp(0, decoded.image.height - 1).toInt();
      final right =
          microRect.right.ceil().clamp(x + 1, decoded.image.width).toInt();
      final bottom =
          microRect.bottom.ceil().clamp(y + 1, decoded.image.height).toInt();
      var micro = img.copyCrop(
        decoded.image,
        x: x,
        y: y,
        width: right - x,
        height: bottom - y,
      );
      micro.exif.imageIfd.orientation = null;
      final scale = (420.0 / math.max(1, micro.height)).clamp(1.0, 6.0).toDouble();
      if (scale > 1.02) {
        micro = img.copyResize(
          micro,
          width: math.max(1, (micro.width * scale).round()).toInt(),
          height: math.max(1, (micro.height * scale).round()).toInt(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final bytes = Uint8List.fromList(img.encodeJpg(micro, quality: 98));
      final microPath =
          '$capturedPath.live_ocr_micro_${candidate.frontLen}_${candidate.front}_${candidate.back}.jpg';
      final file = File(microPath);
      try {
        await file.writeAsBytes(bytes, flush: true);
        _ocrDebugMicroCropBytes = bytes;
        _ocrDebugMicroCropText = null;
        _ocrDebugMicroOcrMs = null;
        _setOcrDebugStage(
          _OcrDebugStage.microCropOcr,
          detail:
              '${candidate.signature} evidence=${candidate.segmentationEvidence.name} crop=${micro.width}x${micro.height}',
          structuredPlate: candidate.signature,
        );

        final watch = Stopwatch()..start();
        final microResult = await _recognizer.processImage(
          InputImage.fromFilePath(microPath),
        );
        watch.stop();
        final text = microResult.text;
        final ocrMs = watch.elapsedMilliseconds;
        _ocrDebugMicroCropText = text.replaceAll('\n', ' ');
        _ocrDebugMicroOcrMs = ocrMs;

        final evidence = _selectMidFromMicroCropResult(
          microResult,
          Size(micro.width.toDouble(), micro.height.toDouble()),
          expected: candidate,
          onUseLearningMid: onUseLearningMid,
        );
        final ambiguousFronts = _ambiguousFrontSegmentations(
          candidate,
          weakCandidates,
        );
        final frontResolved = resolvedFront == candidate.front;
        final strongSegmentation = evidence?.strongContext == true ||
            frontResolved ||
            (candidate.segmentationEvidence != _WeakSegmentationEvidence.inferred &&
                ambiguousFronts.length <= 1);

        _appendLog(
          'micro OCR signature=${candidate.signature} '
          'evidence=${candidate.segmentationEvidence.name} '
          'anchor=${microContext.sourceKind} '
          'rect=${_rectForLog(microRect)} crop=${micro.width}x${micro.height} '
          'ocrMs=$ocrMs text=${text.replaceAll('\n', ' ')} '
          'mid=${evidence?.mid ?? '-'} '
          'leftMatch=${evidence?.leftContextMatched ?? false} '
          'rightMatch=${evidence?.rightContextMatched ?? false} '
          'frontResolved=$frontResolved '
          'ambiguous=${ambiguousFronts.join('|')}',
        );

        if (evidence != null && strongSegmentation) {
          final plate = '${candidate.front}${evidence.mid}${candidate.back}';
          if (_isModernPlate(plate)) {
            _appendLog(
              'micro crop 복구 성공 plate=$plate '
              'signature=${candidate.signature} '
              'strongContext=${evidence.strongContext} '
              'evidence=${candidate.segmentationEvidence.name}',
            );
            return _MicroCropRecovery(
              plate: plate,
              text: text,
              rect: microRect,
              bytes: bytes,
              ocrMs: ocrMs,
              signature: candidate.signature,
            );
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
      'resolvedFront=${resolvedFront ?? '-'}',
    );
    return null;
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
      case _WeakSegmentationEvidence.inferred:
        return 0.0;
    }
  }

  void _observeSegmentationEvidence(
    List<_StructuredWeakCandidate> candidates,
  ) {
    final frame = <String, Map<String, double>>{};
    for (final candidate in candidates) {
      final weight = _segmentationEvidenceWeight(
        candidate.segmentationEvidence,
      );
      if (weight <= 0) continue;
      final fronts = frame.putIfAbsent(
        candidate.back,
        () => <String, double>{},
      );
      final previous = fronts[candidate.front] ?? 0.0;
      if (weight > previous) {
        fronts[candidate.front] = weight;
      }
    }
    _segmentationEvidenceFrames.add(frame);
    if (_segmentationEvidenceFrames.length > _voteWindow) {
      _segmentationEvidenceFrames.removeAt(0);
    }
  }

  String? _resolveFrontFromEvidence(
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
    if (scores.isEmpty) return null;
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : 0.0;
    if (best.value >= 3.0 && best.value >= second + 1.5) {
      return best.key;
    }
    if (ranked.length == 1 && best.value >= 3.0) {
      return best.key;
    }
    return null;
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
    if (_sessionLogs.isEmpty) {
      final message = '[LIVE-OCR][${widget.sessionId}] 로그가 없습니다.';
      return 'debugPrint(${jsonEncode(message)});';
    }
    return _sessionLogs.map((line) {
      final message = '[LIVE-OCR][${widget.sessionId}] $line';
      return 'debugPrint(${jsonEncode(message)});';
    }).join('\n');
  }

  String get _developerStatusDescription {
    return 'stage=${_ocrDebugStage.name}\n'
        'detail=${_ocrDebugStageDetail ?? '-'}\n'
        'attempt=$_attempt\n'
        'structured=${_ocrDebugStructuredPlate ?? '-'}\n'
        'cropText=${_ocrDebugCropText ?? '-'}\n'
        'microText=${_ocrDebugMicroCropText ?? '-'}\n'
        'recovered=${_ocrDebugRecoveredPlate ?? '-'}\n'
        'captureMs=${_ocrDebugCaptureMs ?? '-'}\n'
        'fullOcrMs=${_ocrDebugFullOcrMs ?? '-'}\n'
        'cropOcrMs=${_ocrDebugCropOcrMs ?? '-'}\n'
        'microOcrMs=${_ocrDebugMicroOcrMs ?? '-'}\n'
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

    final structuredWeakChips = _buildStructuredWeakChips(structuredWeakFrame);
    if (structuredWeakChips.isNotEmpty) {
      return structuredWeakChips;
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

    final voted = ranked
        .where((e) =>
            (_weakStructuredVotes[e.signature] ?? 0) >=
            _weakStructuredVoteThreshold)
        .toList();
    final source = voted.isNotEmpty ? voted : ranked;
    final selected = <_StructuredWeakCandidate>[];
    final evidenceKeys = <String>{};
    for (final candidate in source) {
      final evidenceKey = '${candidate.rawValue}|${candidate.back}';
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
        digits.sort((a, b) => a.$2.center.dx.compareTo(b.$2.center.dx));
        for (int i = digits.length - 4; i >= 0; i--) {
          final win = digits.sublist(i, i + 4);
          final heights = win.map((e) => e.$2.height).toList();
          final gaps = [
            win[1].$2.left - win[0].$2.right,
            win[2].$2.left - win[1].$2.right,
            win[3].$2.left - win[2].$2.right,
          ];
          final hMax = heights.reduce((a, b) => a > b ? a : b);
          final hMin = heights.reduce((a, b) => a < b ? a : b);
          final heightOk = (hMax / (hMin == 0 ? 1 : hMin)) < 1.25;
          final gapOk = gaps.every((g) => g > -2 && g < hMax * 0.8);
          if (!(heightOk && gapOk)) continue;
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

    final sep = r'[\s\.\-·•_]*';
    final unresolvedTokenReg = RegExp(
      '(?<![0-9A-Za-z])(\\d{2,3})$sep([A-Za-z○#|]{1,2})$sep(\\d{4})(?![0-9A-Za-z])',
    );
    final unresolvedHangulReg = RegExp(
      '(?<![0-9A-Za-z가-힣])(\\d{2,3})$sep([가-힣])$sep(\\d{4})(?![0-9A-Za-z가-힣])',
    );

    for (final source in _weakParseSources(result)) {
      for (final match in unresolvedTokenReg.allMatches(source)) {
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

      for (final digits in _extractWeakDigitSequences(source)) {
        if (digits.length == 8) {
          addCandidate(
            front: digits.substring(0, 3),
            back: digits.substring(4),
            observedToken: digits.substring(3, 4),
            rawValue: digits,
            frontLen: 3,
            tokenMissing: false,
            segmentationEvidence: _WeakSegmentationEvidence.observedSlot,
          );
          if (_preferredFrontLen == 2) {
            addCandidate(
              front: digits.substring(0, 2),
              back: digits.substring(4),
              observedToken: digits.substring(2, 4),
              rawValue: digits,
              frontLen: 2,
              tokenMissing: false,
              segmentationEvidence: _WeakSegmentationEvidence.inferred,
            );
          }
          continue;
        }

        if (digits.length == 7) {
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
        .map((e) =>
            '${e.front}?${e.back}:${e.rawValue}:token=${e.observedToken.isEmpty ? '-' : e.observedToken}:evidence=${e.segmentationEvidence.name}:${(_weakStructuredVotes[e.signature] ?? 0)}')
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
      final voteCmp = (_weakStructuredVotes[b.signature] ?? 0)
          .compareTo(_weakStructuredVotes[a.signature] ?? 0);
      if (voteCmp != 0) return voteCmp;
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
    Navigator.pop(
      context,
      LiveOcrSessionResult(
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
      ),
    );
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
                  unawaited(_meterTo(Offset(dx, dy)));
                },
                child: CameraPreview(
                  cam,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _OcrPublicOverlay(
                        revision: _ocrDebugRevision,
                        stage: _ocrDebugStage,
                        cropBytes: _ocrDebugCropBytes,
                        microCropBytes: _ocrDebugMicroCropBytes,
                      ),
                      if (_developerMode)
                        _OcrDebugOverlay(
                          revision: _ocrDebugRevision,
                          stage: _ocrDebugStage,
                          lineBoxes: _ocrDebugLineBoxes,
                          sourceImageSize: _ocrDebugSourceImageSize,
                          weakBox: _ocrDebugWeakBox,
                          cropBox: _ocrDebugCropBox,
                          microCropBox: _ocrDebugMicroCropBox,
                          focusPoint: _ocrDebugFocusPoint,
                          cropText: _ocrDebugCropText,
                          microCropText: _ocrDebugMicroCropText,
                          structuredPlate: _ocrDebugStructuredPlate,
                          recoveredPlate: _ocrDebugRecoveredPlate,
                          detail: _ocrDebugStageDetail,
                          captureMs: _ocrDebugCaptureMs,
                          fullOcrMs: _ocrDebugFullOcrMs,
                          cropOcrMs: _ocrDebugCropOcrMs,
                          microOcrMs: _ocrDebugMicroOcrMs,
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
    required this.cropBytes,
    required this.microCropBytes,
  });

  final int revision;
  final _OcrDebugStage stage;
  final Uint8List? cropBytes;
  final Uint8List? microCropBytes;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final imageBytes = microCropBytes ?? cropBytes;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageBytes != null)
            Positioned(
              right: 12,
              bottom: 78,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<String>('public-magnifier-$revision-${stage.name}'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 360),
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
                  width: 154,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.68),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(.82),
                      width: 1.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: .96, end: 1).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Image.memory(
                        imageBytes,
                        key: ValueKey<int>(identityHashCode(imageBytes)),
                        height: 84,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
      case _OcrDebugStage.microCropPrepared:
        return '가운데 글자를 더 크게 살펴보고 있어요';
      case _OcrDebugStage.microCropOcr:
        return '가운데 글자와 주변 숫자를 함께 확인하고 있어요';
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
    required this.microCropBox,
    required this.focusPoint,
    required this.cropText,
    required this.microCropText,
    required this.structuredPlate,
    required this.recoveredPlate,
    required this.detail,
    required this.captureMs,
    required this.fullOcrMs,
    required this.cropOcrMs,
    required this.microOcrMs,
  });

  final int revision;
  final _OcrDebugStage stage;
  final List<_OcrDebugLineBox> lineBoxes;
  final Size? sourceImageSize;
  final Rect? weakBox;
  final Rect? cropBox;
  final Rect? microCropBox;
  final Offset? focusPoint;
  final String? cropText;
  final String? microCropText;
  final String? structuredPlate;
  final String? recoveredPlate;
  final String? detail;
  final int? captureMs;
  final int? fullOcrMs;
  final int? cropOcrMs;
  final int? microOcrMs;

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
          final mappedMicro = source == null || microCropBox == null
              ? null
              : _mapDebugRect(microCropBox!, source, viewport);
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
              if (mappedMicro != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('micro-$revision-${mappedMicro.hashCode}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    final t = value.clamp(0.0, 1.0).toDouble();
                    final start = mappedCrop ?? mappedWeak ?? mappedMicro;
                    final animatedRect = Rect.lerp(
                      start,
                      mappedMicro,
                      t,
                    )!;
                    return CustomPaint(
                      painter: _OcrDebugRegionPainter(
                        rect: animatedRect,
                        opacity: .45 + (.55 * t),
                        color: colorScheme.error,
                        dashed: true,
                        label: 'MID MICRO CROP',
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
                    cropText: microCropText ?? cropText,
                    detail: detail,
                    captureMs: captureMs,
                    fullOcrMs: fullOcrMs,
                    cropOcrMs: (cropOcrMs ?? 0) + (microOcrMs ?? 0),
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
      case _OcrDebugStage.microCropPrepared:
        return 'MID MICRO CROP';
      case _OcrDebugStage.microCropOcr:
        return 'MICRO OCR';
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
