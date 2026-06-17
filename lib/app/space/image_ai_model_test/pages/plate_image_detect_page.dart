import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/ocr_learning_repository.dart';
import '../data/vehicle_image_classifier.dart';

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
  imageAutoAccepted,
  imageUserSelected,
  userAborted,
  permissionDenied,
  cameraInitFailed,
}

class LiveOcrSessionResult {
  final String sessionId;
  final bool plateRecognitionEnabled;
  final bool imageRecognitionEnabled;
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
  final String? rpsLabel;
  final String? rpsDisplayLabel;
  final double? rpsConfidence;
  final Map<String, double> rpsProbabilities;
  final Map<String, double> rpsRawScores;
  final List<String> rpsLogs;
  final String? rpsFailureReason;
  final String? rpsInstabilityReason;
  final bool rpsProbabilityMode;
  final bool rpsUserSelected;
  final bool rpsAutoAccepted;
  final String? rpsTopLabel;
  final String? rpsTopDisplayLabel;
  final double? rpsTopConfidence;
  final String? rpsSecondLabel;
  final String? rpsSecondDisplayLabel;
  final double? rpsSecondConfidence;
  final double? rpsConfidenceMargin;
  final double rpsMinAutoConfidence;
  final double rpsMinAutoMargin;

  const LiveOcrSessionResult({
    required this.sessionId,
    this.plateRecognitionEnabled = true,
    this.imageRecognitionEnabled = true,
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
    this.rpsLabel,
    this.rpsDisplayLabel,
    this.rpsConfidence,
    this.rpsProbabilities = const {},
    this.rpsRawScores = const {},
    this.rpsLogs = const [],
    this.rpsFailureReason,
    this.rpsInstabilityReason,
    this.rpsProbabilityMode = false,
    this.rpsUserSelected = false,
    this.rpsAutoAccepted = false,
    this.rpsTopLabel,
    this.rpsTopDisplayLabel,
    this.rpsTopConfidence,
    this.rpsSecondLabel,
    this.rpsSecondDisplayLabel,
    this.rpsSecondConfidence,
    this.rpsConfidenceMargin,
    this.rpsMinAutoConfidence = VehicleImageClassifier.minAutoConfidence,
    this.rpsMinAutoMargin = VehicleImageClassifier.minAutoMargin,
  });

  String get logText => logs.join('\n');

  String get rpsLogText => rpsLogs.join('\n');

  bool get plateSuccess => plate != null && plate!.isNotEmpty && !requiresMidCompletion;

  bool get rpsSuccess => rpsLabel != null && rpsLabel!.isNotEmpty;

  bool get enabledRecognitionSuccess {
    final plateOk = !plateRecognitionEnabled || plateSuccess;
    final imageOk = !imageRecognitionEnabled || rpsSuccess;
    return plateOk && imageOk;
  }

  String get plateExecutionStatus {
    if (!plateRecognitionEnabled) return '미실행';
    return plateSuccess ? '성공' : '실패';
  }

  String get imageExecutionStatus {
    if (!imageRecognitionEnabled) return '미실행';
    return rpsSuccess ? '성공' : '실패';
  }

  bool get combinedSuccess => enabledRecognitionSuccess;
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

class _StructuredWeakCandidate {
  final String signature;
  final String front;
  final String back;
  final String observedToken;
  final String rawValue;
  final int frontLen;
  final bool tokenMissing;
  final double score;

  const _StructuredWeakCandidate({
    required this.signature,
    required this.front,
    required this.back,
    required this.observedToken,
    required this.rawValue,
    required this.frontLen,
    required this.tokenMissing,
    required this.score,
  });
}

class PlateImageDetectPage extends StatefulWidget {
  final String sessionId;
  final bool plateRecognitionEnabled;
  final bool imageRecognitionEnabled;

  const PlateImageDetectPage({
    super.key,
    required this.sessionId,
    this.plateRecognitionEnabled = true,
    this.imageRecognitionEnabled = true,
  });

  @override
  State<PlateImageDetectPage> createState() => _PlateImageDetectPageState();
}

class _PlateImageDetectPageState extends State<PlateImageDetectPage> {
  CameraController? _controller;
  CameraDescription? _cameraDescription;
  ResolutionPreset _activePreset = ResolutionPreset.high;
  TextRecognizer? _recognizer;

  final OcrLearningRepository _learningRepo = OcrLearningRepository.instance;
  final VehicleImageClassifier _rpsClassifier = VehicleImageClassifier.instance;

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
  bool _rpsProbabilityMode = false;
  bool _rpsModelReady = false;
  bool _rpsUserSelected = false;

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
  String? _selectedRpsLabel;
  String? _selectedRpsDisplayLabel;
  String? _lastRpsFailureReason;
  String? _lastRpsInstabilityReason;
  String? _rpsTopLabel;
  String? _rpsTopDisplayLabel;
  String? _rpsSecondLabel;
  String? _rpsSecondDisplayLabel;
  String? _pendingPlate;
  String? _pendingSelectedChipLabel;
  LiveOcrExitType? _pendingPlateExitType;
  double? _selectedRpsConfidence;
  double? _rpsTopConfidence;
  double? _rpsSecondConfidence;
  double? _rpsConfidenceMargin;
  bool _rpsAutoAccepted = false;
  Map<String, double> _lastRpsProbabilities = const {};
  Map<String, double> _lastRpsRawScores = const {};

  List<String> _candidateChips = const [];
  List<_DisplayChip> _displayChips = const [];

  OcrLearningSummary? _learningSummary;
  Map<String, String> _dynMidMap = const {};
  Map<String, String> _dynCandidateMap = const {};
  int? _preferredFrontLen;

  final List<String> _sessionLogs = [];
  final List<String> _rpsSessionLogs = [];
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
  static const int _voteWindow = 4;
  static const int _stableVoteThreshold = 2;
  static const int _tentativeVoteThreshold = 2;
  static const int _weakStructuredVoteThreshold = 2;

  static const double _chipBottomSpacer = 24;
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
    '': ['러', '부', '누', '조', '허', '어', '저', '머', '버'],
    '4': ['러', '부', '누', '무', '버', '허'],
    '1': ['러', '어', '허', '누', '저'],
    '0': ['오', '어', '우', '조', '호', '아'],
    'O': ['오', '어', '우', '조', '호', '아'],
    '○': ['오', '어', '우', '조', '호', '아'],
    '2': ['조', '저', '자', '누'],
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
    if (widget.plateRecognitionEnabled) {
      _recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!widget.plateRecognitionEnabled && !widget.imageRecognitionEnabled) {
      _appendLog('인식 기능이 모두 OFF 상태입니다.');
      if (!mounted) return;
      await _finishAndPop(exitType: LiveOcrExitType.userAborted);
      return;
    }

