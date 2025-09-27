// lib/screens/input_package/live_ocr_page.dart
import 'dart:async';
import 'dart:io'; // ⬅️ 임시 파일 삭제를 위해 추가

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/snackbar_helper.dart';

/// 자동 스틸샷 OCR 버전 (ROI 관련 로직 제거)
/// - startImageStream 미사용
/// - 초기화 후 일정 간격으로 자동 촬영 → OCR → 번호판 감지 시 즉시 pop(plate)
/// - AF/AE 중앙 맞춤, 탭-투-포커스 지원, 토치 토글
class LiveOcrPage extends StatefulWidget {
  const LiveOcrPage({super.key});

  @override
  State<LiveOcrPage> createState() => _LiveOcrPageState();
}

class _LiveOcrPageState extends State<LiveOcrPage> {
  CameraController? _controller;
  late final TextRecognizer _recognizer =
  TextRecognizer(script: TextRecognitionScript.korean);

  bool _initializing = true;
  bool _autoRunning = false;
  bool _shooting = false; // 촬영 중 중복 방지
  bool _torch = false;

  // 자동 촬영 간격/로직
  static const int _autoIntervalMs = 900;
  int _attempts = 0;
  static const int _hintEvery = 10; // n회 연속 실패 시 힌트 노출

  String? _debugText; // blocks/plate 등 디버그 표시
  String? _lastText; // 최근 인식 텍스트 일부
  Timer? _firstHintTimer;

