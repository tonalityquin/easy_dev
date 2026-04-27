import 'package:flutter/material.dart';

class VoiceHoldToTalkButton extends StatefulWidget {
  const VoiceHoldToTalkButton({
    super.key,
    required this.isRecording,
    required this.isUploading,
    required this.onStart,
    required this.onCancel,
    required this.onFinish,
  });

  final bool isRecording;
  final bool isUploading;
  final Future<void> Function() onStart;
  final Future<void> Function() onCancel;
  final Future<void> Function() onFinish;

  @override
  State<VoiceHoldToTalkButton> createState() =>
      _VoiceHoldToTalkButtonState();
}

class _VoiceHoldToTalkButtonState
    extends State<VoiceHoldToTalkButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.isUploading
        ? '업로드 중...'
        : widget.isRecording
            ? '손을 떼면 전송됩니다'
            : '길게 눌러 녹음';
    final help = widget.isRecording
        ? '터치가 취소되면 업로드하지 않습니다'
        : '동일 지역 계정에는 최신 2개 음성만 유지됩니다';

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(24),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.isUploading
            ? null
            : (_) async {
                _pressed = true;
                await widget.onStart();
                if (mounted) {
                  setState(() {});
                }
              },
        onPointerUp: widget.isUploading
            ? null
            : (_) async {
                if (!_pressed) {
                  return;
                }
                _pressed = false;
                await widget.onFinish();
                if (mounted) {
                  setState(() {});
                }
              },
        onPointerCancel: widget.isUploading
            ? null
            : (_) async {
                if (!_pressed) {
                  return;
                }
                _pressed = false;
                await widget.onCancel();
                if (mounted) {
                  setState(() {});
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          child: Column(
            children: [
              Icon(
                widget.isUploading
                    ? Icons.cloud_upload_rounded
                    : widget.isRecording
                        ? Icons.mic_rounded
                        : Icons.keyboard_voice_rounded,
                size: 42,
                color: cs.primary,
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                help,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
