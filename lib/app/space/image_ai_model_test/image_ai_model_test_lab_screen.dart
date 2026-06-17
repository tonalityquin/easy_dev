import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../di/routes.dart';
import 'pages/plate_image_detect_page.dart';

class ImageAiModelTestLabScreen extends StatefulWidget {
  const ImageAiModelTestLabScreen({
    super.key,
    this.autoStartScanner = true,
  });

  final bool autoStartScanner;

  @override
  State<ImageAiModelTestLabScreen> createState() => _ImageAiModelTestLabScreenState();
}

class _ImageAiModelTestLabScreenState extends State<ImageAiModelTestLabScreen> {
  final TextEditingController _frontController = TextEditingController();
  final TextEditingController _midController = TextEditingController();
  final TextEditingController _backController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  String _selectedModel = '번호판 OCR + 차량 전면부 TFLite 통합 모델';
  bool _openingScanner = false;
  bool _autoStarted = false;
  bool _plateRecognitionEnabled = true;
  bool _imageRecognitionEnabled = true;
  bool _requiresMidCompletion = false;
  String? _rawPlateText;
  String? _statusText;
  String? _lastSessionId;
  LiveOcrSessionResult? _lastResult;
  List<String> _processLogs = const [];

  static const List<String> _models = [
    '번호판 OCR + 차량 전면부 TFLite 통합 모델',
    '번호판 OCR + 차량 전면부 확률 검증 모델',
    '번호판 OCR 보정 강화 + 차량 전면부 통합 모델',
  ];

  static const Map<String, String> _rpsDisplayLabels = {
    'genesis_g80': '제네시스 G80',
    'kia_carnival': '기아 카니발',
  };

  static const List<String> _allowedKoreanMids = [
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
    '배',
  ];

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

