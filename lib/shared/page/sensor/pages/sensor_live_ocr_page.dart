import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../live_ocr/pages/live_ocr_page.dart';
import '../controllers/sensor_live_ocr_controller.dart';

class SensorLiveOcrPage extends StatefulWidget {
  const SensorLiveOcrPage({
    super.key,
    required this.sessionId,
    this.onExitPreparing,
    this.allowIncompleteResult = false,
    this.initialFrameBytes,
  });

  final String sessionId;
  final LiveOcrExitPreparing? onExitPreparing;
  final bool allowIncompleteResult;
  final Uint8List? initialFrameBytes;

  @override
  State<SensorLiveOcrPage> createState() => _SensorLiveOcrPageState();
}

class _SensorLiveOcrPageState extends State<SensorLiveOcrPage> {
  late final SensorLiveOcrController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SensorLiveOcrController(
      allowIncompleteResult: widget.allowIncompleteResult,
      initialFrameBytes: widget.initialFrameBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: Transform.scale(
              scale: .985 + (.015 * t),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
      child: LiveOcrPage(
        sessionId: widget.sessionId,
        coordinator: _controller,
        onExitPreparing: widget.onExitPreparing,
      ),
    );
  }
}