    if (widget.plateRecognitionEnabled) {
      await _loadLearningPolicy();
    } else {
      _appendLog('번호판 인식 OFF: OCR 학습 정책 로드를 생략합니다.');
      if (mounted) {
        setState(() => _learningLoaded = true);
      } else {
        _learningLoaded = true;
      }
    }

    if (widget.imageRecognitionEnabled) {
      await _loadRpsModel();
    } else {
      _appendLog('이미지 인식 OFF: 차량 인식 모델 로드를 생략합니다.');
      if (mounted) {
        setState(() => _rpsModelReady = false);
      }
    }

    await _initCamera();
  }

  Future<void> _loadRpsModel() async {
    try {
      final logs = await _rpsClassifier.warmUp();
      for (final log in logs) {
        _appendRpsLog(log);
      }
      _appendLog('차량 인식 모델 준비 완료');
      if (mounted) {
        setState(() => _rpsModelReady = true);
      } else {
        _rpsModelReady = true;
      }
    } catch (e) {
      _lastRpsFailureReason = e.toString();
      _appendLog('차량 인식 모델 준비 오류 $e');
      _appendRpsLog('차량 인식 모델 준비 오류 $e');
      if (mounted) {
        setState(() => _rpsModelReady = false);
      }
    }
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
    _recognizer?.close();
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

      _meterTo(const Offset(0.5, 0.5));

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

  void _meterTo(Offset p) async {
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
      _sessionLogs.clear();
      _rpsSessionLogs.clear();
      _selectedRpsLabel = null;
      _selectedRpsDisplayLabel = null;
      _selectedRpsConfidence = null;
      _lastRpsFailureReason = null;
      _lastRpsInstabilityReason = null;
      _rpsTopLabel = null;
      _rpsTopDisplayLabel = null;
      _rpsSecondLabel = null;
      _rpsSecondDisplayLabel = null;
      _rpsTopConfidence = null;
      _rpsSecondConfidence = null;
      _rpsConfidenceMargin = null;
      _rpsAutoAccepted = false;
      _lastRpsProbabilities = const {};
      _lastRpsRawScores = const {};
      _rpsUserSelected = false;
      _pendingPlate = null;
      _pendingPlateExitType = null;
      _pendingSelectedChipLabel = null;
      _lastSavedLearningKey = null;
    }

    _autoGen++;
    final gen = _autoGen;
    _appendLog(
      '인식 시작 gen=$gen intervalMs=$_autoIntervalMs '
          'plate=${widget.plateRecognitionEnabled ? 'on' : 'off'} '
          'image=${widget.imageRecognitionEnabled ? 'on' : 'off'} '
          'forceInsert=${_allowForceInsert ? 'on' : 'off'} torch=${_torch ? 'on' : 'off'}',
    );
    _autoLoop(gen);
  }

