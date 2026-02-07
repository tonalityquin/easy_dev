import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <- systemOverlayStyle 적용을 위해 추가
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../utils/snackbar_helper.dart';

/// ✅ Triple 파일 내부 전용 mid 정책(외부로 export되지 않음)
class _PlateMidPolicy {
  static const List<String> allowedKoreanMids = [
    '가','나','다','라','마','거','너','더','러','머','버','서','어','저',
    '고','노','도','로','모','보','소','오','조','구','누','두','루','무','부','수','우','주',
    '하','허','호','배'
  ];

  static const Map<String, String> midNormalize = {
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

  static String normalizeMid(String mid) => midNormalize[mid] ?? mid;

  static bool isAllowedMid(String mid) => allowedKoreanMids.contains(normalizeMid(mid));

  static String allowedMidCharClass() => allowedKoreanMids.join();
}

/// 자동 스틸샷 OCR + 하단 후보 칩 탭 삽입 지원
/// - 일정 간격 takePicture() → OCR
/// - 자동 삽입(엄격/느슨 매칭) 유지
/// - 하단 후보 칩(임의문자/숫자만 6~7자리/기하 기반) 노출, 탭 시 오타 포함 그대로 pop
/// - (옵션) 강제 자동삽입 토글: 2~3숫자 + 임의문자 + 4숫자 감지 시 즉시 pop
class TripleLiveOcrPage extends StatefulWidget {
  const TripleLiveOcrPage({super.key});

  @override
  State<TripleLiveOcrPage> createState() => _TripleLiveOcrPageState();
}

class _TripleLiveOcrPageState extends State<TripleLiveOcrPage> {
  CameraController? _controller;
  late final TextRecognizer _recognizer;

  bool _initialized = false;
  bool _autoRunning = false;
  bool _shooting = false;
  bool _torch = false;

  int _autoIntervalMs = 900;
  int _attempt = 0;
  final int _hintEvery = 10;
  bool _completed = false;
  bool _allowForceInsert = false;

  Timer? _firstHintTimer;
  String? _lastText;
  String? _debugText;
  List<String> _candidates = const [];

  static const double _chipBottomSpacer = 24;

  Size? _previewSizeLogical;

  static const Map<String, String> _charMap = {
    'O': '0', 'o': '0', '○': '0',
    'I': '1', 'l': '1', 'í': '1',
    'B': '8', 'S': '5',

    '０':'0','１':'1','２':'2','３':'3','４':'4',
    '５':'5','６':'6','７':'7','８':'8','９':'9',
  };

  static const String _plateSepPattern = r'[\s\.\-·•_]*';

  @override
  void initState() {
    super.initState();
    _recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    _initCamera();
  }

