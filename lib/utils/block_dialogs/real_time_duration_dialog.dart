import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ✅ 5초 동안 유지되는 취소 가능 blocking dialog
/// - [duration] 동안 카운트다운 후 자동으로 true 반환
/// - '취소' 버튼 누르면 false 반환
/// - ✅ [body]를 주면 body를 우선 렌더링
/// - ✅ body가 없으면 [plateNumber/location/occurredAt/elapsedText] 프리뷰 카드 렌더링
Future<bool> showRealTimeDurationBlockingDialog(
    BuildContext context, {
      required String message,
      Duration duration = const Duration(seconds: 3),
      Widget? body,

      /// ✅ 프리뷰(번호판/구역/시각/경과)용
      String? plateNumber,
      String? location,
      DateTime? occurredAt,
      String? elapsedText,

      /// ✅ 타이틀 커스텀
      String title = '원본 조회 전 확인',
    }) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return _CancelableBlockingDialog(
        title: title,
        message: message,
        duration: duration,
        body: body,
        plateNumber: plateNumber,
        location: location,
        occurredAt: occurredAt,
        elapsedText: elapsedText,
      );
    },
  );
  return result ?? false;
}

/// ✅ “번호판 상세” 다이얼로그 스타일(센터 + AlertDialog)과 동일 톤
class _CancelableBlockingDialog extends StatefulWidget {
  const _CancelableBlockingDialog({
    required this.title,
    required this.message,
    required this.duration,
    this.body,
    this.plateNumber,
    this.location,
    this.occurredAt,
    this.elapsedText,
  });

  final String title;
  final String message;
  final Duration duration;

  final Widget? body;

  final String? plateNumber;
  final String? location;
  final DateTime? occurredAt;
  final String? elapsedText;

  @override
  State<_CancelableBlockingDialog> createState() => _CancelableBlockingDialogState();
}

class _CancelableBlockingDialogState extends State<_CancelableBlockingDialog> {
  Timer? _timer;

  late final int _totalSeconds;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();

    _totalSeconds = widget.duration.inSeconds <= 0 ? 1 : widget.duration.inSeconds;
    _remainingSeconds = _totalSeconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        _remainingSeconds -= 1;
        if (_remainingSeconds < 0) _remainingSeconds = 0;
      });

      if (_remainingSeconds <= 0) {
        t.cancel();
        if (mounted) {
          Navigator.of(context).pop<bool>(true);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleCancel() {
    HapticFeedback.selectionClick();
    _timer?.cancel();
    Navigator.of(context).pop<bool>(false);
  }

  double get _progressValue {
    final total = _totalSeconds <= 0 ? 1 : _totalSeconds;
    final elapsed = (total - _remainingSeconds).clamp(0, total);
    return elapsed / total;
  }

  String _fmtDate(DateTime? v) {
    if (v == null) return '-';
    final d = v.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final mo = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$y-$mo-$da $h:$mi';
  }

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) return '$hours시간 $minutes분';
    if (minutes > 0) return '$minutes분 $seconds초';
    return '$seconds초';
  }

  String _resolvedElapsedText() {
    final raw = (widget.elapsedText ?? '').trim();
    if (raw.isNotEmpty) return raw;

    final t = widget.occurredAt;
    if (t == null) return '-';

    final diff = DateTime.now().difference(t);
    final safe = diff.isNegative ? Duration.zero : diff;
    return _formatElapsed(safe);
  }

  bool get _hasPreviewFields {
    final p = (widget.plateNumber ?? '').trim();
    final l = (widget.location ?? '').trim();
    return p.isNotEmpty || l.isNotEmpty || widget.occurredAt != null || (widget.elapsedText ?? '').trim().isNotEmpty;
  }

  TextStyle _titleStyle(ColorScheme cs, TextTheme text) => text.titleMedium!.copyWith(
    fontWeight: FontWeight.w900,
    color: cs.onSurface,
  );

  TextStyle _subStyle(ColorScheme cs, TextTheme text) => text.bodySmall!.copyWith(
    color: cs.onSurfaceVariant,
    height: 1.35,
  );

  TextStyle _labelStyle(ColorScheme cs, TextTheme text) => text.labelMedium!.copyWith(
    fontWeight: FontWeight.w900,
    color: cs.onSurfaceVariant,
  );

  TextStyle _valueStyle(ColorScheme cs, TextTheme text) => text.bodyMedium!.copyWith(
    fontWeight: FontWeight.w900,
    color: cs.onSurface,
    height: 1.2,
  );

  TextStyle _monoValueStyle(ColorScheme cs, TextTheme text) => _valueStyle(cs, text).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    fontFamilyFallback: const ['monospace'],
  );

  Widget _infoRow({
    required ColorScheme cs,
    required TextTheme text,
    required String label,
    required Widget value,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(label, style: _labelStyle(cs, text)),
              ),
              const SizedBox(width: 8),
              Expanded(child: value),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: cs.outlineVariant.withOpacity(.6),
          ),
      ],
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final plate = (widget.plateNumber ?? '').trim();
    final loc = (widget.location ?? '').trim();
    final timeText = _fmtDate(widget.occurredAt);
    final elapsedText = _resolvedElapsedText();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _infoRow(
            cs: cs,
            text: text,
            label: '번호판',
            value: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  plate.isEmpty ? '-' : plate,
                  style: _valueStyle(cs, text),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
          _infoRow(
            cs: cs,
            text: text,
            label: '주차 구역',
            value: Text(
              loc.isEmpty ? '-' : loc,
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _infoRow(
            cs: cs,
            text: text,
            label: '시각',
            value: Text(
              timeText,
              style: _monoValueStyle(cs, text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _infoRow(
            cs: cs,
            text: text,
            label: '경과',
            showDivider: false,
            value: Text(
              elapsedText,
              style: _monoValueStyle(cs, text).copyWith(color: cs.tertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final hasBody = widget.body != null;
    final hasMessage = widget.message.trim().isNotEmpty;

    if (hasBody) return widget.body!;

    if (_hasPreviewFields) {
      return _buildPreviewCard(context);
    }

    if (hasMessage) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
        ),
        child: Text(
          widget.message,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(
            color: cs.onSurface,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Colors.transparent,
          child: AlertDialog(
            backgroundColor: cs.surface,
            elevation: 8,
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ───────────────────────── Header ─────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: _titleStyle(cs, text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: '취소',
                        onPressed: _handleCancel,
                        icon: Icon(Icons.close, color: cs.onSurface),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$_remainingSeconds초 후 자동 진행됩니다. (취소 시 원본 조회를 실행하지 않습니다.)',
                      style: _subStyle(cs, text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ───────────────────────── Progress Card ─────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    value: _progressValue.clamp(0.0, 1.0),
                                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                                    backgroundColor: cs.primary.withOpacity(.12),
                                  ),
                                ),
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: cs.primary.withOpacity(.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.schedule, color: cs.primary, size: 18),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '잠시만 기다려 주세요…',
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            value: _progressValue.clamp(0.0, 1.0),
                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                            backgroundColor: cs.primary.withOpacity(.12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ───────────────────────── Main Content ─────────────────────────
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: _buildContent(context),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ───────────────────────── Countdown Chip ─────────────────────────
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            '자동 진행까지 ${_remainingSeconds}s',
                            style: text.labelMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ───────────────────────── Actions ─────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleCancel,
                      icon: const Icon(Icons.block),
                      label: const Text(
                        '취소',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(color: cs.outlineVariant.withOpacity(.9)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
