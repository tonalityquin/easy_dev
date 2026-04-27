import 'package:flutter/material.dart';

import '../../../controllers/voice_runtime_controller.dart';

class VoiceParkingCompletedAppbarPanel extends StatelessWidget {
  const VoiceParkingCompletedAppbarPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VoiceRuntimeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final canPlayPrevious = controller.messages.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Material(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: kToolbarHeight - 16,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(0.75),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(
                children: [
                  Icon(
                    controller.active
                        ? Icons.campaign_rounded
                        : Icons.campaign_outlined,
                    size: 18,
                    color: controller.active ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canPlayPrevious && !controller.isUploading
                          ? controller.playPreviousComment
                          : null,
                      icon: Icon(
                        controller.currentlyPlayingMessageId == null
                            ? Icons.history_rounded
                            : Icons.stop_circle_outlined,
                        size: 18,
                      ),
                      label: Text(
                        controller.currentlyPlayingMessageId == null
                            ? '이전 코멘트 듣기'
                            : '재생 정지',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: VoiceCompactHoldToTalkButton(
                      isRecording: controller.isRecording,
                      isUploading: controller.isUploading,
                      onStart: controller.startRecording,
                      onCancel: controller.cancelRecording,
                      onFinish: controller.stopRecordingAndSend,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class VoiceCompactHoldToTalkButton extends StatefulWidget {
  const VoiceCompactHoldToTalkButton({
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
  State<VoiceCompactHoldToTalkButton> createState() =>
      _VoiceCompactHoldToTalkButtonState();
}

class _VoiceCompactHoldToTalkButtonState
    extends State<VoiceCompactHoldToTalkButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.isUploading
        ? '업로드 중'
        : widget.isRecording
            ? '손을 떼면 전송'
            : '길게 눌러 무전';

    return Material(
      color: widget.isRecording ? cs.primaryContainer : cs.primary,
      borderRadius: BorderRadius.circular(12),
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
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isUploading
                    ? Icons.cloud_upload_rounded
                    : widget.isRecording
                        ? Icons.mic_rounded
                        : Icons.keyboard_voice_rounded,
                size: 18,
                color:
                    widget.isRecording ? cs.onPrimaryContainer : cs.onPrimary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isRecording
                        ? cs.onPrimaryContainer
                        : cs.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
