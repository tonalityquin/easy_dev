import 'package:flutter/material.dart';

import '../../../domain/models/voice_message.dart';

class VoiceMessageTile extends StatelessWidget {
  const VoiceMessageTile({
    super.key,
    required this.message,
    required this.isMine,
    required this.isPlaying,
    required this.progress,
    required this.subtitle,
    required this.onPlay,
    required this.onDelete,
  });

  final voice_message message;
  final bool isMine;
  final bool isPlaying;
  final double progress;
  final String subtitle;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clampedProgress = progress.clamp(0, 1).toDouble();
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      isMine ? cs.primaryContainer : cs.secondaryContainer,
                  child: Text(
                    message.senderName.isEmpty
                        ? '?'
                        : message.senderName.substring(0, 1),
                    style: TextStyle(
                      color: isMine
                          ? cs.onPrimaryContainer
                          : cs.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.senderName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        '$subtitle · ${_formatDuration(message.duration)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: isPlaying ? clampedProgress : 0),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onPlay,
                  icon: Icon(isPlaying
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(isPlaying ? '정지' : '재생'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isMine
                        ? '내가 보낸 음성'
                        : '${message.senderIdentity} · ${message.areaName}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
