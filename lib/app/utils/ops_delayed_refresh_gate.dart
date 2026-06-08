import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../features/selector/application/dev_auth.dart';

class OpsDelayedRefreshGate {
  OpsDelayedRefreshGate._();

  static final Random _random = Random();
  static const int _minSeconds = 165;
  static const int _maxSeconds = 195;
  static int? _lastSeconds;

  static Future<bool> waitIfNeeded({
    required BuildContext context,
    String title = '운영 데이터 동기화',
    String message = '운영 데이터를 새로고침하기 전 서버 요청을 준비하고 있습니다.',
  }) async {
    final devMode = await DevAuth.isDeveloperLoggedIn();
    if (devMode) return true;

    final duration = _nextDuration();
    if (!context.mounted) return false;

    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OpsDelayedRefreshDialog(
        title: title,
        message: message,
        duration: duration,
      ),
    );

    return completed ?? false;
  }

  static Duration _nextDuration() {
    final range = _maxSeconds - _minSeconds + 1;
    var seconds = _minSeconds + _random.nextInt(range);

    if (_lastSeconds != null && range > 1) {
      while (seconds == _lastSeconds) {
        seconds = _minSeconds + _random.nextInt(range);
      }
    }

    _lastSeconds = seconds;
    return Duration(seconds: seconds);
  }
}

class _OpsDelayedRefreshDialog extends StatefulWidget {
  const _OpsDelayedRefreshDialog({
    required this.title,
    required this.message,
    required this.duration,
  });

  final String title;
  final String message;
  final Duration duration;

  @override
  State<_OpsDelayedRefreshDialog> createState() => _OpsDelayedRefreshDialogState();
}

class _OpsDelayedRefreshDialogState extends State<_OpsDelayedRefreshDialog> {
  Timer? _timer;
  late final DateTime _startedAt;
  late final List<String> _steps;
  double _progress = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _steps = _pickSteps();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<String> _pickSteps() {
    const candidates = <String>[
      '지역 운영 정보 확인 중',
      '주차 구역 데이터 준비 중',
      '정산 타입 목록 준비 중',
      '월정기 사용 여부 확인 중',
      '로컬 캐시 정리 중',
      '동기화 요청 대기열 점검 중',
      '마지막 적용 상태 확인 중',
    ];

    final shuffled = List<String>.of(candidates)..shuffle(OpsDelayedRefreshGate._random);
    return shuffled.take(5).toList(growable: false);
  }

  void _tick() {
    if (!mounted || _closing) return;

    final elapsedMs = DateTime.now().difference(_startedAt).inMilliseconds;
    final totalMs = widget.duration.inMilliseconds;
    final raw = totalMs <= 0 ? 1.0 : (elapsedMs / totalMs).clamp(0.0, 1.0).toDouble();
    final eased = raw >= 1.0 ? 1.0 : 0.98 * (1 - pow(1 - raw, 1.7)).toDouble();

    setState(() => _progress = eased.clamp(0.0, 1.0).toDouble());

    if (raw >= 1.0) {
      _close(true);
    }
  }

  void _close(bool completed) {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    Navigator.of(context, rootNavigator: true).pop<bool>(completed);
  }

  String get _stepLabel {
    final index = (_progress * _steps.length).floor().clamp(0, _steps.length - 1);
    return _steps[index];
  }

  String get _remainingLabel {
    final elapsed = DateTime.now().difference(_startedAt);
    final remaining = widget.duration - elapsed;
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final minutes = safe.inMinutes;
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final percent = (_progress * 100).clamp(0, 100).round();

    return PopScope(
      canPop: false,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        title: Row(
          children: [
            Icon(Icons.sync_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.message,
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _stepLabel,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: text.bodySmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
                ),
                child: Text(
                  '예상 대기 시간 약 $_remainingLabel · 취소하면 새로고침이 실행되지 않습니다.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _close(false),
            icon: const Icon(Icons.close_rounded),
            label: const Text('취소'),
          ),
        ],
      ),
    );
  }
}
