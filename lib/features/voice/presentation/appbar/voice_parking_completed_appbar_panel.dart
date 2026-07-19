import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../controllers/voice_runtime_controller.dart';

class VoiceParkingCompletedAppbarPanel extends StatelessWidget {
  const VoiceParkingCompletedAppbarPanel({super.key});

  Future<void> _openReplayDialog(
    BuildContext context,
    VoiceRuntimeController controller,
  ) async {
    if (controller.messages.isEmpty || controller.isUploading) return;
    await showPromptOverlayDialog<void>(
      context: context,
      builder: (_) => _VoiceReplayDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = VoiceRuntimeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tokens = PromptUiTheme.of(context);
        final canOpenReplay = controller.messages.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: AnimatedContainer(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : PromptUiMotion.selection,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(
                color: controller.active
                    ? tokens.accent
                    : tokens.borderSubtle,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration:
                      MediaQuery.maybeOf(context)?.disableAnimations ?? false
                          ? Duration.zero
                          : PromptUiMotion.selection,
                  child: Icon(
                    controller.active
                        ? Icons.campaign_rounded
                        : Icons.campaign_outlined,
                    key: ValueKey<bool>(controller.active),
                    size: 18,
                    color: controller.active
                        ? tokens.accent
                        : tokens.iconSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PromptButton(
                    label: controller.currentlyPlayingMessageId == null
                        ? '코멘트 다시 듣기'
                        : '재생 중',
                    icon: controller.currentlyPlayingMessageId == null
                        ? Icons.history_rounded
                        : Icons.stop_circle_outlined,
                    onPressed: canOpenReplay && !controller.isUploading
                        ? () => _openReplayDialog(context, controller)
                        : null,
                    variant: PromptButtonVariant.secondary,
                    expand: true,
                    minHeight: 36,
                    haptic: PromptHaptic.selection,
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final hasLatest = controller.messages.isNotEmpty;
    final hasPrevious = controller.messages.length > 1;

    return PromptDialogFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.campaign_rounded,
                    color: tokens.onAccentContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '코멘트 다시 듣기',
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '들을 코멘트를 선택하세요',
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
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
              primary: true,
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
              primary: false,
              onPressed: () async {
                Navigator.of(context).pop();
                await controller.playPreviousComment();
              },
            ),
            const SizedBox(height: 14),
            PromptButton(
              label: '닫기',
              onPressed: () => Navigator.of(context).pop(),
              variant: PromptButtonVariant.tertiary,
              expand: true,
              haptic: PromptHaptic.selection,
            ),
          ],
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
    required this.primary,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool primary;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final background = primary ? tokens.accent : tokens.surfaceOverlay;
    final foreground = primary ? tokens.onAccent : tokens.textPrimary;
    final secondary = primary
        ? tokens.onAccent.withOpacity(0.82)
        : tokens.textSecondary;

    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: tokens.transparent,
        child: InkWell(
          onTap: enabled
              ? () async {
                  await HapticFeedback.selectionClick();
                  await onPressed();
                }
              : null,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(
                color: primary ? tokens.accent : tokens.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: secondary),
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final label = widget.isUploading
        ? '업로드 중'
        : widget.isRecording
            ? '손을 떼면 전송'
            : '길게 눌러 무전';
    final background = widget.isUploading
        ? tokens.surfaceDisabled
        : widget.isRecording
            ? tokens.accentContainer
            : tokens.accent;
    final foreground = widget.isUploading
        ? tokens.textDisabled
        : widget.isRecording
            ? tokens.onAccentContainer
            : tokens.onAccent;

    return Semantics(
      button: true,
      enabled: !widget.isUploading,
      label: label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          border: Border.all(
            color: widget.isRecording ? tokens.accent : tokens.transparent,
          ),
        ),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.isUploading
              ? null
              : (_) async {
                  _pressed = true;
                  await HapticFeedback.mediumImpact();
                  await widget.onStart();
                  if (mounted) setState(() {});
                },
          onPointerUp: widget.isUploading
              ? null
              : (_) async {
                  if (!_pressed) return;
                  _pressed = false;
                  await widget.onFinish();
                  if (mounted) setState(() {});
                },
          onPointerCancel: widget.isUploading
              ? null
              : (_) async {
                  if (!_pressed) return;
                  _pressed = false;
                  await widget.onCancel();
                  if (mounted) setState(() {});
                },
          child: SizedBox(
            height: 36,
            child: Center(
              child: AnimatedScale(
                scale: _pressed ? 0.96 : 1,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
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
                      color: foreground,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