  // 미터링(탭-투-포커스)용
  Size? _previewSizeLogical;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _stopAuto();
    _firstHintTimer?.cancel();
    _controller?.dispose();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      if (mounted) {
        showFailedSnackbar(context, '카메라 권한이 필요합니다. 설정에서 허용해 주세요.');
        Navigator.pop(context);
      }
      return;
    }

    try {
      final cams = await availableCameras();
      if (!mounted) return;

      final back = cams.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      // 고해상도 시도 → 실패 시 medium
      try {
        _controller = CameraController(
          back,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _controller!.initialize();
      } catch (_) {
        if (!mounted) return;
        _controller = CameraController(
          back,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _controller!.initialize();
      }
      if (!mounted) return;

      // 중앙 AF/AE
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _meterTo(const Offset(0.5, 0.5));
      if (!mounted) return;

      // 6초 후 첫 힌트
      _firstHintTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        showSelectedSnackbar(
            context, '번호판을 화면 가로 70~90%로 채우고 1초 정지해 주세요.');
      });

      // 자동 촬영 루프 시작
      _startAuto();
    } catch (e) {
      if (mounted) {
        showFailedSnackbar(context, '카메라 초기화 실패: $e');
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  Future<void> _meterTo(Offset ndc) async {
    try {
      await _controller?.setFocusPoint(ndc);
      await _controller?.setExposurePoint(ndc);
    } catch (_) {
      // 단말/버전에 따라 미지원일 수 있음 → 무시
    }
  }

  void _startAuto() {
    if (_autoRunning || _controller == null) return;
    _autoRunning = true;
    _attempts = 0;
    _autoLoop();
  }

  void _stopAuto() {
    _autoRunning = false;
  }

  Future<void> _autoLoop() async {
    while (mounted && _autoRunning) {
      if (_shooting) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }

      _shooting = true;
      XFile? shot; // ⬅️ 촬영 파일을 finally에서 정리하기 위해 스코프 바깥에 선언
      try {
        shot = await _controller!.takePicture(); // 미리보기 유지됨

        final input = InputImage.fromFilePath(shot.path);
        final result = await _recognizer.processImage(input);

        final allText = result.text;
        _lastText = allText.isEmpty
            ? ''
            : (allText.length > 80 ? '${allText.substring(0, 80)}…' : allText);

        final plate = _extractPlate(allText);

        if (kDebugMode) {
          if (mounted) {
            setState(() => _debugText = 'attempt:${_attempts + 1} plate:$plate');
          }
        }

        if (plate != null) {
          _stopAuto();
          _firstHintTimer?.cancel();
          if (!mounted) return;
          Navigator.pop(context, plate); // ⬅️ 성공 시 즉시 데이터 삽입
          return;
        } else {
          _attempts++;
          if (_attempts % _hintEvery == 0 && mounted) {
            showSelectedSnackbar(
              context,
              '각도/거리/밝기 조정해 보세요. (정면·근접·밝게)',
            );
          }
        }
      } catch (e) {
        if (kDebugMode && mounted) {
          setState(() => _debugText = 'shoot_err:$e');
        }
      } finally {
        _shooting = false;
        // ⬇️ 임시 촬영 파일 안전 삭제 (누수 방지)
        if (shot != null) {
          try {
            await File(shot.path).delete();
          } catch (_) {
            // 파일이 이미 정리됐거나 접근 불가인 경우 무시
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: _autoIntervalMs));
    }
  }

  // ───────── 번호판 파서 ─────────
  String _normalizeChars(String s) => s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('O', '0')
      .replaceAll('o', '0')
      .replaceAll('I', '1')
      .replaceAll('l', '1')
      .replaceAll('B', '8')
      .replaceAll('S', '5');

  final List<RegExp> _patterns = [
    // 123가4567 / 12가3456
    RegExp(r'\b\d{3}\s*[가-힣]\s*\d{4}\b'),
    RegExp(r'\b\d{2}\s*[가-힣]\s*\d{4}\b'),
  ];

  String? _extractPlate(String text) {
    var s = _normalizeChars(text);
    final lines = s.split(RegExp(r'[\r\n]+'));
    for (final rx in _patterns) {
      final m0 = rx.firstMatch(s);
      if (m0 != null) return m0.group(0)!.replaceAll(' ', '');
      for (int i = 0; i + 1 < lines.length; i++) {
        final joined =
        (lines[i] + lines[i + 1]).replaceAll(' ', '');
        final m1 = rx.firstMatch(joined);
        if (m1 != null) return m1.group(0)!.replaceAll(' ', '');
      }
    }
    return null;
  }

  // 미리보기 탭 → AF/AE 재조정
  Future<void> _onTapPreview(TapDownDetails d) async {
    if (_previewSizeLogical == null) return;
    final s = _previewSizeLogical!;
    final ndc = Offset(
      (d.localPosition.dx / s.width).clamp(0.0, 1.0),
      (d.localPosition.dy / s.height).clamp(0.0, 1.0),
    );
    await _meterTo(ndc);
    if (mounted) showSelectedSnackbar(context, '초점/노출 맞춤');
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('카메라 사용 불가', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title:
        const Text('자동 번호판 인식', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // 자동 촬영 일시정지/재개
          IconButton(
            tooltip: _autoRunning ? '자동촬영 일시정지' : '자동촬영 재개',
            onPressed: () {
              if (_autoRunning) {
                _stopAuto();
                if (mounted) {
                  showSelectedSnackbar(context, '자동촬영: 일시정지');
                }
              } else {
                _startAuto();
                if (mounted) {
                  showSelectedSnackbar(context, '자동촬영: 재개');
                }
              }
              if (mounted) setState(() {});
            },
            icon: Icon(
                _autoRunning ? Icons.pause_circle : Icons.play_circle),
          ),
          // 토치 토글
          IconButton(
            tooltip: _torch ? '플래시 끄기' : '플래시 켜기',
            onPressed: () async {
              _torch = !_torch;
              try {
                await _controller?.setFlashMode(
                    _torch ? FlashMode.torch : FlashMode.off);
                if (mounted) {
                  showSelectedSnackbar(
                      context, _torch ? '플래시 ON' : '플래시 OFF');
                }
              } catch (e) {
                if (mounted) {
                  showFailedSnackbar(context, '플래시 제어 실패: $e');
                }
              }
              if (mounted) setState(() {});
            },
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: () {
              if (mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          _previewSizeLogical = Size(c.maxWidth, c.maxHeight);
          return Stack(
            children: [
              // 탭-투-포커스 지원
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _onTapPreview,
                  child: CameraPreview(_controller!),
                ),
              ),
              // 디버그 텍스트
              if (_debugText != null || _lastText != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 80,
                  child: Column(
                    children: [
                      if (_debugText != null)
                        Text(
                          _debugText!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      if (_lastText != null && _lastText!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _lastText!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      // ⛔️ 버튼 없음: 자동 촬영/인식만 수행
      floatingActionButton: null,
    );
  }
}
