import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import 'backup_signature_painter.dart';

class SignatureResult {
  SignatureResult({
    required this.pngBytes,
    required this.signDateTime,
  });

  final Uint8List pngBytes;
  final DateTime signDateTime;
}

Future<SignatureResult?> showBackupSignatureOverlay({
  required BuildContext context,
  required String name,
  required DateTime? initialDateTime,
}) {
  return showCommonOverlayDialog<SignatureResult>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '전자서명',
    builder: (_) => BackupSignatureDialog(
      name: name,
      initialDateTime: initialDateTime,
    ),
  );
}

class BackupSignatureDialog extends StatefulWidget {
  const BackupSignatureDialog({
    super.key,
    required this.name,
    required this.initialDateTime,
  });

  final String name;
  final DateTime? initialDateTime;

  @override
  State<BackupSignatureDialog> createState() =>
      _BackupSignatureDialogState();
}

class _BackupSignatureDialogState
    extends State<BackupSignatureDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<Offset?> _points = <Offset?>[];
  DateTime? _signDateTime;
  bool _saving = false;

  static const double _strokeWidth = 2.2;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _signDateTime = widget.initialDateTime;
  }

  bool get _hasAny => _points.any((point) => point != null);

  void _clear() {
    if (_saving || !_hasAny) return;
    setState(_points.clear);
    debugPrint('[BackupSignature] clear');
  }

  void _undo() {
    if (_saving || _points.isEmpty) return;
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
    debugPrint('[BackupSignature] undo');
  }

  Future<void> _save() async {
    if (_saving || !_hasAny) return;
    setState(() {
      _saving = true;
      _signDateTime = DateTime.now();
    });
    debugPrint('[BackupSignature] save_start');
    try {
      await Future<void>.delayed(
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 16),
      );
      if (!mounted) return;
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('signature_boundary_not_found');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('signature_png_encode_failed');
      }
      final bytes = byteData.buffer.asUint8List();
      debugPrint(
        '[BackupSignature] save_complete bytes=${bytes.length}',
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        SignatureResult(
          pngBytes: bytes,
          signDateTime: _signDateTime!,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[BackupSignature] save_failure error=$error\n$stackTrace',
      );
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _fmtCompact(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.of(context);
    final name = widget.name.trim().isEmpty ? '이름 미입력' : widget.name.trim();
    final timeText =
        _signDateTime == null ? '미서명' : _fmtCompact(_signDateTime!);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 660,
        maxHeight: media.size.height * .84,
      ),
      child: Material(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.sheet),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(
                  bottom: BorderSide(color: tokens.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.draw_rounded, color: tokens.iconSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '전자서명',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  CommonIconButton(
                    icon: Icons.undo_rounded,
                    tooltip: '되돌리기',
                    onPressed: _saving || !_hasAny ? null : _undo,
                    haptic: CommonHaptic.selection,
                    size: 38,
                  ),
                  CommonIconButton(
                    icon: Icons.layers_clear_rounded,
                    tooltip: '지우기',
                    onPressed: _saving || !_hasAny ? null : _clear,
                    haptic: CommonHaptic.selection,
                    size: 38,
                  ),
                  CommonIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    haptic: CommonHaptic.selection,
                    size: 38,
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration:
                  _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              color: tokens.surfaceOverlay,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration:
                        _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: Text(
                      timeText,
                      key: ValueKey<String>(timeText),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AnimatedScale(
                  duration:
                      _reduceMotion ? Duration.zero : CommonUiMotion.component,
                  curve: CommonUiMotion.enter,
                  scale: _saving ? .992 : 1,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(CommonUiShapes.card),
                        border: Border.all(color: tokens.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.shadow,
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(CommonUiShapes.card),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _saving
                              ? null
                              : (details) => setState(
                                    () => _points.add(details.localPosition),
                                  ),
                          onPanUpdate: _saving
                              ? null
                              : (details) => setState(
                                    () => _points.add(details.localPosition),
                                  ),
                          onPanEnd: _saving
                              ? null
                              : (_) => setState(() => _points.add(null)),
                          child: CustomPaint(
                            painter: SignaturePainter(
                              points: _points,
                              strokeWidth: _strokeWidth,
                              color: tokens.textPrimary,
                              background: tokens.surfaceRaised,
                              overlayName: name,
                              overlayDateText: timeText,
                              guideColor: tokens.borderSubtle,
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
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: tokens.surface.withOpacity(.94),
                border: Border(
                  top: BorderSide(color: tokens.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CommonButton(
                      label: '취소',
                      icon: Icons.close_rounded,
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      variant: CommonButtonVariant.tertiary,
                      expand: true,
                      haptic: CommonHaptic.selection,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CommonButton(
                      label: _saving ? '저장 중' : '저장',
                      icon: _saving ? null : Icons.save_alt_rounded,
                      loading: _saving,
                      onPressed: _saving || !_hasAny ? null : _save,
                      expand: true,
                      haptic: CommonHaptic.medium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
