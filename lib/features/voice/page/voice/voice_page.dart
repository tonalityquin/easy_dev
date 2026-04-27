import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../account/applications/user_state.dart';
import '../../../account/domain/models/session_account.dart';
import '../../../dev/application/area_state.dart';
import '../../controllers/voice_runtime_controller.dart';
import '../../domain/models/voice_message.dart';
import 'widgets/voice_hold_to_talk_button.dart';
import 'widgets/voice_message_tile.dart';

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final VoiceRuntimeController _controller = VoiceRuntimeController.instance;
  bool _bootstrapped = false;
  String _boundAreaName = '';
  String _boundUserId = '';
  bool _syncingChannel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped || !mounted) {
      return;
    }
    _bootstrapped = true;
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final session = userState.session;
    final currentArea = areaState.currentArea.trim();
    if (session == null) {
      await _controller.initialize();
      return;
    }
    await _syncChannelFor(
        session: session, currentArea: currentArea, force: true);
  }

  Future<void> _syncChannelFor({
    required SessionAccount session,
    required String currentArea,
    bool force = false,
  }) async {
    final normalizedArea = currentArea.trim();
    if (_syncingChannel || !mounted) {
      return;
    }
    if (normalizedArea.isEmpty) {
      await _controller.stop();
      _boundAreaName = '';
      _boundUserId = '';
      return;
    }
    final userId = session.id;
    final unchanged = !force &&
        _boundAreaName == normalizedArea &&
        _boundUserId == userId &&
        _controller.active;
    if (unchanged) {
      return;
    }
    _syncingChannel = true;
    try {
      await _controller.start(session: session, areaName: normalizedArea);
      _boundAreaName = normalizedArea;
      _boundUserId = userId;
    } finally {
      _syncingChannel = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final activeSession = userState.session;
    final currentArea = areaState.currentArea.trim();
    final dateFormat = DateFormat('MM/dd HH:mm');
    final activeUserName = activeSession?.displayName ?? '';

    final needsSync = activeSession != null &&
        currentArea.isNotEmpty &&
        (_boundAreaName != currentArea || _boundUserId != activeSession.id);
    if (needsSync && !_syncingChannel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final latestSession = context.read<UserState>().session;
        final latestArea = context.read<AreaState>().currentArea.trim();
        if (latestSession == null || latestArea.isEmpty) {
          return;
        }
        _syncChannelFor(session: latestSession, currentArea: latestArea);
      });
    }
    if (activeSession == null && _controller.active && !_syncingChannel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.stop();
        _boundAreaName = '';
        _boundUserId = '';
      });
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final messages = _controller.messages;
        final canOpen = activeSession != null && currentArea.isNotEmpty;
        final errorMessage = _controller.errorMessage ?? '';

        return Scaffold(
          backgroundColor: cs.surfaceContainerLowest,
          appBar: AppBar(
            title: const Text('워킨토킨'),
            actions: [
              IconButton(
                onPressed: !canOpen
                    ? null
                    : () async {
                        if (_controller.active) {
                          await _controller.stop();
                        } else {
                          await _controller.start(
                            session: activeSession,
                            areaName: currentArea,
                          );
                        }
                      },
                icon: Icon(
                  _controller.active
                      ? Icons.power_settings_new_rounded
                      : Icons.play_circle_fill_rounded,
                ),
                tooltip: _controller.active ? '수신 중지' : '수신 시작',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: cs.outlineVariant.withOpacity(0.8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeUserName.isNotEmpty
                              ? '$activeUserName · 워킨토킨'
                              : '워킨토킨',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          currentArea.isEmpty
                              ? 'currentArea 값이 비어 있습니다.'
                              : 'currentArea 기준 채널: $currentArea',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _controller.active
                                  ? Icons.campaign_rounded
                                  : Icons.campaign_outlined,
                              size: 18,
                              color:
                                  _controller.active ? cs.primary : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _controller.active
                                    ? '근무 중 자동 수신 활성화 · 동일 지역 새 음성 자동 재생'
                                    : '자동 수신 비활성화',
                              ),
                            ),
                          ],
                        ),
                        if (errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorMessage,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                        if (!canOpen) ...[
                          const SizedBox(height: 10),
                          const Text(
                            '현재 로그인 사용자 또는 currentArea를 확인할 수 없습니다.',
                            style: TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text('아직 음성이 없습니다. 아래 버튼을 길게 눌러 첫 메시지를 보내세요.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isPlaying =
                                _controller.currentlyPlayingMessageId ==
                                    message.id;
                            final progress = isPlaying &&
                                    _controller.playerDuration.inMilliseconds >
                                        0
                                ? _controller.playerPosition.inMilliseconds /
                                    _controller.playerDuration.inMilliseconds
                                : 0.0;
                            return VoiceMessageTile(
                              message: message,
                              isMine: activeSession != null &&
                                  message.senderId == activeSession.id,
                              isPlaying: isPlaying,
                              progress: progress,
                              subtitle: dateFormat.format(message.createdAt),
                              onPlay: () => _controller.togglePlayback(message),
                              onDelete: () => _confirmDelete(context, message),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemCount: messages.length,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: VoiceHoldToTalkButton(
                    isRecording: _controller.isRecording,
                    isUploading: _controller.isUploading,
                    onStart: _controller.startRecording,
                    onCancel: _controller.cancelRecording,
                    onFinish: _controller.stopRecordingAndSend,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    voice_message message,
  ) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('음성 삭제'),
              content: Text('${message.senderName}의 메시지를 삭제하시겠습니까?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('삭제'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!shouldDelete || !context.mounted) {
      return;
    }
    await _controller.deleteMessage(message);
  }
}
