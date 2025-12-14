// lib/screens/input_package/offline_live_ocr_page.dart
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

/// 자동 스틸샷 OCR + 하단 후보 칩 탭 삽입 지원
/// - 일정 간격 takePicture() → OCR
/// - 자동 삽입(엄격/느슨 매칭) 유지
/// - 하단 후보 칩(임의문자/숫자만 6~7자리/기하 기반) 노출, 탭 시 오타 포함 그대로 pop
/// - (옵션) 강제 자동삽입 토글: 2~3숫자 + 임의문자 + 4숫자 감지 시 즉시 pop
class LiteLiveOcrPage extends StatefulWidget {
  const LiteLiveOcrPage({super.key});

  @override
  State<LiteLiveOcrPage> createState() => _LiteLiveOcrPageState();
}

class _LiteLiveOcrPageState extends State<LiteLiveOcrPage> {
  CameraController? _controller;
  late final TextRecognizer _recognizer;

  bool _initialized = false;
  bool _autoRunning = false;
  bool _shooting = false;
  bool _torch = false;

  // 자동 루프
  int _autoIntervalMs = 900;
  int _attempt = 0;
  final int _hintEvery = 10;
  bool _completed = false;            // pop 중복 방지
  bool _allowForceInsert = false;     // (옵션) 임의문자 자동 강제삽입

  // UI
  Timer? _firstHintTimer;
  String? _lastText;
  String? _debugText;
  List<String> _candidates = const [];

  // 칩 하단 여백(시스템 제스처 바와 시각적 간격)
  static const double _chipBottomSpacer = 24;

  // 탭-투-포커스 좌표 보정용
  Size? _previewSizeLogical;

  // 가운데 한글 허용 리스트
  static const List<String> _allowedKoreanMids = [
    '가','나','다','라','마','거','너','더','러','머','버','서','어','저',
    '고','노','도','로','모','보','소','오','조','구','누','두','루','무','부','수','우','주',
    '하','허','호','배'
  ];

  // 흔한 OCR 치환
  static const Map<String, String> _charMap = {
    'O': '0', 'o': '0',
    'I': '1', 'l': '1', 'í': '1',
    'B': '8', 'S': '5',
  };