  static const Map<String, String> _midNormalize = {
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

  static const List<String> _legacyRegions = [
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
    '제주',
  ];

  @override
  void initState() {
    super.initState();
    _appendProcessLog('이미지 AI 모델 테스트 화면 진입');
    if (widget.autoStartScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _autoStarted) {
          return;
        }
        _autoStarted = true;
        _openPlateImageDetectPage();
      });
    }
  }

  @override
  void dispose() {
    _frontController.dispose();
    _midController.dispose();
    _backController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _goBackToSelector(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
  }

  void _appendProcessLog(String message) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final next = List<String>.from(_processLogs, growable: true)..add('[$ts] $message');
    if (next.length > 400) {
      next.removeRange(0, next.length - 400);
    }
    if (mounted) {
      setState(() {
        _processLogs = List<String>.unmodifiable(next);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollLogToBottom());
    } else {
      _processLogs = List<String>.unmodifiable(next);
    }
  }

  void _scrollLogToBottom() {
    if (!_logScrollController.hasClients) {
      return;
    }
    _logScrollController.animateTo(
      _logScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  String _newSessionId() {
    final now = DateTime.now();
    return 'space-ocr-${now.microsecondsSinceEpoch}';
  }

  bool get _hasEnabledRecognizer => _plateRecognitionEnabled || _imageRecognitionEnabled;

  String _recognitionConditionLabel({bool? plate, bool? image}) {
    final plateOn = plate ?? _plateRecognitionEnabled;
    final imageOn = image ?? _imageRecognitionEnabled;
    if (plateOn && imageOn) return 'plate+vehicle';
    if (plateOn) return 'plate';
    if (imageOn) return 'vehicle';
    return 'none';
  }

  String _enabledSuccessStatus(LiveOcrSessionResult result) {
    if (result.plateRecognitionEnabled && result.imageRecognitionEnabled) {
      return result.enabledRecognitionSuccess ? '통합 인식 성공' : '통합 조건 미충족';
    }
    if (result.plateRecognitionEnabled) {
      return result.plateSuccess ? '번호판 인식 성공' : '번호판 인식 실패';
    }
    if (result.imageRecognitionEnabled) {
      return result.rpsSuccess ? '이미지 인식 성공' : '이미지 인식 실패';
    }
    return '인식 기능 미선택';
  }

  Future<void> _openPlateImageDetectPage() async {
    if (_openingScanner) {
      return;
    }
    if (!_hasEnabledRecognizer) {
      setState(() => _statusText = '인식 기능을 선택하세요');
      _appendProcessLog('인식 실행 차단 condition=none');
      return;
    }

    final sessionId = _newSessionId();

    setState(() {
      _openingScanner = true;
      _lastSessionId = sessionId;
      _statusText = '인식 진행 중';
    });

    _appendProcessLog('PlateImageDetectPage 열기 sessionId=$sessionId model=$_selectedModel condition=${_recognitionConditionLabel()}');

    final result = await Navigator.of(context).push<LiveOcrSessionResult>(
      MaterialPageRoute(
        builder: (_) => PlateImageDetectPage(
          sessionId: sessionId,
          plateRecognitionEnabled: _plateRecognitionEnabled,
          imageRecognitionEnabled: _imageRecognitionEnabled,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _openingScanner = false;
      _lastResult = result;
    });

    if (result == null) {
      setState(() {
        _statusText = '인식 실패';
      });
      _appendProcessLog('PlateImageDetectPage 결과 없음');
      return;
    }

    _appendProcessLog('PlateImageDetectPage 닫힘 exitType=${_ocrExitTypeLabel(result.exitType)} attempt=${result.attemptCount}');
    _appendProcessLog('후보값=${result.candidateValues.isEmpty ? '-' : result.candidateValues.join(', ')}');
    _appendProcessLog('마지막 OCR 텍스트=${result.lastOcrText ?? '-'}');
    _appendProcessLog(
      '차량 인식 결과=${result.rpsDisplayLabel ?? '-'} confidence=${_formatProbability(result.rpsConfidence)} '
      'mode=${_rpsSelectionMode(result)} autoAccepted=${result.rpsAutoAccepted} '
      'top1=${result.rpsTopDisplayLabel ?? '-'} ${_formatProbability(result.rpsTopConfidence)} '
      'top2=${result.rpsSecondDisplayLabel ?? '-'} ${_formatProbability(result.rpsSecondConfidence)} '
      'margin=${_formatProbability(result.rpsConfidenceMargin)} '
      'failure=${result.rpsFailureReason ?? '-'} instability=${result.rpsInstabilityReason ?? '-'}',
    );
    _appendProcessLog('선택 기능 성공=${result.enabledRecognitionSuccess} plateEnabled=${result.plateRecognitionEnabled} imageEnabled=${result.imageRecognitionEnabled} plateStatus=${result.plateExecutionStatus} imageStatus=${result.imageExecutionStatus}');

    _applyOcrResult(result);
  }

  void _applyOcrResult(LiveOcrSessionResult result) {
    if (!result.plateRecognitionEnabled && result.imageRecognitionEnabled) {
      setState(() {
        _statusText = _enabledSuccessStatus(result);
        _rawPlateText = null;
        _requiresMidCompletion = false;
      });
      _appendProcessLog('번호판 인식 미실행 imageStatus=${result.imageExecutionStatus} vehicle=${result.rpsDisplayLabel ?? '-'}');
      return;
    }

    if (result.plate != null && result.plate!.isNotEmpty) {
      final applied = _applyPlateWithFallback(result.plate!, sessionId: result.sessionId);
      final status = _enabledSuccessStatus(result);
      setState(() {
        _statusText = applied ? status : '번호판 원문 표시, 선택 기능 조건 미충족';
        _rawPlateText = result.plate;
      });
      _appendProcessLog(applied ? '번호판 데이터 삽입 완료 plate=${result.plate}' : '번호판 원문만 표시 plate=${result.plate}');
      if (result.enabledRecognitionSuccess) {
        _appendProcessLog('선택 기능 인식 성공 plate=${result.plate ?? '-'} vehicle=${result.rpsDisplayLabel ?? '-'} condition=${_recognitionConditionLabel(plate: result.plateRecognitionEnabled, image: result.imageRecognitionEnabled)}');
      } else {
        _appendProcessLog('선택 기능 조건 미충족 plateStatus=${result.plateExecutionStatus} imageStatus=${result.imageExecutionStatus} vehicleFailure=${result.rpsFailureReason ?? '-'}');
      }
      return;
    }

    if (result.requiresMidCompletion && result.weakFront != null && result.weakBack != null) {
      _applyToFields(
        front: result.weakFront!,
        mid: '',
        back: result.weakBack!,
        promptMid: true,
        sessionId: result.sessionId,
      );
      setState(() {
        _statusText = result.imageRecognitionEnabled && result.rpsSuccess ? '부분 번호판, 이미지 성공' : '부분 번호판 인식';
        _rawPlateText = result.weakObservedValue;
      });
      _appendProcessLog('부분 번호판 삽입 완료 front=${result.weakFront} back=${result.weakBack} suggestions=${result.weakMidSuggestions.join(', ')}');
      _appendProcessLog('선택 기능 조건 미충족 plateStatus=${result.plateExecutionStatus} imageStatus=${result.imageExecutionStatus}');
      return;
    }

    final failedByUser = result.exitType == LiveOcrExitType.userAborted;
    setState(() {
      _statusText = failedByUser ? '사용자 종료' : _enabledSuccessStatus(result);
      _rawPlateText = null;
      _requiresMidCompletion = false;
    });
    _appendProcessLog('번호판 삽입 없음 reason=${result.lastFailureReason ?? _ocrExitTypeLabel(result.exitType)}');
    _appendProcessLog('선택 기능 조건 결과 plateStatus=${result.plateExecutionStatus} imageStatus=${result.imageExecutionStatus}');
  }

  String _normalize(String value) {
    var text = value.trim().replaceAll(RegExp(r'\s+'), '');
    text = text.replaceAll(RegExp(r'[\-\.·•_]'), '');
    _charMap.forEach((key, mapped) {
      text = text.replaceAll(key, mapped);
    });
    return text;
  }

  RegExp get _rxStrict {
    final allowed = _allowedKoreanMids.join();
    return RegExp(r'^(\d{2,3})([' + allowed + r'])(\d{4})$');
  }

  RegExp get _rxLegacy {
    final regions = _legacyRegions.join('|');
    return RegExp('^($regions)(\\d{1,2})([가-힣])(\\d{4})\$');
  }

  final RegExp _rxAnyMid = RegExp(r'^(\d{2,3})(.)(\d{4})$');
  final RegExp _rxOnly7 = RegExp(r'^\d{7}$');
  final RegExp _rxOnly6 = RegExp(r'^\d{6}$');

  bool _applyPlateWithFallback(String plate, {String? sessionId}) {
    final raw = _normalize(plate);

    final strict = _rxStrict.firstMatch(raw);
    if (strict != null) {
      final front = strict.group(1)!;
      var mid = strict.group(2)!;
      final back = strict.group(3)!;
      mid = _midNormalize[mid] ?? mid;
      _applyToFields(front: front, mid: mid, back: back, sessionId: sessionId);
      return true;
    }

    final legacy = _rxLegacy.firstMatch(raw);
    if (legacy != null) {
      final front = '${legacy.group(1)!}${legacy.group(2)!}';
      var mid = legacy.group(3)!;
      final back = legacy.group(4)!;
      mid = _midNormalize[mid] ?? mid;
      _applyToFields(front: front, mid: mid, back: back, sessionId: sessionId);
      return true;
    }

    final anyMid = _rxAnyMid.firstMatch(raw);
    if (anyMid != null) {
      final front = anyMid.group(1)!;
      var mid = anyMid.group(2)!;
      final back = anyMid.group(3)!;
      if (RegExp(r'^[가-힣]$').hasMatch(mid)) {
        mid = _midNormalize[mid] ?? mid;
      }
      _applyToFields(front: front, mid: mid, back: back, sessionId: sessionId);
      return true;
    }

    if (_rxOnly7.hasMatch(raw)) {
      _applyToFields(
        front: raw.substring(0, 3),
        mid: '',
        back: raw.substring(3, 7),
        promptMid: true,
        sessionId: sessionId,
      );
      return true;
    }

    if (_rxOnly6.hasMatch(raw)) {
      _applyToFields(
        front: raw.substring(0, 2),
        mid: '',
        back: raw.substring(2, 6),
        promptMid: true,
        sessionId: sessionId,
      );
      return true;
    }

    return false;
  }

  void _applyToFields({
    required String front,
    required String mid,
    required String back,
    bool promptMid = false,
    String? sessionId,
  }) {
    setState(() {
      _frontController.text = front;
      _midController.text = mid;
      _backController.text = back;
      _lastSessionId = sessionId ?? _lastSessionId;
      _requiresMidCompletion = promptMid || mid.isEmpty;
    });
  }

  void _clearResult() {
    setState(() {
      _frontController.clear();
      _midController.clear();
      _backController.clear();
      _lastResult = null;
      _statusText = null;
      _lastSessionId = null;
      _rawPlateText = null;
      _requiresMidCompletion = false;
      _processLogs = const [];
    });
  }

  String _ocrExitTypeLabel(LiveOcrExitType type) {
    switch (type) {
      case LiveOcrExitType.autoDirect:
        return '자동 확정(strict)';
      case LiveOcrExitType.autoLoose:
        return '자동 확정(loose)';
      case LiveOcrExitType.autoForceInsert:
        return '강제 삽입';
      case LiveOcrExitType.candidateChipSelected:
        return '후보 칩 선택';
      case LiveOcrExitType.imageAutoAccepted:
        return '이미지 자동 확정';
      case LiveOcrExitType.imageUserSelected:
        return '이미지 사용자 선택';
      case LiveOcrExitType.userAborted:
        return '사용자 중도 종료';
      case LiveOcrExitType.permissionDenied:
        return '권한 거부';
      case LiveOcrExitType.cameraInitFailed:
        return '카메라 초기화 실패';
    }
  }

  String _fullPlatePreview() {
    final front = _frontController.text.trim();
    final mid = _midController.text.trim();
    final back = _backController.text.trim();
    if (front.isEmpty && mid.isEmpty && back.isEmpty) {
      return '-';
    }
    if (mid.isEmpty) {
      return '$front?$back';
    }
    return '$front$mid$back';
  }

  String _buildClipboardText() {
    final result = _lastResult;
    final values = <String>[
      'status: ${_statusText ?? '-'}',
      'model: $_selectedModel',
      'sessionId: ${_lastSessionId ?? '-'}',
      'plateRecognitionEnabled: $_plateRecognitionEnabled',
      'imageRecognitionEnabled: $_imageRecognitionEnabled',
      'condition: ${_recognitionConditionLabel()}',
      'front: ${_frontController.text.isEmpty ? '-' : _frontController.text}',
      'mid: ${_midController.text.isEmpty ? '-' : _midController.text}',
      'back: ${_backController.text.isEmpty ? '-' : _backController.text}',
      'fullPlatePreview: ${_fullPlatePreview()}',
      'requiresMidCompletion: $_requiresMidCompletion',
      'rawPlateText: ${_rawPlateText ?? '-'}',
    ];

    if (result != null) {
      values.addAll([
        'exitType: ${_ocrExitTypeLabel(result.exitType)}',
        'resultPlateRecognitionEnabled: ${result.plateRecognitionEnabled}',
        'resultImageRecognitionEnabled: ${result.imageRecognitionEnabled}',
        'plateExecutionStatus: ${result.plateExecutionStatus}',
        'imageExecutionStatus: ${result.imageExecutionStatus}',
        'enabledRecognitionSuccess: ${result.enabledRecognitionSuccess}',
        'selectedPlate: ${result.plate ?? '-'}',
        'selectedChipLabel: ${result.selectedChipLabel ?? '-'}',
        'attemptCount: ${result.attemptCount}',
        'lastOcrText: ${result.lastOcrText ?? '-'}',
        'lastFailureReason: ${result.lastFailureReason ?? '-'}',
        'candidateValues: ${result.candidateValues.isEmpty ? '-' : result.candidateValues.join(', ')}',
        'usedLearningMid: ${result.usedLearningMid}',
        'usedLearningRank: ${result.usedLearningRank}',
        'weakFront: ${result.weakFront ?? '-'}',
        'weakBack: ${result.weakBack ?? '-'}',
        'weakObservedValue: ${result.weakObservedValue ?? '-'}',
        'weakMidSuggestions: ${result.weakMidSuggestions.isEmpty ? '-' : result.weakMidSuggestions.join(', ')}',
        'combinedSuccess: ${result.combinedSuccess}',
        'rpsLabel: ${result.rpsLabel ?? '-'}',
        'rpsDisplayLabel: ${result.rpsDisplayLabel ?? '-'}',
        'rpsConfidence: ${_formatProbability(result.rpsConfidence)}',
        'rpsProbabilityMode: ${result.rpsProbabilityMode}',
        'rpsUserSelected: ${result.rpsUserSelected}',
        'rpsAutoAccepted: ${result.rpsAutoAccepted}',
        'rpsSelectionMode: ${_rpsSelectionMode(result)}',
        'rpsFailureReason: ${result.rpsFailureReason ?? '-'}',
        'rpsInstabilityReason: ${result.rpsInstabilityReason ?? '-'}',
        'rpsTopLabel: ${result.rpsTopLabel ?? '-'}',
        'rpsTopDisplayLabel: ${result.rpsTopDisplayLabel ?? '-'}',
        'rpsTopConfidence: ${_formatProbability(result.rpsTopConfidence)}',
        'rpsSecondLabel: ${result.rpsSecondLabel ?? '-'}',
        'rpsSecondDisplayLabel: ${result.rpsSecondDisplayLabel ?? '-'}',
        'rpsSecondConfidence: ${_formatProbability(result.rpsSecondConfidence)}',
        'rpsConfidenceMargin: ${_formatProbability(result.rpsConfidenceMargin)}',
        'rpsMinAutoConfidence: ${_formatProbability(result.rpsMinAutoConfidence)}',
        'rpsMinAutoMargin: ${_formatProbability(result.rpsMinAutoMargin)}',
        'rpsProbabilities: ${_formatRpsProbabilities(result.rpsProbabilities)}',
      ]);
    }

    values.addAll([
      '',
      '----- PROCESS LOG -----',
      _processLogs.isEmpty ? '로그가 없습니다.' : _processLogs.join('\n'),
      '',
      '----- OCR SESSION LOG -----',
      result == null || result.logText.isEmpty ? '로그가 없습니다.' : result.logText,
      '',
      '----- 차량 인식 MODEL LOG -----',
      result == null || result.rpsLogText.isEmpty ? '로그가 없습니다.' : result.rpsLogText,
    ]);

    return values.join('\n');
  }

  String _formatProbability(double? value) {
    if (value == null) {
      return '-';
    }
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  String _rpsSelectionMode(LiveOcrSessionResult result) {
    if (result.rpsUserSelected) {
      return '사용자 선택';
    }
    if (result.rpsAutoAccepted) {
      return '자동 판정';
    }
    if (result.rpsLabel != null && result.rpsLabel!.isNotEmpty) {
      return '결과 확정';
    }
    return '자동 보류';
  }

  String _formatRpsProbabilities(Map<String, double> probabilities) {
    if (probabilities.isEmpty) {
      return '-';
    }
    final ordered = ['scissors', 'rock', 'paper'];
    final values = <String>[];
    for (final key in ordered) {
      final value = probabilities[key];
      if (value == null) {
        continue;
      }
      values.add('${_rpsDisplayLabels[key] ?? key}: ${_formatProbability(value)}');
    }
    for (final entry in probabilities.entries) {
      if (ordered.contains(entry.key)) {
        continue;
      }
      values.add('${_rpsDisplayLabels[entry.key] ?? entry.key}: ${_formatProbability(entry.value)}');
    }
    return values.join(', ');
  }

  List<MapEntry<String, double>> _orderedRpsProbabilities(Map<String, double> probabilities) {
    final entries = probabilities.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _buildClipboardText()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('인식 결과와 로그를 복사했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = _lastResult;
    final hasResult = result != null;
    final hasPlateData = _frontController.text.isNotEmpty || _midController.text.isNotEmpty || _backController.text.isNotEmpty;
    final statusText = _statusText ?? (_openingScanner ? '인식 진행 중' : '대기 중');
    final hasEnabledRecognizer = _hasEnabledRecognizer;
    final statusIcon = switch (statusText) {
      '통합 인식 성공' => Icons.check_circle_rounded,
      '번호판 인식 성공' => Icons.check_circle_rounded,
      '이미지 인식 성공' => Icons.check_circle_rounded,
      '번호판 성공, 차량 인식 실패' => Icons.warning_amber_rounded,
      '번호판 표시 확인 필요' => Icons.warning_amber_rounded,
      '부분 번호판, 차량 인식 성공' => Icons.warning_amber_rounded,
      '부분 인식, 통합 조건 미충족' => Icons.warning_amber_rounded,
      '차량 인식 성공, 번호판 실패' => Icons.error_outline_rounded,
      '인식 실패' => Icons.error_outline_rounded,
      '이미지 인식 실패' => Icons.error_outline_rounded,
      '번호판 인식 실패' => Icons.error_outline_rounded,
      '인식 기능을 선택하세요' => Icons.tune_rounded,
      '인식 기능 미선택' => Icons.tune_rounded,
      '사용자 종료' => Icons.cancel_outlined,
      _ => Icons.hourglass_top_rounded,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('이미지 AI 모델 테스트'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Selector로 이동',
            onPressed: () => _goBackToSelector(context),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '이미지 AI 모델 테스트',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '번호판 OCR과 가위바위보 TFLite 이미지 모델을 함께 실행하고, 둘 다 성공한 경우만 통합 성공으로 기록합니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: '인식 실행',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedModel,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '테스트 모델',
                    ),
                    items: _models
                        .map(
                          (model) => DropdownMenuItem<String>(
                            value: model,
                            child: Text(model),
                          ),
                        )
                        .toList(),
                    onChanged: _openingScanner
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedModel = value;
                            });
                            _appendProcessLog('테스트 모델 변경 model=$value');
                          },
                  ),
                  const SizedBox(height: 12),
                  _RecognitionSwitchTile(
                    title: '번호판 인식',
                    subtitle: '한국 차량 번호판 OCR과 후보 보정을 실행합니다.',
                    value: _plateRecognitionEnabled,
                    enabled: !_openingScanner,
                    onChanged: (value) {
                      setState(() {
                        _plateRecognitionEnabled = value;
                        if (!_plateRecognitionEnabled && !_imageRecognitionEnabled) {
                          _statusText = '인식 기능을 선택하세요';
                        }
                      });
                      _appendProcessLog('번호판 인식 ${value ? 'ON' : 'OFF'} condition=${_recognitionConditionLabel()}');
                    },
                  ),
                  const SizedBox(height: 8),
                  _RecognitionSwitchTile(
                    title: '이미지 인식',
                    subtitle: '가위바위보 TFLite 이미지 모델을 실행합니다.',
                    value: _imageRecognitionEnabled,
                    enabled: !_openingScanner,
                    onChanged: (value) {
                      setState(() {
                        _imageRecognitionEnabled = value;
                        if (!_plateRecognitionEnabled && !_imageRecognitionEnabled) {
                          _statusText = '인식 기능을 선택하세요';
                        }
                      });
                      _appendProcessLog('이미지 인식 ${value ? 'ON' : 'OFF'} condition=${_recognitionConditionLabel()}');
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(statusIcon, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusText,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: _openingScanner
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.image_search_rounded),
                          label: Text(_openingScanner ? '인식 화면 실행 중' : '선택 기능 인식 열기'),
                          onPressed: _openingScanner || !hasEnabledRecognizer ? null : _openPlateImageDetectPage,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: '결과와 로그 복사',
                        onPressed: hasResult || _processLogs.isNotEmpty ? _copyLogs : null,
                        icon: const Icon(Icons.copy_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: '초기화',
                        onPressed: _openingScanner || (!hasResult && !hasPlateData && _processLogs.isEmpty) ? null : _clearResult,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '번호판 데이터 출력',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result != null && !result.plateRecognitionEnabled) ...[
                    _WarningBox(text: '번호판 인식이 OFF라 실행하지 않았습니다.'),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _frontController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '앞자리',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _midController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '중간 글자',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _backController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '뒤 4자리',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '조합 결과: ${_fullPlatePreview()}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_rawPlateText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '원본 인식값: $_rawPlateText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_requiresMidCompletion) ...[
                    const SizedBox(height: 10),
                    _WarningBox(
                      text: '중간 글자 보정이 필요합니다. PlateImageDetectPage가 반환한 앞자리와 뒤 4자리는 출력했고, 중간 글자는 비워두었습니다.',
                    ),
                    if (result != null && result.weakMidSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: result.weakMidSuggestions
                            .map(
                              (mid) => InputChip(
                                label: Text(mid),
                                onPressed: () {
                                  setState(() {
                                    _midController.text = mid;
                                    _requiresMidCompletion = false;
                                    _statusText = '부분 인식 보정 완료';
                                  });
                                  _appendProcessLog('중간 글자 수동 보정 mid=$mid fullPlate=${_fullPlatePreview()}');
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '가위바위보 이미지 모델 출력',
              child: result == null
                  ? Text(
                      '아직 완료된 차량 인식 모델 결과가 없습니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : !result.imageRecognitionEnabled
                      ? Text(
                          '이미지 인식이 OFF라 실행하지 않았습니다.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SummaryRow(label: '차량 인식 결과', value: result.rpsDisplayLabel ?? '-'),
                        _SummaryRow(label: '원본 라벨', value: result.rpsLabel ?? '-'),
                        _SummaryRow(label: '신뢰도', value: _formatProbability(result.rpsConfidence)),
                        _SummaryRow(label: '선택 방식', value: _rpsSelectionMode(result)),
                        _SummaryRow(label: '확률 모드', value: result.rpsProbabilityMode ? 'ON' : 'OFF'),
                        _SummaryRow(label: '자동 판정 통과', value: '${result.rpsAutoAccepted}'),
                        _SummaryRow(label: '1위 후보', value: '${result.rpsTopDisplayLabel ?? '-'} ${_formatProbability(result.rpsTopConfidence)}'),
                        _SummaryRow(label: '2위 후보', value: '${result.rpsSecondDisplayLabel ?? '-'} ${_formatProbability(result.rpsSecondConfidence)}'),
                        _SummaryRow(label: '1위-2위 차이', value: _formatProbability(result.rpsConfidenceMargin)),
                        _SummaryRow(label: '자동 기준', value: '${_formatProbability(result.rpsMinAutoConfidence)} / 차이 ${_formatProbability(result.rpsMinAutoMargin)}'),
                        _SummaryRow(label: '차량 인식 실패 사유', value: result.rpsFailureReason ?? '-'),
                        _SummaryRow(label: '차량 인식 불안정 사유', value: result.rpsInstabilityReason ?? '-'),
                        const SizedBox(height: 8),
                        if (result.rpsProbabilities.isEmpty)
                          Text(
                            '확률 데이터가 없습니다.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        else
                          Column(
                            children: _orderedRpsProbabilities(result.rpsProbabilities)
                                .map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 64,
                                          child: Text(
                                            _rpsDisplayLabels[entry.key] ?? entry.key,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: LinearProgressIndicator(
                                            value: entry.value.clamp(0.0, 1.0).toDouble(),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 56,
                                          child: Text(
                                            _formatProbability(entry.value),
                                            textAlign: TextAlign.right,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '세션 요약',
              child: result == null
                  ? Text(
                      '아직 완료된 인식 세션이 없습니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SummaryRow(label: '세션 ID', value: result.sessionId),
                        _SummaryRow(label: '번호판 인식', value: result.plateRecognitionEnabled ? 'ON' : 'OFF'),
                        _SummaryRow(label: '이미지 인식', value: result.imageRecognitionEnabled ? 'ON' : 'OFF'),
                        _SummaryRow(label: '번호판 상태', value: result.plateExecutionStatus),
                        _SummaryRow(label: '이미지 상태', value: result.imageExecutionStatus),
                        _SummaryRow(label: '선택 기능 성공', value: '${result.enabledRecognitionSuccess}'),
                        _SummaryRow(label: '종료 유형', value: _ocrExitTypeLabel(result.exitType)),
                        _SummaryRow(label: '최종 번호판', value: result.plate ?? '-'),
                        _SummaryRow(label: '선택 칩', value: result.selectedChipLabel ?? '-'),
                        _SummaryRow(label: '시도 횟수', value: '${result.attemptCount}'),
                        _SummaryRow(label: '마지막 실패 사유', value: result.lastFailureReason ?? '-'),
                        _SummaryRow(label: '후보값', value: result.candidateValues.isEmpty ? '-' : result.candidateValues.join(', ')),
                        _SummaryRow(label: '학습 mid 적용', value: '${result.usedLearningMid}'),
                        _SummaryRow(label: '학습 rank 적용', value: '${result.usedLearningRank}'),
                        _SummaryRow(label: '보정 필요', value: '${result.requiresMidCompletion}'),
                        _SummaryRow(label: 'mid 제안', value: result.weakMidSuggestions.isEmpty ? '-' : result.weakMidSuggestions.join(', ')),
                        _SummaryRow(label: '최근 OCR', value: result.lastOcrText ?? '-'),
                        _SummaryRow(label: '통합 성공', value: '${result.combinedSuccess}'),
                        _SummaryRow(label: '번호판 성공', value: '${result.plateSuccess}'),
                        _SummaryRow(label: '차량 인식 성공', value: '${result.rpsSuccess}'),
                        _SummaryRow(label: '차량 인식 결과', value: result.rpsDisplayLabel ?? '-'),
                        _SummaryRow(label: '차량 인식 확률', value: _formatRpsProbabilities(result.rpsProbabilities)),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: '인식 과정 로그',
              child: SizedBox(
                height: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Scrollbar(
                    controller: _logScrollController,
                    child: SingleChildScrollView(
                      controller: _logScrollController,
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _buildVisibleLogText(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          fontFamily: 'monospace',
                        ),
                      ),
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

  String _buildVisibleLogText() {
    final result = _lastResult;
    final values = <String>[
      '----- PROCESS LOG -----',
      _processLogs.isEmpty ? '로그가 없습니다.' : _processLogs.join('\n'),
      '',
      '----- OCR SESSION LOG -----',
      result == null || result.logText.isEmpty ? '로그가 없습니다.' : result.logText,
      '',
      '----- 차량 인식 MODEL LOG -----',
      result == null || result.rpsLogText.isEmpty ? '로그가 없습니다.' : result.rpsLogText,
    ];
    return values.join('\n');
  }
}

class _RecognitionSwitchTile extends StatelessWidget {
  const _RecognitionSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.tertiary.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onTertiaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