  void _stopAuto() {
    _autoRunning = false;
    _autoGen++;
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

      try {
        final captured = await cam.takePicture();
        capturedPath = captured.path;
        _captureErrorStreak = 0;

        if (widget.imageRecognitionEnabled) {
          if (!(_rpsUserSelected && _selectedRpsLabel != null)) {
            final rpsResult = await _rpsClassifier.classifyFile(captured.path);
            _applyRpsResult(rpsResult);
            if (_hasRpsResultForEnabledSuccess &&
                _pendingPlate != null &&
                _pendingPlateExitType != null) {
              final pendingPlate = _pendingPlate!;
              final pendingExitType = _pendingPlateExitType!;
              final selectedChipLabel = _pendingSelectedChipLabel;
              _pendingPlate = null;
              _pendingPlateExitType = null;
              _pendingSelectedChipLabel = null;
              _appendLog('번호판 대기값과 차량 인식값 조건 충족 plate=$pendingPlate rps=${_selectedRpsDisplayLabel ?? _selectedRpsLabel}');
              await _finishAndPop(
                plate: pendingPlate,
                exitType: pendingExitType,
                selectedChipLabel: selectedChipLabel,
              );
              return;
            }
          }
        }

        RecognizedText? ocrResult;
        String allText = '';
        if (widget.plateRecognitionEnabled) {
          final recognizer = _recognizer;
          if (recognizer != null) {
            final input = InputImage.fromFilePath(captured.path);
            ocrResult = await recognizer.processImage(input);
            allText = ocrResult.text;
          } else {
            _appendLog('번호판 인식 ON이지만 OCR recognizer가 초기화되지 않았습니다.');
          }
        }

        _attempt++;

        if (widget.plateRecognitionEnabled) {
          _lastText = allText.replaceAll('\n', ' ');
          if ((_lastText ?? '').length > 180) {
            _lastText = '${_lastText!.substring(0, 180)}…';
          }
          _appendLog('attempt=$_attempt ocrText=${_lastText ?? ''}');
        } else {
          _lastText = '번호판 인식 OFF';
          _appendLog('attempt=$_attempt plateRecognition=off imageRecognition=${widget.imageRecognitionEnabled ? 'on' : 'off'}');
        }

        if (!widget.plateRecognitionEnabled) {
          if (widget.imageRecognitionEnabled && _hasRpsResultForEnabledSuccess) {
            await _finishAndPop(
              plate: null,
              exitType: LiveOcrExitType.imageAutoAccepted,
            );
            return;
          }
          if (widget.imageRecognitionEnabled && _rpsProbabilityMode && _lastRpsProbabilities.isNotEmpty) {
            _appendLog('이미지 인식 확률 후보 선택 대기 probabilities=${_formatRpsProbabilities(_lastRpsProbabilities)}');
            _stopAuto();
            if (mounted) {
              setState(() {});
            }
            continue;
          }
          if (mounted) {
            setState(() {});
          }
          continue;
        }

        final direct = _extractStrictKoreanPlate(allText);
        if (direct != null) {
          _usedLearningMidLast = false;
          _usedLearningRankLast = false;
          _appendLog('직접 확정 $direct');
          final completed = await _finishWhenEnabledRecognitionReady(
            plate: direct,
            exitType: LiveOcrExitType.autoDirect,
          );
          if (completed) return;
        }

        final loose = _extractLooseKoreanPlate(allText, onUseLearningMid: () {
          usedLearningMidThis = true;
        });
        if (loose != null) {
          _usedLearningMidLast = usedLearningMidThis;
          _usedLearningRankLast = false;
          _appendLog('완화 확정 $loose');
          final completed = await _finishWhenEnabledRecognitionReady(
            plate: loose,
            exitType: LiveOcrExitType.autoLoose,
          );
          if (completed) return;
        }

        final rawSet = <String>{};
        rawSet.addAll(
            _extractModernCandidatesAnyChar(allText, onUseLearningMid: () {
              usedLearningMidThis = true;
            }));
        rawSet.addAll(_extractLegacyRegionCandidates(allText));
        rawSet.addAll(_extractDigitsOnlyNoMidCandidates(allText));
        if (ocrResult != null) {
          rawSet.addAll(_extractByGeometryCandidates(ocrResult));
        }
        rawSet.addAll(
            _extractWeakRecoverableCandidates(allText, onUseLearningMid: () {
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

        final structuredWeakFrame = _extractStructuredWeakCandidates(allText);
        _pushObservedWeakMidEvidence(allText, structuredWeakFrame);
        _pushVoteFrame(_stableFrames, _stableVotes, stableFrame);
        _pushVoteFrame(_tentativeFrames, _tentativeVotes, tentativeFrame);
        _pushWeakStructuredFrame(structuredWeakFrame);

        final displayChips = _buildDisplayChips(
          stableFrame,
          tentativeFrame,
          weakFrame,
          structuredWeakFrame,
        );
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
            final completed = await _finishWhenEnabledRecognitionReady(
              plate: force,
              exitType: LiveOcrExitType.autoForceInsert,
            );
            if (completed) return;
          }
        }
        if (kDebugMode && mounted) {
          setState(() => _debugText = 'attempt:$_attempt');
        }
      } catch (e) {
        final msg = e.toString();
        if (e is CameraException || msg.contains('ImageCaptureException')) {
          _captureErrorStreak++;
          _appendLog('autoLoop 오류 $e');
          if (_captureErrorStreak >= _captureErrorRecoverThreshold) {
            await _recoverCameraAfterCaptureFailure();
          } else if (_captureErrorStreak >= _captureErrorBackoffThreshold) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } else {
          _appendLog('autoLoop 오류 $e');
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
          Duration(milliseconds: _autoIntervalMs.clamp(200, 3000)));
    }
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    _sessionLogs.add('[$ts] $message');
    if (_sessionLogs.length > _maxSessionLogLines) {
      _sessionLogs.removeAt(0);
    }
  }

  void _appendRpsLog(String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    _rpsSessionLogs.add('[$ts] $message');
    if (_rpsSessionLogs.length > _maxSessionLogLines) {
      _rpsSessionLogs.removeAt(0);
    }
  }

  void _applyRpsResult(VehicleImageClassifierResult result) {
    for (final log in result.logs) {
      _appendRpsLog(log);
    }

    _rpsTopLabel = result.topLabel;
    _rpsTopDisplayLabel = result.topDisplayLabel;
    _rpsSecondLabel = result.secondLabel;
    _rpsSecondDisplayLabel = result.secondDisplayLabel;
    _rpsTopConfidence = result.topConfidence;
    _rpsSecondConfidence = result.secondConfidence;
    _rpsConfidenceMargin = result.confidenceMargin;

    if (!result.success) {
      _selectedRpsLabel = null;
      _selectedRpsDisplayLabel = null;
      _selectedRpsConfidence = null;
      _rpsUserSelected = false;
      _rpsAutoAccepted = false;
      _lastRpsFailureReason = result.failureReason ?? 'vehicle_inference_failed';
      _lastRpsInstabilityReason = null;
      _appendLog('차량 인식 인식 실패 reason=${_lastRpsFailureReason ?? '-'}');
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _lastRpsProbabilities = result.probabilities;
    _lastRpsRawScores = result.rawScores;
    _lastRpsInstabilityReason = result.instabilityReason;

    if (!_rpsProbabilityMode) {
      _applyAutomaticRpsDecisionFromResult(result);
    } else {
      _lastRpsFailureReason = null;
      _appendLog(
        '차량 인식 확률 후보 갱신 inputMode=${VehicleImageClassifier.inputMode} '
        'top1=${result.topLabel ?? '-'} ${_formatProbability(result.topConfidence)} '
        'top2=${result.secondLabel ?? '-'} ${_formatProbability(result.secondConfidence)} '
        'margin=${_formatProbability(result.confidenceMargin)} '
        'autoAcceptable=${result.autoAcceptable} '
        'instability=${result.instabilityReason ?? '-'} '
        'probabilities=${_formatRpsProbabilities(result.probabilities)}',
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _applyAutomaticRpsDecisionFromResult(VehicleImageClassifierResult result) {
    if (result.autoAcceptable && result.label != null && result.label!.isNotEmpty) {
      _selectedRpsLabel = result.label;
      _selectedRpsDisplayLabel = result.displayLabel;
      _selectedRpsConfidence = result.confidence;
      _rpsUserSelected = false;
      _rpsAutoAccepted = true;
      _lastRpsFailureReason = null;
      _lastRpsInstabilityReason = null;
      _appendLog(
        '차량 인식 자동 판정 승인 inputMode=${VehicleImageClassifier.inputMode} '
        'label=${result.label} display=${result.displayLabel} '
        'confidence=${_formatProbability(result.confidence)} '
        'margin=${_formatProbability(result.confidenceMargin)} '
        'minConfidence=${_formatProbability(result.minAutoConfidence)} '
        'minMargin=${_formatProbability(result.minAutoMargin)}',
      );
      return;
    }

    _selectedRpsLabel = null;
    _selectedRpsDisplayLabel = null;
    _selectedRpsConfidence = null;
    _rpsUserSelected = false;
    _rpsAutoAccepted = false;
    _lastRpsFailureReason = result.instabilityReason ?? 'vehicle_unstable_confidence';
    _appendLog(
      '차량 인식 자동 판정 보류 inputMode=${VehicleImageClassifier.inputMode} '
      'top1=${result.topLabel ?? '-'} ${_formatProbability(result.topConfidence)} '
      'top2=${result.secondLabel ?? '-'} ${_formatProbability(result.secondConfidence)} '
      'margin=${_formatProbability(result.confidenceMargin)} '
      'minConfidence=${_formatProbability(result.minAutoConfidence)} '
      'minMargin=${_formatProbability(result.minAutoMargin)} '
      'reason=${_lastRpsFailureReason ?? '-'}',
    );
  }

  void _applyAutomaticRpsDecisionFromStoredProbabilities() {
    if (_lastRpsProbabilities.isEmpty) {
      return;
    }
    final ranked = _lastRpsProbabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    final second = ranked.length < 2 ? null : ranked[1];
    final margin = second == null ? null : top.value - second.value;
    final accepted = margin != null &&
        top.value >= VehicleImageClassifier.minAutoConfidence &&
        margin >= VehicleImageClassifier.minAutoMargin;
    _rpsTopLabel = top.key;
    _rpsTopDisplayLabel = VehicleImageClassifier.displayLabels[top.key] ?? top.key;
    _rpsTopConfidence = top.value;
    _rpsSecondLabel = second?.key;
    _rpsSecondDisplayLabel = second == null ? null : VehicleImageClassifier.displayLabels[second.key] ?? second.key;
    _rpsSecondConfidence = second?.value;
    _rpsConfidenceMargin = margin;
    if (accepted) {
      _selectedRpsLabel = top.key;
      _selectedRpsDisplayLabel = VehicleImageClassifier.displayLabels[top.key] ?? top.key;
      _selectedRpsConfidence = top.value;
      _rpsUserSelected = false;
      _rpsAutoAccepted = true;
      _lastRpsFailureReason = null;
      _lastRpsInstabilityReason = null;
      _appendLog(
        '차량 인식 자동 모드 전환 승인 label=$top.key confidence=${_formatProbability(top.value)} margin=${_formatProbability(margin)}',
      );
      return;
    }
    _selectedRpsLabel = null;
    _selectedRpsDisplayLabel = null;
    _selectedRpsConfidence = null;
    _rpsUserSelected = false;
    _rpsAutoAccepted = false;
    _lastRpsFailureReason = _buildStoredRpsInstabilityReason(top.value, margin);
    _lastRpsInstabilityReason = _lastRpsFailureReason;
    _appendLog(
      '차량 인식 자동 모드 전환 보류 top1=${top.key} ${_formatProbability(top.value)} top2=${second?.key ?? '-'} ${_formatProbability(second?.value)} margin=${_formatProbability(margin)} reason=${_lastRpsFailureReason ?? '-'}',
    );
  }

  String _buildStoredRpsInstabilityReason(double topConfidence, double? margin) {
    if (margin == null) {
      return 'vehicle_probability_unavailable';
    }
    final lowConfidence = topConfidence < VehicleImageClassifier.minAutoConfidence;
    final lowMargin = margin < VehicleImageClassifier.minAutoMargin;
    if (lowConfidence && lowMargin) {
      return 'vehicle_low_confidence_and_low_margin';
    }
    if (lowConfidence) {
      return 'vehicle_low_confidence';
    }
    if (lowMargin) {
      return 'vehicle_low_margin';
    }
    return 'vehicle_unstable_confidence';
  }

  bool get _hasRpsResultForEnabledSuccess {
    return _selectedRpsLabel != null && _selectedRpsLabel!.isNotEmpty;
  }

  Future<bool> _finishWhenEnabledRecognitionReady({
    required String plate,
    required LiveOcrExitType exitType,
    String? selectedChipLabel,
  }) async {
    final normalizedPlate = _normalizeCandidateKey(plate);

    if (!_isValidKoreanPlate(normalizedPlate)) {
      _appendLog('선택 기능 조건 미충족 invalidPlate=$normalizedPlate');
      return false;
    }

    if (!widget.imageRecognitionEnabled) {
      _appendLog('번호판 인식 조건 충족 plate=$normalizedPlate imageRecognition=off');
      await _finishAndPop(
        plate: normalizedPlate,
        exitType: exitType,
        selectedChipLabel: selectedChipLabel,
      );
      return true;
    }

    if (_hasRpsResultForEnabledSuccess) {
      _appendLog('선택 기능 조건 충족 plate=$normalizedPlate rps=${_selectedRpsDisplayLabel ?? _selectedRpsLabel}');
      await _finishAndPop(
        plate: normalizedPlate,
        exitType: exitType,
        selectedChipLabel: selectedChipLabel,
      );
      return true;
    }

    _pendingPlate = normalizedPlate;
    _pendingPlateExitType = exitType;
    _pendingSelectedChipLabel = selectedChipLabel;
    _appendLog('번호판 선택 반영 plate=$normalizedPlate 차량 인식 후보 선택 대기 probabilities=${_formatRpsProbabilities(_lastRpsProbabilities)} rpsFailure=${_lastRpsFailureReason ?? '-'}');
    if (mounted) {
      setState(() {});
    }
    return false;
  }

  Future<void> _selectRpsResult(String label) async {
    final probability = _lastRpsProbabilities[label];
    if (probability == null) {
      return;
    }

    if (_rpsUserSelected && _selectedRpsLabel == label) {
      setState(() {
        _selectedRpsLabel = null;
        _selectedRpsDisplayLabel = null;
        _selectedRpsConfidence = null;
        _rpsUserSelected = false;
        _rpsAutoAccepted = false;
        _lastRpsFailureReason = null;
      });
      _appendLog('차량 인식 사용자 선택 해제 label=$label 모델 추론 재개');
      return;
    }

    setState(() {
      _selectedRpsLabel = label;
      _selectedRpsDisplayLabel = VehicleImageClassifier.displayLabels[label] ?? label;
      _selectedRpsConfidence = probability;
      _rpsUserSelected = true;
      _rpsAutoAccepted = false;
      _lastRpsFailureReason = null;
      _lastRpsInstabilityReason = null;
    });
    _appendLog('차량 인식 사용자 선택 label=$label display=$_selectedRpsDisplayLabel confidence=${_formatProbability(probability)} 모델 추론 일시정지');

    final pendingPlate = _pendingPlate;
    final pendingExitType = _pendingPlateExitType;
    if (pendingPlate != null && pendingExitType != null) {
      final selectedChipLabel = _pendingSelectedChipLabel;
      _pendingPlate = null;
      _pendingPlateExitType = null;
      _pendingSelectedChipLabel = null;
      await _finishAndPop(
        plate: pendingPlate,
        exitType: pendingExitType,
        selectedChipLabel: selectedChipLabel,
      );
      return;
    }

    if (!widget.plateRecognitionEnabled && widget.imageRecognitionEnabled) {
      await _finishAndPop(
        plate: null,
        exitType: LiveOcrExitType.imageUserSelected,
      );
    }
  }

  String _formatProbability(double? value) {
    if (value == null) return '-';
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  String _formatRpsProbabilities(Map<String, double> probabilities) {
    if (probabilities.isEmpty) return '-';
    final ordered = VehicleImageClassifier.fallbackLabels;
    final values = <String>[];
    for (final key in ordered) {
      final value = probabilities[key];
      if (value == null) continue;
      final display = VehicleImageClassifier.displayLabels[key] ?? key;
      values.add('$display:${_formatProbability(value)}');
    }
    for (final entry in probabilities.entries) {
      if (ordered.contains(entry.key)) continue;
      final display = VehicleImageClassifier.displayLabels[entry.key] ?? entry.key;
      values.add('$display:${_formatProbability(entry.value)}');
    }
    return values.join(', ');
  }

  String _rpsStatusText() {
    if (!widget.imageRecognitionEnabled) return '차량 인식 미실행';
    if (_selectedRpsDisplayLabel != null) {
      final mode = _rpsUserSelected ? '사용자 선택, 다시 누르면 해제' : '자동 판정';
      return '$mode ${_selectedRpsDisplayLabel!} ${_formatProbability(_selectedRpsConfidence)}';
    }
    if (_rpsProbabilityMode && _lastRpsProbabilities.isNotEmpty) {
      final unstable = _lastRpsInstabilityReason == null ? '' : ' · 불안정 ${_lastRpsInstabilityReason!}';
      return '확률 표시 중, 사용자 선택 필요$unstable';
    }
    if (_lastRpsFailureReason != null) {
      return '차량 인식 보류 ${_lastRpsFailureReason!}';
    }
    return _rpsModelReady ? '차량 인식 대기 중' : '차량 인식 모델 준비 중';
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
    final selected = voted.isNotEmpty ? voted : ranked.take(1).toList();

    return selected.take(2).map((e) {
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

  List<String> _extractDigitsOnlyNoMidCandidates(String text) {
    final norm = _normalizeFlat(text);
    final out = <String>[];
    for (final m in RegExp(r'(?<!\d)(\d{6,8})(?!\d)').allMatches(norm)) {
      out.add(m.group(1)!);
    }
    return out;
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

  List<String> _extractWeakRecoverableCandidates(String text,
      {required VoidCallback onUseLearningMid}) {
    final norm = _normalizeFlat(text);
    final stripped = _normalizeCandidateKey(norm);
    final out = <String>{};

    for (final m in RegExp(r'(?<!\d)(\d{2,3})([^가-힣\s]{1,2})(\d{4})(?!\d)')
        .allMatches(norm)) {
      final front = m.group(1)!;
      final token = _normalizeCandidateKey(m.group(2)!);
      final back = m.group(3)!;
      final key = '$front$token$back';
      final mapped = _dynCandidateMap[key];
      if (mapped != null && _isModernPlate(mapped)) {
        out.add(_normalizeCandidateKey(mapped));
      }
      final mid = _normalizeMidToken(token, onUseLearningMid: onUseLearningMid);
      if (_KoreanPlatePolicy.allowedNewMids.contains(mid)) {
        out.add('$front$mid$back');
      }
    }

    for (final m in RegExp(r'(?<!\d)(\d{8})(?!\d)').allMatches(stripped)) {
      final digits = m.group(1)!;
      final mapped = _dynCandidateMap[digits];
      if (mapped != null && _isModernPlate(mapped)) {
        out.add(_normalizeCandidateKey(mapped));
      }
      final front3 = digits.substring(0, 3);
      final token1 = digits.substring(3, 4);
      final back4 = digits.substring(4);
      final mid1 =
      _normalizeMidToken(token1, onUseLearningMid: onUseLearningMid);
      if (_KoreanPlatePolicy.allowedNewMids.contains(mid1)) {
        out.add('$front3$mid1$back4');
      }
    }

    for (final m in RegExp(r'(?<!\d)(\d{7})(?!\d)').allMatches(stripped)) {
      final digits = m.group(1)!;
      final mapped = _dynCandidateMap[digits];
      if (mapped != null && _isModernPlate(mapped)) {
        out.add(_normalizeCandidateKey(mapped));
      }
      if (_preferredFrontLen == 3) {
        final front = digits.substring(0, 3);
        final back = digits.substring(3);
        final token = _dynMidMap[''];
        if (token != null &&
            _KoreanPlatePolicy.allowedNewMids.contains(token)) {
          out.add('$front$token$back');
        }
      }
      if (_preferredFrontLen == 2) {
        final front = digits.substring(0, 2);
        final back = digits.substring(2);
        if (back.length == 4) {
          final token = _dynMidMap[''];
          if (token != null &&
              _KoreanPlatePolicy.allowedNewMids.contains(token)) {
            out.add('$front$token$back');
          }
        }
      }
    }

    return out.toList();
  }

  List<_StructuredWeakCandidate> _extractStructuredWeakCandidates(String text) {
    final norm = _normalizeFlat(text);
    final stripped = _normalizeCandidateKey(norm);
    final out = <_StructuredWeakCandidate>[];
    final seen = <String>{};

    void addCandidate({
      required String front,
      required String back,
      required String observedToken,
      required String rawValue,
      required int frontLen,
      required bool tokenMissing,
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
          score: score,
        ),
      );
    }

    for (final m in RegExp(r'(?<!\d)(\d{2,3})([^가-힣\s]{1,2})(\d{4})(?!\d)')
        .allMatches(norm)) {
      final front = m.group(1)!;
      final token = _normalizeCandidateKey(m.group(2)!);
      final back = m.group(3)!;
      addCandidate(
        front: front,
        back: back,
        observedToken: token,
        rawValue: '$front$token$back',
        frontLen: front.length,
        tokenMissing: token.isEmpty,
      );
    }

    for (final m in RegExp(r'(?<!\d)(\d{8})(?!\d)').allMatches(stripped)) {
      final digits = m.group(1)!;
      addCandidate(
        front: digits.substring(0, 3),
        back: digits.substring(4),
        observedToken: digits.substring(3, 4),
        rawValue: digits,
        frontLen: 3,
        tokenMissing: false,
      );
      if (_preferredFrontLen == 2) {
        addCandidate(
          front: digits.substring(0, 2),
          back: digits.substring(4),
          observedToken: digits.substring(2, 4),
          rawValue: digits,
          frontLen: 2,
          tokenMissing: false,
        );
      }
    }

    for (final m in RegExp(r'(?<!\d)(\d{7})(?!\d)').allMatches(stripped)) {
      final digits = m.group(1)!;
      addCandidate(
        front: digits.substring(0, 3),
        back: digits.substring(3),
        observedToken: '',
        rawValue: digits,
        frontLen: 3,
        tokenMissing: true,
      );
    }

    for (final m in RegExp(r'(?<!\d)(\d{6})(?!\d)').allMatches(stripped)) {
      final digits = m.group(1)!;
      addCandidate(
        front: digits.substring(0, 2),
        back: digits.substring(2),
        observedToken: '',
        rawValue: digits,
        frontLen: 2,
        tokenMissing: true,
      );
    }

    return out;
  }

  double _scoreStructuredWeakCandidate({
    required String front,
    required String back,
    required String observedToken,
    required int frontLen,
    required bool tokenMissing,
  }) {
    var score = 1.0;
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
      for (final fallback in ['러', '부', '누', '조', '허', '어', '저']) {
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
    '${e.front}?${e.back}:${e.rawValue}:${(_weakStructuredVotes[e.signature] ?? 0)}')
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
        plateRecognitionEnabled: widget.plateRecognitionEnabled,
        imageRecognitionEnabled: widget.imageRecognitionEnabled,
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
        rpsLabel: _selectedRpsLabel,
        rpsDisplayLabel: _selectedRpsDisplayLabel,
        rpsConfidence: _selectedRpsConfidence,
        rpsProbabilities: Map<String, double>.from(_lastRpsProbabilities),
        rpsRawScores: Map<String, double>.from(_lastRpsRawScores),
        rpsLogs: List<String>.from(_rpsSessionLogs, growable: false),
        rpsFailureReason: _lastRpsFailureReason,
        rpsInstabilityReason: _lastRpsInstabilityReason,
        rpsProbabilityMode: _rpsProbabilityMode,
        rpsUserSelected: _rpsUserSelected,
        rpsAutoAccepted: _rpsAutoAccepted,
        rpsTopLabel: _rpsTopLabel,
        rpsTopDisplayLabel: _rpsTopDisplayLabel,
        rpsTopConfidence: _rpsTopConfidence,
        rpsSecondLabel: _rpsSecondLabel,
        rpsSecondDisplayLabel: _rpsSecondDisplayLabel,
        rpsSecondConfidence: _rpsSecondConfidence,
        rpsConfidenceMargin: _rpsConfidenceMargin,
        rpsMinAutoConfidence: VehicleImageClassifier.minAutoConfidence,
        rpsMinAutoMargin: VehicleImageClassifier.minAutoMargin,
      ),
    );
  }

  void _showLearningDialog() {
    final cs = Theme.of(context).colorScheme;
    final committed = _learningSummary?.committedCount ?? 0;
    final pending = _learningSummary?.pendingCount ?? 0;
    final dynCnt = _dynMidMap.length;
    final pref = _preferredFrontLen;
    final lastMs = _learningSummary?.lastCommittedAtMs;
    final lastText = lastMs == null
        ? '없음'
        : DateTime.fromMillisecondsSinceEpoch(lastMs).toLocal().toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('학습 데이터 상태'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('커밋(정답 확정): $committed건'),
            Text('대기(미커밋): $pending건'),
            Text('동적 mid 보정맵: $dynCnt개'),
            Text('후보 보정맵: ${_dynCandidateMap.length}개'),
            Text('선호 앞자리 길이: ${pref ?? '-'}'),
            Text('마지막 커밋: $lastText'),
            const SizedBox(height: 12),
            Text(
              '한국 차량 번호판 형식으로 검증된 값만 학습 저장에 반영합니다.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  String _buildRecognitionLogText() {
    _DisplayChip? weakChip;
    for (final chip in _displayChips) {
      if (chip.requiresMidCompletion) {
        weakChip = chip;
        break;
      }
    }
    final requiresMidCompletion = weakChip?.requiresMidCompletion ?? false;
    final weakFront = weakChip?.weakFront;
    final weakBack = weakChip?.weakBack;
    final weakObservedValue = weakChip?.weakObservedValue ?? weakChip?.value;

    final lines = <String>[
      '----- RECOGNITION DEBUG LOG -----',
      'time=${DateTime.now().toIso8601String()}',
      'sessionId=${widget.sessionId}',
      'plateRecognitionEnabled=${widget.plateRecognitionEnabled}',
      'imageRecognitionEnabled=${widget.imageRecognitionEnabled}',
      'autoRunning=$_autoRunning',
      '',
      '----- THRESHOLD -----',
      'vehicleMinConfidence=${_formatProbability(VehicleImageClassifier.minAutoConfidence)}',
      'vehicleMinMargin=${_formatProbability(VehicleImageClassifier.minAutoMargin)}',
      'vehicleModelPausedByUserSelection=${_rpsUserSelected && _selectedRpsLabel != null}',
      'vehicleInputMode=${VehicleImageClassifier.inputMode}',
      'vehicleModelAsset=${VehicleImageClassifier.modelAssetPath}',
      'vehicleLabelsAsset=${VehicleImageClassifier.labelsAssetPath}',
      '',
      '----- LAST OCR STATE -----',
      'lastText=${_lastText ?? '-'}',
      'lastFailureReason=${_lastFailureReason ?? '-'}',
      'pendingPlate=${_pendingPlate ?? '-'}',
      'requiresMidCompletion=$requiresMidCompletion',
      'weakFront=${weakFront ?? '-'}',
      'weakBack=${weakBack ?? '-'}',
      'weakObservedValue=${weakObservedValue ?? '-'}',
      '',
      '----- LAST VEHICLE STATE -----',
      'modelReady=$_rpsModelReady',
      'probabilityMode=$_rpsProbabilityMode',
      'selectedLabel=${_selectedRpsLabel ?? '-'}',
      'selectedDisplay=${_selectedRpsDisplayLabel ?? '-'}',
      'selectedConfidence=${_formatProbability(_selectedRpsConfidence)}',
      'top1=${_rpsTopLabel ?? '-'}',
      'top1Display=${_rpsTopDisplayLabel ?? '-'}',
      'top1Confidence=${_formatProbability(_rpsTopConfidence)}',
      'top2=${_rpsSecondLabel ?? '-'}',
      'top2Display=${_rpsSecondDisplayLabel ?? '-'}',
      'top2Confidence=${_formatProbability(_rpsSecondConfidence)}',
      'margin=${_formatProbability(_rpsConfidenceMargin)}',
      'autoAccepted=$_rpsAutoAccepted',
      'userSelected=$_rpsUserSelected',
      'failureReason=${_lastRpsFailureReason ?? '-'}',
      'probabilities=${_formatRpsProbabilities(_lastRpsProbabilities)}',
      'rawScores=${_formatRpsProbabilities(_lastRpsRawScores)}',
      '',
      '----- OCR SESSION LOG -----',
      _sessionLogs.isEmpty ? '로그가 없습니다.' : _sessionLogs.join('\n'),
      '',
      '----- VEHICLE MODEL LOG -----',
      _rpsSessionLogs.isEmpty ? '로그가 없습니다.' : _rpsSessionLogs.join('\n'),
    ];
    return lines.join('\n');
  }

  Future<void> _copyRecognitionLogToClipboard() async {
    final logText = _buildRecognitionLogText();
    await Clipboard.setData(ClipboardData(text: logText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('인식 로그를 클립보드에 복사했습니다.')),
    );
  }

  void _showLogsDialog() {
    final cs = Theme.of(context).colorScheme;
    final logText = _buildRecognitionLogText();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('인식 로그'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              logText.isEmpty ? '로그가 없습니다.' : logText,
              style: TextStyle(color: cs.onSurface, fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logText));
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('인식 로그를 클립보드에 복사했습니다.')),
              );
            },
            child: const Text('복사'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final cam = _controller;
    final preview = (!(_initialized && cam != null && cam.value.isInitialized))
        ? Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
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
            _meterTo(Offset(dx, dy));
          },
          child: CameraPreview(cam),
        );
      },
    );

    final hasLearning =
        (_learningSummary?.committedCount ?? 0) > 0 || _dynMidMap.isNotEmpty;
    final usedLearningNow = _usedLearningMidLast || _usedLearningRankLast;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        _appendLog('시스템 뒤로가기 종료');
        await _finishAndPop(exitType: LiveOcrExitType.userAborted);
      },
      child: Scaffold(
        backgroundColor: cs.scrim,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: cs.scrim,
          foregroundColor: cs.surface,
          systemOverlayStyle: cs.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: widget.imageRecognitionEnabled ? (_rpsProbabilityMode ? '차량 인식 확률 표시 ON' : '차량 인식 확률 표시 OFF') : '차량 인식 확률 표시 OFF',
              onPressed: widget.imageRecognitionEnabled ? () {
                final nextMode = !_rpsProbabilityMode;
                setState(() {
                  _rpsProbabilityMode = nextMode;
                  if (_rpsProbabilityMode) {
                    _selectedRpsLabel = null;
                    _selectedRpsDisplayLabel = null;
                    _selectedRpsConfidence = null;
                    _rpsUserSelected = false;
                    _rpsAutoAccepted = false;
                    _lastRpsFailureReason = null;
                  }
                });
                if (!nextMode && _lastRpsProbabilities.isNotEmpty) {
                  _applyAutomaticRpsDecisionFromStoredProbabilities();
                  if (mounted) {
                    setState(() {});
                  }
                }
                _appendLog('차량 인식 확률 표시 ${_rpsProbabilityMode ? 'ON' : 'OFF'}');
              } : null,
              icon: Icon(_rpsProbabilityMode ? Icons.percent : Icons.percent_outlined),
            ),
            IconButton(
              tooltip: '인식 로그 보기',
              onPressed: _showLogsDialog,
              icon: const Icon(Icons.article_outlined),
            ),
            IconButton(
              tooltip: hasLearning ? '학습 데이터 있음' : '학습 데이터 없음',
              onPressed: widget.plateRecognitionEnabled && _learningLoaded ? _showLearningDialog : null,
              icon: Icon(hasLearning ? Icons.school : Icons.school_outlined),
            ),
            if (usedLearningNow)
              IconButton(
                tooltip: '학습 보정 적용 중',
                onPressed: widget.plateRecognitionEnabled && _learningLoaded ? _showLearningDialog : null,
                icon: const Icon(Icons.auto_awesome),
              ),
            IconButton(
              tooltip: widget.plateRecognitionEnabled ? (_allowForceInsert ? '강제삽입 ON' : '강제삽입 OFF') : '강제삽입 OFF',
              onPressed: widget.plateRecognitionEnabled ? () {
                setState(() => _allowForceInsert = !_allowForceInsert);
                _appendLog('강제삽입 ${_allowForceInsert ? 'ON' : 'OFF'}');
              } : null,
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
                color: cs.scrim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_debugText != null)
                      Text(
                        _debugText!,
                        style: TextStyle(
                            color: cs.surface.withOpacity(0.85), fontSize: 12),
                      ),
                    if (_lastText != null && _lastText!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '최근: $_lastText',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.surface.withOpacity(0.70),
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
                              cs: cs,
                              icon: hasLearning
                                  ? Icons.school
                                  : Icons.school_outlined,
                              text:
                              '학습 ${_learningSummary?.committedCount ?? 0}건',
                            ),
                            _infoPill(
                              cs: cs,
                              icon: Icons.tune,
                              text: '보정맵 ${_dynMidMap.length}개',
                            ),
                            _infoPill(
                              cs: cs,
                              icon: Icons.receipt_long,
                              text: '로그 ${_sessionLogs.length}줄',
                            ),
                            _infoPill(
                              cs: cs,
                              icon: _rpsProbabilityMode ? Icons.percent : Icons.auto_awesome,
                              text: widget.imageRecognitionEnabled ? (_rpsProbabilityMode ? '차량 인식 확률ON' : '차량 인식 자동') : '차량 인식 OFF',
                            ),
                            _infoPill(
                              cs: cs,
                              icon: Icons.directions_car_filled_outlined,
                              text: widget.imageRecognitionEnabled ? _rpsStatusText() : '차량 인식 미실행',
                            ),
                            if (usedLearningNow)
                              _infoPill(
                                cs: cs,
                                icon: Icons.auto_awesome,
                                text: '보정 적용',
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: true,
              minimum: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                color: cs.scrim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.imageRecognitionEnabled) _buildRpsPanel(),
                    if (widget.imageRecognitionEnabled && widget.plateRecognitionEnabled)
                      const SizedBox(height: 8),
                    if (widget.plateRecognitionEnabled) _buildCandidates(),
                    const SizedBox(height: 8),
                    _buildLogCopyButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCopyButton() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _copyRecognitionLogToClipboard,
        icon: const Icon(Icons.copy_all_outlined, size: 18),
        label: const Text('인식 로그 복사'),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.surface,
          side: BorderSide(color: cs.surface.withOpacity(0.28)),
          backgroundColor: cs.surface.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _infoPill({
    required ColorScheme cs,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.12),
        border: Border.all(color: cs.surface.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.surface.withOpacity(0.9)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: cs.surface.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRpsPanel() {
    final cs = Theme.of(context).colorScheme;
    if (!widget.imageRecognitionEnabled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.10),
          border: Border.all(color: cs.surface.withOpacity(0.22)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '이미지 인식이 OFF라 차량 인식 모델을 실행하지 않습니다.',
          style: TextStyle(color: cs.surface.withOpacity(0.78), fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      );
    }
    final theme = Theme.of(context);
    final probabilities = _lastRpsProbabilities;
    final waitingUserChoice = probabilities.isNotEmpty && _selectedRpsLabel == null;
    final vehicleSelectionPaused = _rpsUserSelected && _selectedRpsLabel != null;
    final pendingPlate = _pendingPlate;

    if (probabilities.isEmpty && _selectedRpsLabel == null && _lastRpsFailureReason == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.10),
          border: Border.all(color: cs.surface.withOpacity(0.22)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _rpsModelReady ? '차량 인식 모델 대기 중입니다. 카메라 프레임을 분석하면 결과가 표시됩니다.' : '차량 인식 모델을 준비 중입니다.',
          style: TextStyle(color: cs.surface.withOpacity(0.78), fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      );
    }

    final entries = probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.12),
        border: Border.all(color: waitingUserChoice ? cs.primary.withOpacity(0.75) : cs.surface.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '차량 전면부 인식 모델',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.surface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pendingPlate == null ? _rpsStatusText() : vehicleSelectionPaused ? '번호판 $pendingPlate, 차종 $_selectedRpsDisplayLabel 선택 완료' : '번호판 $pendingPlate 선택됨, 차량 후보 선택 후 완료',
            style: TextStyle(color: cs.surface.withOpacity(0.78), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '입력: 전체 프레임 · 자동 기준 ${_formatProbability(VehicleImageClassifier.minAutoConfidence)} / 차이 ${_formatProbability(VehicleImageClassifier.minAutoMargin)} · 후보 선택 시 모델 일시정지',
            style: TextStyle(color: cs.surface.withOpacity(0.62), fontSize: 11),
            textAlign: TextAlign.center,
          ),
          if (_rpsTopDisplayLabel != null || _rpsSecondDisplayLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              '1위 ${_rpsTopDisplayLabel ?? '-'} ${_formatProbability(_rpsTopConfidence)} · 2위 ${_rpsSecondDisplayLabel ?? '-'} ${_formatProbability(_rpsSecondConfidence)} · 차이 ${_formatProbability(_rpsConfidenceMargin)}',
              style: TextStyle(color: cs.surface.withOpacity(0.62), fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: entries.map((entry) {
                final display = VehicleImageClassifier.displayLabels[entry.key] ?? entry.key;
                final selected = _selectedRpsLabel == entry.key;
                return ActionChip(
                  label: Text('$display ${_formatProbability(entry.value)}'),
                  avatar: Icon(
                    selected ? Icons.check_circle : Icons.touch_app_outlined,
                    size: 18,
                    color: selected ? cs.onPrimary : cs.primary,
                  ),
                  labelStyle: TextStyle(
                    color: selected ? cs.onPrimary : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: selected ? cs.primary : cs.surface,
                  tooltip: selected ? '차량 선택을 해제하고 모델 추론을 재개' : '이 차량 인식 값을 선택하고 모델 추론 일시정지',
                  onPressed: () => _selectRpsResult(entry.key),
                );
              }).toList(),
            ),
          ],
          if (_lastRpsFailureReason != null) ...[
            const SizedBox(height: 8),
            Text(
              '마지막 차량 인식 실패: $_lastRpsFailureReason',
              style: TextStyle(color: cs.errorContainer, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCandidates() {
    final cs = Theme.of(context).colorScheme;
    if (!widget.plateRecognitionEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '번호판 인식이 OFF라 OCR 후보를 생성하지 않습니다.',
            style: TextStyle(color: cs.surface.withOpacity(0.70)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: _chipBottomSpacer),
        ],
      );
    }

    if (_displayChips.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '인식 후보가 안정화되면 탭하여 삽입할 수 있습니다. 한국 차량 번호판 형식만 판독합니다.',
            style: TextStyle(color: cs.surface.withOpacity(0.70)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: _chipBottomSpacer),
        ],
      );
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
            final normalizedValue = _normalizeCandidateKey(chip.value);
            final selected = _pendingPlate == normalizedValue;
            final backgroundColor = selected
                ? Colors.amber
                : switch (chip.tier) {
              _ChipTier.stable => Theme.of(context).colorScheme.primary,
              _ChipTier.tentative => Colors.teal,
              _ChipTier.weak => cs.surface,
            };
            final labelColor = selected
                ? Colors.black
                : switch (chip.tier) {
              _ChipTier.stable => cs.onPrimary,
              _ChipTier.tentative => Colors.white,
              _ChipTier.weak => cs.onSurface,
            };
            return ActionChip(
              label: Text(selected ? '${chip.label} 선택됨' : chip.label),
              avatar: selected ? const Icon(Icons.check_circle, size: 18, color: Colors.black) : null,
              labelStyle:
              TextStyle(color: labelColor, fontWeight: FontWeight.w600),
              backgroundColor: backgroundColor,
              tooltip: selected ? '선택된 번호판' : '이 번호판 값을 선택',
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
                await _finishWhenEnabledRecognitionReady(
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
