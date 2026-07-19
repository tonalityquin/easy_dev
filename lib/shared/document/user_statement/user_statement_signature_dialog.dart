import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

import 'user_statement_signature_painter.dart';

class UserStatementSignatureResult {
  UserStatementSignatureResult({required this.pngBytes, required this.signDateTime});

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
  State<UserStatementSignatureFullScreenDialog> createState() => _UserStatementSignatureFullScreenDialogState();
}

class _UserStatementSignatureFullScreenDialogState extends State<UserStatementSignatureFullScreenDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<Offset?> _points = <Offset?>[];
  DateTime? _signDateTime;

  static const double _strokeWidth = 2.2;

  @override
  void initState() {
    super.initState();
    _signDateTime = widget.initialDateTime;
  }

  bool get _hasAny => _points.any((point) => point != null);

  void _clear() {
    if (!_hasAny) return;
    setState(_points.clear);
  }

  void _undo() {
    if (_points.isEmpty) return;
    int index = _points.length - 1;
    if (_points[index] == null) {
      _points.removeAt(index);
      index--;
    }
    while (index >= 0 && _points[index] != null) {
      _points.removeAt(index);
      index--;
    }
    if (index >= 0 && _points[index] == null) {
      _points.removeAt(index);
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (!_hasAny) return;
    try {
      setState(() => _signDateTime = DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      final boundary =
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      Navigator.of(context).pop(
        UserStatementSignatureResult(
          pngBytes: byteData.buffer.asUint8List(),
          signDateTime: _signDateTime!,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final name = widget.name.trim().isEmpty ? '이름 미입력' : widget.name.trim();
    final timeText =
        _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

    return Material(
      color: tokens.canvas,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: tokens.canvas,
          appBar: AppBar(
            title: const Text('전자서명'),
            centerTitle: true,
            leadingWidth: 58,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: PromptIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                haptic: PromptHaptic.selection,
                size: 40,
              ),
            ),
            actions: [
              PromptIconButton(
                icon: Icons.layers_clear_rounded,
                tooltip: '지우기',
                onPressed: _hasAny ? _clear : null,
                haptic: PromptHaptic.selection,
                size: 40,
              ),
              const SizedBox(width: 6),
              PromptIconButton(
                icon: Icons.undo_rounded,
                tooltip: '되돌리기',
                onPressed: _hasAny ? _undo : null,
                haptic: PromptHaptic.selection,
                size: 40,
              ),
              const SizedBox(width: 8),
            ],
            shape: Border(
              bottom: BorderSide(color: tokens.borderSubtle),
            ),
          ),
          body: Column(
            children: [
              PromptAnimatedReveal(
                offset: const Offset(0, .02),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    border: Border(
                      bottom: BorderSide(color: tokens.borderSubtle),
                    ),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MetadataChip(
                        icon: Icons.person_outline_rounded,
                        label: '서명자',
                        value: name,
                      ),
                      _MetadataChip(
                        icon: Icons.access_time_rounded,
                        label: '서명 일시',
                        value: timeText,
                      ),
                      PromptButton(
                        label: '현재 시각',
                        icon: Icons.schedule_rounded,
                        onPressed: () =>
                            setState(() => _signDateTime = DateTime.now()),
                        variant: PromptButtonVariant.tertiary,
                        haptic: PromptHaptic.selection,
                        minHeight: 42,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: PromptAnimatedReveal(
                    delay: const Duration(milliseconds: 60),
                    offset: const Offset(0, .025),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.card),
                          border: Border.all(color: tokens.borderSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: tokens.shadow,
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.card),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (details) => setState(
                              () => _points.add(details.localPosition),
                            ),
                            onPanUpdate: (details) => setState(
                              () => _points.add(details.localPosition),
                            ),
                            onPanEnd: (_) => setState(() => _points.add(null)),
                            child: CustomPaint(
                              painter: UserStatementSignaturePainter(
                                points: _points,
                                strokeWidth: _strokeWidth,
                                color: tokens.textPrimary,
                                background: tokens.surfaceRaised,
                                overlayName: name,
                                overlayDateText: timeText,
                                guideColor: tokens.borderSubtle,
                                hintColor: tokens.textSecondary,
                                overlayTextColor: tokens.textSecondary,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: PromptButton(
                        label: '취소',
                        icon: Icons.cancel_outlined,
                        onPressed: () => Navigator.of(context).pop(),
                        variant: PromptButtonVariant.tertiary,
                        expand: true,
                        haptic: PromptHaptic.selection,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PromptButton(
                        label: '저장',
                        icon: Icons.save_alt_rounded,
                        onPressed: _hasAny ? _save : null,
                        expand: true,
                        haptic: PromptHaptic.medium,
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

  String _fmtCompact(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tokens.iconSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$label: $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