  // 가운데 글자 보정(리→러 등)
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
          back, ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _controller!.initialize();
      } catch (_) {
        _controller = CameraController(
          back, ResolutionPreset.medium,
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

        // 1) 엄격
        final strict = _extractPlateStrict(allText);
        if (strict != null) {
          _return(strict);
          return;
        }

        // 2) 느슨(보정)
        final loose = _extractPlateLoose(allText);
        if (loose != null) {
          _return(loose);
          return;
        }

        // 3) 후보(임의문자/숫자만 6~7/기하 기반) 갱신
        final set = <String>{};
        set.addAll(_extractPlateCandidatesAnyChar(allText));     // (2~3).(3~4)
        set.addAll(_extractDigitsOnlyNoMidCandidates(allText));  // 6~7 digits only
        set.addAll(_extractByGeometryCandidates(result));        // 라인 기하 기반 분리
        final list = _rankCandidates(set.toList());
        if (mounted) setState(() => _candidates = list);

        // (옵션) 임의문자 자동 강제삽입
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

  String _normalize(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    _charMap.forEach((k, v) => t = t.replaceAll(k, v));
    return t.trim();
  }

  /// 엄격: (2~3)숫자 + (허용한글 1) + (4)숫자
  String? _extractPlateStrict(String text) {
    final norm = _normalize(text);
    final allowed = _allowedKoreanMids.join();
    final strict = RegExp(r'(?<!\d)(\d{2,3})\s*([' + allowed + r'])\s*(\d{4})(?!\d)');
    final lines = norm.split('\n');

    for (final line in lines) {
      final m = strict.firstMatch(line);
      if (m != null) return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
    }
    for (int i = 0; i + 1 < lines.length; i++) {
      final m = strict.firstMatch('${lines[i]} ${lines[i + 1]}');
      if (m != null) return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
    }
    final m = strict.firstMatch(norm.replaceAll('\n', ' '));
    if (m != null) return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
    return null;
  }

  /// 느슨 + 가운데 보정 → 허용한글 재검증
  String? _extractPlateLoose(String text) {
    final norm = _normalize(text).replaceAll('\n', ' ');
    final m = RegExp(r'(\d{2,3})\s*([가-힣])\s*(\d{4})').firstMatch(norm);
    if (m == null) return null;
    var mid = m.group(2)!;
    mid = _midNormalize[mid] ?? mid;
    if (!_allowedKoreanMids.contains(mid)) return null;
    return '${m.group(1)!}$mid${m.group(3)!}';
  }

  /// (옵션 자동강제) 가운데 어떤 문자든 허용 → 하나만
  String? _extractPlateAnyChar(String text) {
    final norm = _normalize(text).replaceAll('\n', ' ');
    final m = RegExp(r'(\d{2,3})\s*(.)\s*(\d{4})').firstMatch(norm);
    if (m == null) return null;
    return '${m.group(1)!}${m.group(2)!}${m.group(3)!}';
  }

  /// 칩용 후보: (2~3).(3~4) (임의문자 허용, 여러 개)
  List<String> _extractPlateCandidatesAnyChar(String text) {
    final norm = _normalize(text).replaceAll('\n', ' ');
    final reg = RegExp(r'(\d{2,3})\s*(.)\s*(\d{3,4})');
    final set = <String>{};
    for (final m in reg.allMatches(norm)) {
      final f = m.group(1)!;
      final mid = m.group(2)!;
      final b = m.group(3)!;
      set.add('$f$mid$b');

      if (RegExp(r'^[가-힣]$').hasMatch(mid)) {
        final fixed = _midNormalize[mid];
        if (fixed != null) set.add('$f$fixed$b');
      }
    }
    return set.toList();
  }

  /// 숫자만 6/7자리(가운데 누락) → digits-only 후보 반환
  List<String> _extractDigitsOnlyNoMidCandidates(String text) {
    final t = _normalize(text).replaceAll('\n', ' ');
    final list = <String>[];
    for (final m in RegExp(r'(?<!\d)(\d{6,7})(?!\d)').allMatches(t)) {
      final s = m.group(1)!; // 6 or 7 digits
      list.add(s);
    }
    return list;
  }

  /// ML Kit 기하(간격/높이) 기반으로 오른쪽 4자리 묶음을 찾아 앞/뒤 분리 → digits-only 후보
  List<String> _extractByGeometryCandidates(RecognizedText result) {
    final outs = <String>{};

    for (final block in result.blocks) {
      for (final line in block.lines) {
        final els = line.elements;
        if (els.length < 6) continue;

        // 숫자 엘리먼트만 추출
        final digits = <(TextElement el, Rect box)>[];
        for (final el in els) {
          if (RegExp(r'^\d$').hasMatch(el.text)) {
            digits.add((el, el.boundingBox));
          }
        }
        if (digits.length < 6) continue;

        digits.sort((a,b) => a.$2.center.dx.compareTo(b.$2.center.dx));

        // 뒤 4자리 탐색
        for (int i = digits.length - 4; i >= 0; i--) {
          final win = digits.sublist(i, i+4);
          final heights = win.map((e) => e.$2.height).toList();
          final gaps = [
            win[1].$2.left - win[0].$2.right,
            win[2].$2.left - win[1].$2.right,
            win[3].$2.left - win[2].$2.right,
          ];
          final hMax = heights.reduce((a,b)=>a>b?a:b);
          final hMin = heights.reduce((a,b)=>a<b?a:b);
          final heightOk = (hMax / (hMin == 0 ? 1 : hMin)) < 1.25;
          final gapOk = gaps.every((g) => g > -2 && g < hMax * 0.8);
          if (!(heightOk && gapOk)) continue;

          final back = win.map((e) => e.$1.text).join(); // 4 digits
          final left = digits.sublist(0, i);
          if (left.length == 2 || left.length == 3) {
            final front = left.map((e) => e.$1.text).join();
            outs.add('$front$back'); // digits-only (2+4 or 3+4)
          }
        }
      }
    }
    return outs.toList();
  }

  /// 후보 정렬: 완전형(2~3.4)에 가까울수록, 다음으로 digits-only(6/7) 우선
  List<String> _rankCandidates(List<String> list) {
    int score(String s) {
      // 완전형 (2~3)(임의)(4)
      if (RegExp(r'^\d{2,3}.\d{4}$').hasMatch(s)) return 0;
      // digits-only 7 → 3+4, 6 → 2+4
      if (RegExp(r'^\d{7}$').hasMatch(s)) return 1;
      if (RegExp(r'^\d{6}$').hasMatch(s)) return 2;
      // 그 외
      return 9;
    }
    final uniq = {...list}.toList();
    uniq.sort((a,b) => score(a).compareTo(score(b)));
    // 너무 많으면 12개까지만
    return uniq.length > 12 ? uniq.sublist(0,12) : uniq;
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
        automaticallyImplyLeading: false,                  // 🔹 뒤로가기 화살표 제거
        backgroundColor: Colors.black,                     // 🔹 검정 배경
        foregroundColor: Colors.white,                     // 🔹 아이콘/텍스트 흰색
        systemOverlayStyle: SystemUiOverlayStyle.light,    // 🔹 상태바 아이콘 밝게
        elevation: 0,
        actions: [
          // 강제 자동삽입 토글(임의문자 허용)
          IconButton(
            tooltip: _allowForceInsert ? '강제삽입 ON' : '강제삽입 OFF',
            onPressed: () => setState(() => _allowForceInsert = !_allowForceInsert),
            icon: Icon(_allowForceInsert ? Icons.fact_check : Icons.fact_check_outlined),
          ),
          // 토치
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
          // 자동 on/off
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

          // 디버그/최근 텍스트
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

          // 후보 칩 (SafeArea로 하단 시스템 UI와 겹침 방지 + 추가 여백)
          SafeArea(
            top: false, left: false, right: false, bottom: true,
            minimum: const EdgeInsets.only(bottom: 8), // 조금 더 띄움
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
      crossAxisAlignment: CrossAxisAlignment.center, // 칩 묶음도 가운데 정렬
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,     // 가로 가운데
          runAlignment: WrapAlignment.center,  // 줄 바꿈 행도 가운데
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
