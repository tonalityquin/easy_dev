import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

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
    _recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
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
      _lastSavedLearningKey = null;
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

        final input = InputImage.fromFilePath(captured.path);
        final result = await _recognizer.processImage(input);
        final allText = result.text;
        _attempt++;

        _lastText = allText.replaceAll('\n', ' ');
        if ((_lastText ?? '').length > 180) {
          _lastText = '${_lastText!.substring(0, 180)}…';
        }
        _appendLog('attempt=$_attempt ocrText=${_lastText ?? ''}');

        final direct = _extractStrictKoreanPlate(allText);
        if (direct != null) {
          _usedLearningMidLast = false;
          _usedLearningRankLast = false;
          _appendLog('직접 확정 $direct');
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
          await _finishAndPop(
            plate: loose,
            exitType: LiveOcrExitType.autoLoose,
          );
          return;
        }

        final rawSet = <String>{};
        rawSet.addAll(
            _extractModernCandidatesAnyChar(allText, onUseLearningMid: () {
          usedLearningMidThis = true;
        }));
        rawSet.addAll(_extractLegacyRegionCandidates(allText));
        rawSet.addAll(_extractDigitsOnlyNoMidCandidates(allText));
        rawSet.addAll(_extractByGeometryCandidates(result));
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

    showPromptOverlayDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = PromptUiTheme.of(dialogContext);
        final textTheme = Theme.of(dialogContext).textTheme;
        Widget row(String label, String value) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
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

        return PromptDialogFrame(
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
                        borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
                PromptButton(
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
    final logText = _sessionLogs.join('\n');
    showPromptOverlayDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = PromptUiTheme.of(dialogContext);
        return PromptDialogFrame(
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
                        borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
                      borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
                      child: PromptButton(
                        label: '복사',
                        icon: Icons.copy_rounded,
                        variant: PromptButtonVariant.secondary,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: logText));
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PromptButton(
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
    return PromptUiScope(
      child: Builder(builder: _buildPromptOcrPage),
    );
  }

  Widget _buildPromptOcrPage(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
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
              tooltip: '인식 로그',
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
            PromptAnimatedReveal(
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
                  child: _buildCandidates(),
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
    final tokens = PromptUiTheme.of(context);
    final foreground = tokens.isDark ? tokens.textPrimary : tokens.onAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised.withOpacity(tokens.isDark ? .72 : .16),
        border: Border.all(color: foreground.withOpacity(.28)),
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
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
    final tokens = PromptUiTheme.of(context);
    final cameraForeground =
        tokens.isDark ? tokens.textPrimary : tokens.onAccent;

    if (_displayChips.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '인식 후보가 안정화되면 탭하여 삽입할 수 있습니다. 한국 차량 번호판 형식만 판독합니다.',
            style: TextStyle(color: cameraForeground.withOpacity(0.72)),
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