  @override
  void dispose() {
    _autoRunning = false;
    _firstHintTimer?.cancel();
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        showFailedSnackbar(context, '카메라 권한이 필요합니다.');
        Navigator.pop(context);
        return;
      }
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      try {
        _controller = CameraController(
          back,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _controller!.initialize();
      } catch (_) {
        _controller = CameraController(
          back,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _controller!.initialize();
      }
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
        await _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}

      _meterTo(const Offset(0.5, 0.5));

      _initialized = true;
      if (mounted) setState(() {});

      _firstHintTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted || _completed) return;
        showSelectedSnackbar(context, '정면·근접·밝게 촬영하면 인식률이 좋아집니다.');
      });

      _startAuto();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '카메라 초기화 중 오류가 발생했습니다.');
      Navigator.pop(context);
    }
  }

  void _meterTo(Offset p) async {
    try {
      await _controller?.setExposurePoint(p);
      await _controller?.setFocusPoint(p);
    } catch (_) {}
  }

  void _startAuto() {
    if (!_initialized) return;
    _autoRunning = true;
    _shooting = false;
    _attempt = 0;
    _completed = false;
    _candidates = const [];
    _lastText = null;
    _debugText = null;
    _autoLoop();
  }

  void _stopAuto() => _autoRunning = false;

  Future<void> _autoLoop() async {
    while (mounted && _autoRunning && !_completed) {
      if (_shooting) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      _shooting = true;
      XFile? xfile;
      try {
        xfile = await _controller?.takePicture();
        if (xfile == null) continue;

        final input = InputImage.fromFilePath(xfile.path);
        final result = await _recognizer.processImage(input);
        final allText = result.text;

        _lastText = allText.replaceAll('\n', ' ');
        if (_lastText!.length > 120) _lastText = '${_lastText!.substring(0, 120)}…';

        final strict = _extractPlateStrict(allText);
        if (strict != null) {
          _return(strict);
          return;
        }

        final loose = _extractPlateLoose(allText);
        if (loose != null) {
          _return(loose);
          return;
        }

        final set = <String>{};
        set.addAll(_extractPlateCandidatesAnyChar(allText));
        set.addAll(_extractDigitsOnlyNoMidCandidates(allText));
        set.addAll(_extractByGeometryCandidates(result));
        final list = _rankCandidates(set.toList());
        if (mounted) setState(() => _candidates = list);

        if (_allowForceInsert) {
          final force = _extractPlateAnyChar(allText);
          if (force != null) {
            _return(force);
            return;
          }
        }

        _attempt++;
        if (_attempt % _hintEvery == 0) {
          showSelectedSnackbar(context, '정면·근접·밝게 촬영해 보세요.');
        }
        if (kDebugMode && mounted) {
          setState(() => _debugText = 'attempt:$_attempt');
        }
      } catch (e) {
        if (kDebugMode && mounted) setState(() => _debugText = 'autoLoop err: $e');
      } finally {
        try {
          if (xfile != null) {
            final f = File(xfile.path);
            if (f.existsSync()) f.deleteSync();
          }
        } catch (_) {}
        _shooting = false;
      }

      await Future.delayed(Duration(milliseconds: _autoIntervalMs.clamp(200, 3000)));
    }
  }

  // ─────────────── 인식률 최우선 정규화 ───────────────

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

  // ─────────────── 추출 로직 ───────────────

  String? _extractPlateStrict(String text) {
    final normLines = _normalizePreserveNewlines(text);
    final allowed = _PlateMidPolicy.allowedMidCharClass();

    final strict = RegExp(
      r'(?<!\d)(\d{2,3})' + _plateSepPattern + r'([' + allowed + r'])' + _plateSepPattern + r'(\d{4})(?!\d)',
    );

    final lines = normLines.split('\n');

    for (final line in lines) {
      final m = strict.firstMatch(line);
      if (m != null) return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
    }
    for (int i = 0; i + 1 < lines.length; i++) {
      final m = strict.firstMatch('${lines[i]} ${lines[i + 1]}');
      if (m != null) return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
    }

    final flat = normLines.replaceAll('\n', ' ');
    final m = strict.firstMatch(flat);
    if (m != null) return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';

    return null;
  }

  String? _extractPlateLoose(String text) {
    final norm = _normalizeFlat(text);

    final reg = RegExp(
      r'(?<!\d)(\d{2,3})' + _plateSepPattern + r'([가-힣])' + _plateSepPattern + r'(\d{4})(?!\d)',
    );

    for (final m in reg.allMatches(norm)) {
      final rawMid = m.group(2)!;
      final mid = _PlateMidPolicy.normalizeMid(rawMid);
      if (!_PlateMidPolicy.isAllowedMid(mid)) continue;
      return '${m.group(1)!}$mid${m.group(3)!}';
    }
    return null;
  }

  String? _extractPlateAnyChar(String text) {
    final norm = _normalizeFlat(text);
    final m = RegExp(r'(\d{2,3})\s*(.)\s*(\d{4})').firstMatch(norm);
    if (m == null) return null;
    return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
  }

  List<String> _extractPlateCandidatesAnyChar(String text) {
    final norm = _normalizeFlat(text);
    final reg = RegExp(r'(\d{2,3})\s*(.)\s*(\d{3,4})');
    final set = <String>{};

    for (final m in reg.allMatches(norm)) {
      final f = m.group(1)!;
      final mid = m.group(2)!;
      final b = m.group(3)!;
      set.add('$f$mid$b');

      if (RegExp(r'^[가-힣]$').hasMatch(mid)) {
        final fixed = _PlateMidPolicy.midNormalize[mid];
        if (fixed != null) set.add('$f$fixed$b');
      }
    }
    return set.toList();
  }

  List<String> _extractDigitsOnlyNoMidCandidates(String text) {
    final t = _normalizeFlat(text);
    final list = <String>[];
    for (final m in RegExp(r'(?<!\d)(\d{6,7})(?!\d)').allMatches(t)) {
      list.add(m.group(1)!);
    }
    return list;
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

  List<String> _rankCandidates(List<String> list) {
    int score(String s) {
      if (RegExp(r'^\d{2,3}.\d{4}$').hasMatch(s)) return 0;
      if (RegExp(r'^\d{7}$').hasMatch(s)) return 1;
      if (RegExp(r'^\d{6}$').hasMatch(s)) return 2;
      return 9;
    }

    final uniq = {...list}.toList();
    uniq.sort((a, b) => score(a).compareTo(score(b)));
    return uniq.length > 12 ? uniq.sublist(0, 12) : uniq;
  }

  void _return(String plate) {
    if (_completed) return;
    _completed = true;
    _stopAuto();
    if (!mounted) return;
    Navigator.pop(context, plate);
  }

  // ─────────────── UI ───────────────
  @override
  Widget build(BuildContext context) {
    final cam = _controller;
    final preview = (!(_initialized && cam != null && cam.value.isInitialized))
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
      builder: (ctx, constraints) {
        _previewSizeLogical = Size(constraints.maxWidth, constraints.maxHeight);
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _allowForceInsert ? '강제삽입 ON' : '강제삽입 OFF',
            onPressed: () => setState(() => _allowForceInsert = !_allowForceInsert),
            icon: Icon(_allowForceInsert ? Icons.fact_check : Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: _torch ? '토치 끄기' : '토치 켜기',
            onPressed: () async {
              try {
                _torch = !_torch;
                await _controller?.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
                setState(() {});
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
                _startAuto();
              }
              setState(() {});
            },
            icon: Icon(_autoRunning ? Icons.pause_circle_filled : Icons.play_circle_fill),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: preview),
          if (_debugText != null || _lastText != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_debugText != null)
                    Text(_debugText!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (_lastText != null && _lastText!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '최근: $_lastText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          SafeArea(
            top: false, left: false, right: false, bottom: true,
            minimum: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: Colors.black,
              child: _buildCandidates(),
            ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildCandidates() {
    if (_candidates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Text(
            '인식 후보가 나타나면 탭하여 그대로 삽입할 수 있습니다.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: _chipBottomSpacer),
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
          children: _candidates.map((cand) {
            return ActionChip(
              label: Text(cand),
              labelStyle: const TextStyle(color: Colors.white),
              backgroundColor: Colors.blueGrey.shade700,
              tooltip: '이 값(오타/누락 포함)으로 삽입',
              onPressed: () => _return(cand),
            );
          }).toList(),
        ),
        const SizedBox(height: _chipBottomSpacer),
      ],
    );
  }
}
