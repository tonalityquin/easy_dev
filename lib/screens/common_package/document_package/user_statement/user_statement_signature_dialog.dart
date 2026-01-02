
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'user_statement_styles.dart';
import 'user_statement_signature_painter.dart';

class UserStatementSignatureResult {
  UserStatementSignatureResult({
    required this.pngBytes,
    required this.signDateTime,
  });

  final Uint8List pngBytes;
  final DateTime signDateTime;
}

class UserStatementSignatureFullScreenDialog extends StatefulWidget {
  const UserStatementSignatureFullScreenDialog({
    super.key,
    required this.name,
    required this.initialDateTime,
  });

  final String name;
  final DateTime? initialDateTime;

  @override
  State<UserStatementSignatureFullScreenDialog> createState() =>
      _UserStatementSignatureFullScreenDialogState();
}

class _UserStatementSignatureFullScreenDialogState
    extends State<UserStatementSignatureFullScreenDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<Offset?> _points = <Offset?>[];
  DateTime? _signDateTime;

  static const double _strokeWidth = 2.2;

  @override
  void initState() {
    super.initState();
    _signDateTime = widget.initialDateTime;
  }

  bool get _hasAny => _points.any((p) => p != null);

  void _clear() {
    HapticFeedback.selectionClick();
    setState(() => _points.clear());
  }

  void _undo() {
    HapticFeedback.selectionClick();
    if (_points.isEmpty) return;

    int i = _points.length - 1;
    if (_points[i] == null) {
      _points.removeAt(i);
      i--;
    }
    while (i >= 0 && _points[i] != null) {
      _points.removeAt(i);
      i--;
    }
    if (i >= 0 && _points[i] == null) {
      _points.removeAt(i);
    }
    setState(() {});
  }

  Future<void> _save() async {
    try {
      HapticFeedback.lightImpact();
      setState(() {
        _signDateTime = DateTime.now();
      });
      // Repaint 적용 위해 한 프레임 대기
      await Future.delayed(const Duration(milliseconds: 16));

      final boundary =
      _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('캡처 영역을 찾을 수 없습니다.')),
        );
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PNG 변환에 실패했습니다.')),
        );
        return;
      }

      final png = byteData.buffer.asUint8List();
      Navigator.of(context).pop(
        UserStatementSignatureResult(
          pngBytes: png,
          signDateTime: _signDateTime!,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서명 저장 오류: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name.isEmpty ? '이름 미입력' : widget.name;
    final timeText =
    _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: const Text('전자서명'),
            centerTitle: true,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shape: const Border(
              bottom: BorderSide(color: Colors.black12, width: 1),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '닫기',
            ),
            actions: [
              IconButton(
                tooltip: '지우기',
                onPressed: _clear,
                icon: const Icon(Icons.layers_clear),
              ),
              IconButton(
                tooltip: '되돌리기',
                onPressed: _undo,
                icon: const Icon(Icons.undo),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              // 상단 서명자 정보 바
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: const BoxDecoration(color: Colors.white),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '서명자: $name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '서명 일시: $timeText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _signDateTime = DateTime.now()),
                      icon: const Icon(Icons.schedule),
                      label: const Text('지금'),
                    ),
                  ],
                ),
              ),
              // 서명 캔버스
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (d) =>
                                setState(() => _points.add(d.localPosition)),
                            onPanUpdate: (d) =>
                                setState(() => _points.add(d.localPosition)),
                            onPanEnd: (_) =>
                                setState(() => _points.add(null)),
                            child: CustomPaint(
                              painter: UserStatementSignaturePainter(
                                points: _points,
                                strokeWidth: _strokeWidth,
                                color: Colors.black87,
                                background: Colors.white,
                                overlayName: name,
                                overlayDateText: timeText,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // 하단 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('취소'),
                        style: UserStatementButtonStyles.outlined(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _hasAny ? _save : null,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('저장'),
                        style: UserStatementButtonStyles.primary(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
