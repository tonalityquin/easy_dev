import 'package:flutter/material.dart';

import '../../controllers/voice_runtime_controller.dart';

class VoiceParkingCompletedAppbarPanel extends StatelessWidget {
  const VoiceParkingCompletedAppbarPanel({super.key});

  Future<void> _openReplayDialog(
    BuildContext context,
    VoiceRuntimeController controller,
  ) async {
    if (controller.messages.isEmpty || controller.isUploading) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _VoiceReplayDialog(controller: controller);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = VoiceRuntimeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final canOpenReplay = controller.messages.isNotEmpty;

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
                      onPressed: canOpenReplay && !controller.isUploading
                          ? () => _openReplayDialog(context, controller)
                          : null,
                      icon: Icon(
                        controller.currentlyPlayingMessageId == null
                            ? Icons.history_rounded
                            : Icons.stop_circle_outlined,
                        size: 18,
                      ),
                      label: Text(
                        controller.currentlyPlayingMessageId == null
                            ? '코멘트 다시 듣기'
                            : '재생 중',
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

class _VoiceReplayDialog extends StatelessWidget {
  const _VoiceReplayDialog({required this.controller});

  final VoiceRuntimeController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasLatest = controller.messages.isNotEmpty;
    final hasPrevious = controller.messages.length > 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.campaign_rounded,
                      color: cs.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '코멘트 다시 듣기',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '들을 코멘트를 선택하세요',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _VoiceReplayActionButton(
                icon: Icons.replay_rounded,
                title: '방금 코멘트 듣기',
                subtitle: '가장 최근 무전을 다시 재생합니다',
                enabled: hasLatest,
                filled: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await controller.playLatestComment();
                },
              ),
              const SizedBox(height: 10),
              _VoiceReplayActionButton(
                icon: Icons.history_rounded,
                title: '이전 코멘트 듣기',
                subtitle: hasPrevious ? '방금 전 무전을 재생합니다' : '이전 코멘트가 없습니다',
                enabled: hasPrevious,
                filled: false,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await controller.playPreviousComment();
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceReplayActionButton extends StatelessWidget {
  const _VoiceReplayActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool filled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = filled ? cs.primary : cs.surfaceContainerHighest;
    final fg = filled ? cs.onPrimary : cs.onSurface;
    final subFg = filled ? cs.onPrimary.withOpacity(0.86) : cs.onSurfaceVariant;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? () => onPressed() : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: subFg),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
