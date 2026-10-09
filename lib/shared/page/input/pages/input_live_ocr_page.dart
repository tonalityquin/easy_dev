import 'package:flutter/material.dart';

import '../../live_ocr/pages/live_ocr_page.dart';
import '../controllers/input_live_ocr_controller.dart';

class InputLiveOcrPage extends StatefulWidget {
  const InputLiveOcrPage({
    super.key,
    required this.sessionId,
    this.onExitPreparing,
  });

  final String sessionId;
  final LiveOcrExitPreparing? onExitPreparing;

  @override
  State<InputLiveOcrPage> createState() => _InputLiveOcrPageState();
}

class _InputLiveOcrPageState extends State<InputLiveOcrPage> {
  late final InputLiveOcrController _controller;

  @override
  void initState() {
    super.initState();
    _controller = InputLiveOcrController();
  }

  @override
  Widget build(BuildContext context) {
    return LiveOcrPage(
      sessionId: widget.sessionId,
      coordinator: _controller,
      onExitPreparing: widget.onExitPreparing,
    );
  }
}
