import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../selector/application/dev_auth.dart';
import '../../../application/discord/discord_config.dart';

class DiscordBottomSheet extends StatefulWidget {
  const DiscordBottomSheet({super.key, required this.rootContext});

  final BuildContext rootContext;

  @override
  State<DiscordBottomSheet> createState() => _DiscordBottomSheetState();
}

class _DiscordBottomSheetState extends State<DiscordBottomSheet> {
  static const String _discordSchemeUrl = 'discord://';
  static const String _androidStoreWeb =
      'https://play.google.com/store/apps/details?id=com.discord';
  static const String _androidStoreMarket = 'market://details?id=com.discord';
  static const String _iosStoreUrl =
      'https://apps.apple.com/app/discord-chat-talk-hangout/id985746746';

  final TextEditingController _inviteController = TextEditingController();
  final TextEditingController _channelController = TextEditingController();
  final FocusNode _inviteFocus = FocusNode();
  final FocusNode _channelFocus = FocusNode();
  final List<String> _debugLines = <String>[];

  Timer? _inviteSaveDebounce;
  Timer? _channelSaveDebounce;
  int _currentStep = 0;
  bool _loading = true;
  bool _inviteDirty = false;
  bool _channelDirty = false;
  bool _developerMode = false;
  String _lastPersistedInvite = '';
  String _lastPersistedChannel = '';

  BuildContext get _statusContext =>
      widget.rootContext.mounted ? widget.rootContext : context;

  @override
  void initState() {
    super.initState();
    _inviteFocus.addListener(_handleInviteFocusChange);
    _channelFocus.addListener(_handleChannelFocusChange);
    _recordDebug('initialized');
    _load();
  }

  @override
  void dispose() {
    _inviteSaveDebounce?.cancel();
    _channelSaveDebounce?.cancel();
    if (_inviteDirty) {
      unawaited(_saveInvite(reason: 'dispose'));
    }
    if (_channelDirty) {
      unawaited(_saveChannel(reason: 'dispose'));
    }
    _inviteFocus.removeListener(_handleInviteFocusChange);
    _channelFocus.removeListener(_handleChannelFocusChange);
    _inviteFocus.dispose();
    _channelFocus.dispose();
    _inviteController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  void _recordDebug(String message) {
    final line = '[DiscordBottomSheet] $message';
    _debugLines.add(line);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
    debugPrint(line);
  }

  Future<void> _showDeveloperStatus() async {
    final enabled = await DevAuth.isDeveloperLoggedIn();
    if (!enabled || !mounted) return;
    if (!_developerMode) {
      setState(() => _developerMode = true);
    }
    HapticFeedback.mediumImpact();
    final invite = _inviteController.text.trim();
    final channel = _channelController.text.trim();
    _recordDebug(
      'developer_status_open step=$_currentStep inviteDirty=$_inviteDirty channelDirty=$_channelDirty inviteLength=${invite.length} inviteValid=${isDiscordInviteUrl(invite)} channelLength=${channel.length} channelValid=${isDiscordChannelUrl(channel)}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: _statusContext,
      title: '서드파티 연결 지원 상태',
      initialMessage: 'Discord 연결 지원 상태를 수집하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    if (!trace.developerMode) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    trace.log(
      'step=$_currentStep, loading=$_loading, inviteDirty=$_inviteDirty, channelDirty=$_channelDirty, reduceMotion=$reduceMotion',
      progress: 0.24,
    );
    trace.log(
      'invitePresent=${invite.isNotEmpty}, inviteLength=${invite.length}, inviteValid=${isDiscordInviteUrl(invite)}',
      progress: 0.38,
    );
    trace.log(
      'channelPresent=${channel.isNotEmpty}, channelLength=${channel.length}, channelValid=${isDiscordChannelUrl(channel)}',
      progress: 0.48,
    );
    trace.log(
      'persistence=invite_and_channel_dirty_on_change_debounce700ms_focus_lost_submit_paste_open_complete_close_dispose',
      progress: 0.58,
    );
    trace.log(
      'stepTransition=fade_y8_220ms, channelCard=animated180ms, channelLaunch=discord_scheme_then_https_fallback, reducedMotion=$reduceMotion',
      progress: 0.7,
    );
    final snapshot = List<String>.of(_debugLines);
    if (snapshot.isEmpty) {
      trace.log('기록된 Discord 연결 지원 로그가 없습니다.', progress: 0.84);
    } else {
      for (var i = 0; i < snapshot.length; i++) {
        trace.log(
          snapshot[i],
          progress: 0.7 + ((i + 1) / snapshot.length) * 0.22,
        );
      }
    }
    await trace.succeed('Discord 연결 지원 상태 수집이 완료되었습니다.');
  }

  Future<void> _showSuccessStatus(String title) {
    return StatusDialog.showSuccess(
      _statusContext,
      title: title,
    );
  }

  Future<void> _showFailureStatus(String title) {
    return StatusDialog.showFailure(
      _statusContext,
      title: title,
    );
  }

  Future<void> _load() async {
    _recordDebug('load_start');
    try {
      final prefs = await SharedPreferences.getInstance();
      final invite = prefs.getString(discordWalkieInviteUrlKey) ?? '';
      final channel = prefs.getString(discordWalkieChannelUrlKey) ?? '';
      final developerMode = await DevAuth.isDeveloperLoggedIn();
      _inviteController.text = invite;
      _channelController.text = channel;
      _lastPersistedInvite = invite.trim();
      _lastPersistedChannel = channel.trim();
      _inviteDirty = false;
      _channelDirty = false;
      _recordDebug(
        'load_complete invitePresent=${invite.trim().isNotEmpty} inviteValid=${isDiscordInviteUrl(invite)} channelPresent=${channel.trim().isNotEmpty} channelValid=${isDiscordChannelUrl(channel)} developerMode=$developerMode',
      );
      if (!mounted) return;
      setState(() {
        _developerMode = developerMode;
        _loading = false;
      });
    } catch (error, stackTrace) {
      _recordDebug('load_failure error=$error\nStackTrace:\n$stackTrace');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveInvite({required String reason}) async {
    _inviteSaveDebounce?.cancel();
    _inviteSaveDebounce = null;
    final value = _inviteController.text.trim();
    if (!_inviteDirty && value == _lastPersistedInvite) {
      _recordDebug(
        'invite_save_skipped reason=$reason unchanged=true length=${value.length}',
      );
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(discordWalkieInviteUrlKey, value);
      _lastPersistedInvite = value;
      _inviteDirty = false;
      _recordDebug(
        'invite_saved reason=$reason length=${value.length} valid=${isDiscordInviteUrl(value)}',
      );
    } catch (error, stackTrace) {
      _recordDebug(
        'invite_save_failure reason=$reason error=$error\nStackTrace:\n$stackTrace',
      );
    }
  }

  void _handleInviteFocusChange() async {
    _recordDebug('invite_focus=${_inviteFocus.hasFocus}');
    if (!_inviteFocus.hasFocus && _inviteDirty) {
      await _saveInvite(reason: 'focus_lost');
    }
  }

  void _handleInviteChanged(String value) {
    _inviteDirty = value.trim() != _lastPersistedInvite;
    _inviteSaveDebounce?.cancel();
    if (_inviteDirty) {
      _inviteSaveDebounce = Timer(const Duration(milliseconds: 700), () {
        if (_inviteDirty) {
          unawaited(_saveInvite(reason: 'debounce'));
        }
      });
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveChannel({required String reason}) async {
    _channelSaveDebounce?.cancel();
    _channelSaveDebounce = null;
    final value = _channelController.text.trim();
    if (!_channelDirty && value == _lastPersistedChannel) {
      _recordDebug(
        'channel_save_skipped reason=$reason unchanged=true length=${value.length}',
      );
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(discordWalkieChannelUrlKey, value);
      _lastPersistedChannel = value;
      _channelDirty = false;
      _recordDebug(
        'channel_saved reason=$reason length=${value.length} valid=${isDiscordChannelUrl(value)}',
      );
    } catch (error, stackTrace) {
      _recordDebug(
        'channel_save_failure reason=$reason error=$error\nStackTrace:\n$stackTrace',
      );
    }
  }

  void _handleChannelFocusChange() async {
    _recordDebug('channel_focus=${_channelFocus.hasFocus}');
    if (!_channelFocus.hasFocus && _channelDirty) {
      await _saveChannel(reason: 'focus_lost');
    }
  }

  void _handleChannelChanged(String value) {
    _channelDirty = value.trim() != _lastPersistedChannel;
    _channelSaveDebounce?.cancel();
    if (_channelDirty) {
      _channelSaveDebounce = Timer(const Duration(milliseconds: 700), () {
        if (_channelDirty) {
          unawaited(_saveChannel(reason: 'debounce'));
        }
      });
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearSaved() async {
    _recordDebug('reset_start');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(discordWalkieInviteUrlKey);
      await prefs.remove(discordWalkieChannelUrlKey);
      await prefs.setBool(discordWalkieTutorialDoneKey, false);
      _inviteController.clear();
      _channelController.clear();
      _lastPersistedInvite = '';
      _lastPersistedChannel = '';
      _inviteDirty = false;
      _channelDirty = false;
      if (!mounted) return;
      setState(() {
        _currentStep = 0;
      });
      _recordDebug('reset_complete step=0 inviteCleared=true channelCleared=true');
      await _showSuccessStatus('저장된 Discord 연결 링크를 초기화했습니다.');
    } catch (error, stackTrace) {
      _recordDebug('reset_failure error=$error\nStackTrace:\n$stackTrace');
      await _showFailureStatus('저장된 링크를 초기화하지 못했어요');
    }
  }

  String _urlKind(String url) {
    final normalized = url.trim().toLowerCase();
    if (normalized == _discordSchemeUrl) return 'discord_scheme';
    if (normalized == _androidStoreMarket) return 'android_store_market';
    if (normalized == _androidStoreWeb) return 'android_store_web';
    if (normalized == _iosStoreUrl) return 'ios_store';
    if (normalized.startsWith('discord:///channels/')) {
      return 'discord_channel_scheme';
    }
    if (isDiscordInviteUrl(normalized)) return 'discord_invite';
    if (isDiscordChannelUrl(normalized)) return 'discord_channel';
    return 'other';
  }

  Future<bool> _launchExternal(String url) async {
    final kind = _urlKind(url);
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      _recordDebug('external_launch kind=$kind parsed=false');
      return false;
    }
    try {
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      _recordDebug('external_launch kind=$kind opened=$opened');
      return opened;
    } catch (error, stackTrace) {
      _recordDebug(
        'external_launch_failure kind=$kind error=$error\nStackTrace:\n$stackTrace',
      );
      return false;
    }
  }

  Future<void> _copyInviteLink(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _recordDebug('invite_copy length=${value.length}');
    await _showSuccessStatus(StatusDialog.inviteLinkCopySuccess);
  }

  Future<void> _copyChannelLink(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _recordDebug('channel_copy length=${value.length}');
    await _showSuccessStatus('디스코드 채널 링크를 복사했습니다.');
  }

  Future<String?> _readClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Future<void> _pasteInviteFromClipboard() async {
    _recordDebug('clipboard_paste_start');
    final text = await _readClipboard();
    if (text == null) {
      _recordDebug('clipboard_paste_failure reason=empty');
      await _showFailureStatus(StatusDialog.clipboardTextNotFound);
      return;
    }
    if (!isDiscordInviteUrl(text)) {
      _recordDebug(
        'clipboard_paste_failure reason=invalid length=${text.length}',
      );
      await _showFailureStatus(StatusDialog.discordInviteUrlInvalid);
      return;
    }
    _inviteController.text = text;
    _inviteDirty = text.trim() != _lastPersistedInvite;
    await _saveInvite(reason: 'clipboard_paste');
    if (mounted) {
      setState(() {});
    }
    _recordDebug('clipboard_paste_complete length=${text.length}');
    await _showSuccessStatus(StatusDialog.discordInviteUrlSaveSuccess);
  }

  Future<void> _pasteChannelFromClipboard() async {
    _recordDebug('channel_clipboard_paste_start');
    final text = await _readClipboard();
    if (text == null) {
      _recordDebug('channel_clipboard_paste_failure reason=empty');
      await _showFailureStatus(StatusDialog.clipboardTextNotFound);
      return;
    }
    if (!isDiscordChannelUrl(text)) {
      _recordDebug(
        'channel_clipboard_paste_failure reason=invalid length=${text.length}',
      );
      await _showFailureStatus(
        '디스코드 채널 링크 형식이 아닙니다.',
      );
      return;
    }
    _channelController.text = text;
    _channelDirty = text.trim() != _lastPersistedChannel;
    await _saveChannel(reason: 'clipboard_paste');
    if (mounted) {
      setState(() {});
    }
    _recordDebug('channel_clipboard_paste_complete length=${text.length}');
    await _showSuccessStatus('디스코드 채널 링크를 저장했습니다.');
  }

  Future<void> _openDiscordOrStore() async {
    _recordDebug('discord_open_start');
    final opened = await _launchExternal(_discordSchemeUrl);
    if (opened) {
      _recordDebug('discord_open_complete destination=discord_app');
      return;
    }

    if (Platform.isIOS) {
      final storeOpened = await _launchExternal(_iosStoreUrl);
      _recordDebug(
        'discord_open_complete destination=ios_store opened=$storeOpened',
      );
      return;
    }

    final marketOpened = await _launchExternal(_androidStoreMarket);
    if (marketOpened) {
      _recordDebug('discord_open_complete destination=android_market');
      return;
    }
    final webOpened = await _launchExternal(_androidStoreWeb);
    _recordDebug(
      'discord_open_complete destination=android_store_web opened=$webOpened',
    );
  }

  Future<void> _openInvite() async {
    final url = _inviteController.text.trim();
    if (!isDiscordInviteUrl(url)) {
      _recordDebug(
        'invite_open_blocked reason=invalid length=${url.length}',
      );
      await _showFailureStatus(StatusDialog.discordInviteUrlPasteRequired);
      return;
    }
    await _saveInvite(reason: 'invite_open');
    final ok = await _launchExternal(url);
    _recordDebug('invite_open_result opened=$ok length=${url.length}');
    if (!ok) {
      await _showFailureStatus(StatusDialog.externalLinkOpenFailed);
    }
  }

  Future<void> _openChannel() async {
    final url = _channelController.text.trim();
    if (!isDiscordChannelUrl(url)) {
      _recordDebug(
        'channel_open_blocked reason=invalid length=${url.length}',
      );
      await _showFailureStatus(
        '디스코드 채널 링크를 입력해 주세요.',
      );
      return;
    }
    await _saveChannel(reason: 'channel_open');
    final appUrl = discordChannelDeepLink(url);
    var opened = false;
    var destination = 'https_channel';
    if (appUrl != null) {
      opened = await _launchExternal(appUrl);
      destination = opened ? 'discord_app_channel' : 'https_channel';
    }
    if (!opened) {
      opened = await _launchExternal(url);
    }
    _recordDebug(
      'channel_open_result opened=$opened destination=$destination length=${url.length}',
    );
    if (!opened) {
      await _showFailureStatus(StatusDialog.externalLinkOpenFailed);
    }
  }

  Future<void> _markDone() async {
    final invite = _inviteController.text.trim();
    final channel = _channelController.text.trim();
    if (!isDiscordInviteUrl(invite)) {
      _recordDebug(
        'complete_blocked reason=invalid_invite length=${invite.length}',
      );
      await _showFailureStatus(StatusDialog.discordInviteUrlRequired);
      return;
    }
    if (channel.isNotEmpty && !isDiscordChannelUrl(channel)) {
      _recordDebug(
        'complete_blocked reason=invalid_channel length=${channel.length}',
      );
      await _showFailureStatus(
        '디스코드 채널 링크 형식을 확인해 주세요.',
      );
      return;
    }
    await _saveInvite(reason: 'complete');
    if (_channelDirty) {
      await _saveChannel(reason: 'complete');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(discordWalkieTutorialDoneKey, true);
    _recordDebug(
      'complete_success inviteLength=${invite.length} channelPresent=${channel.isNotEmpty} channelLength=${channel.length}',
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _closeSheet() async {
    if (_inviteDirty) {
      await _saveInvite(reason: 'close_button');
    }
    if (_channelDirty) {
      await _saveChannel(reason: 'close_button');
    }
    _recordDebug('sheet_close result=false');
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  void _changeStep(int nextStep, {required String source}) {
    final clamped = nextStep.clamp(0, 2).toInt();
    if (clamped == _currentStep) return;
    final previous = _currentStep;
    _recordDebug('step_change from=$previous to=$clamped source=$source');
    HapticFeedback.selectionClick();
    setState(() => _currentStep = clamped);
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }

  Widget _supportText(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
    );
  }

  Step _installStep() {
    return Step(
      title: const Text('디스코드 설치'),
      subtitle: const Text('처음이라면 먼저 설치'),
      isActive: _currentStep >= 0,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('이 단계에서 할 일'),
          const SizedBox(height: 8),
          _supportText(
            '1) 아래 버튼으로 디스코드를 설치하세요.\n2) 설치가 끝나면 다시 이 앱으로 돌아오면 됩니다.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openDiscordOrStore,
            icon: const Icon(Icons.download_rounded),
            label: const Text('디스코드 설치/열기'),
          ),
        ],
      ),
    );
  }

  Step _signupStep() {
    return Step(
      title: const Text('계정 만들기'),
      subtitle: const Text('구글 이메일로 가입 가능'),
      isActive: _currentStep >= 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('이 단계에서 할 일'),
          const SizedBox(height: 8),
          _supportText(
            '1) 디스코드를 열고 회원가입을 진행하세요.\n2) 마이크 권한 요청이 나오면 허용하세요.\n3) 가입이 끝나면 다시 이 앱으로 돌아오세요.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openDiscordOrStore,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('디스코드 열기'),
          ),
        ],
      ),
    );
  }

  Step _joinServerStep() {
    return Step(
      title: const Text('서버 참가'),
      subtitle: const Text('관리자가 준 초대 링크'),
      isActive: _currentStep >= 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('초대 링크 붙여넣기'),
          const SizedBox(height: 8),
          _supportText(
            '관리자가 전달한 초대 링크를 복사한 뒤, 아래에서 붙여넣어 주세요.\n예: discord.gg/… 또는 discord.com/invite/…\n\n서버에 들어가면 디스코드 앱에서 음성 채널(무전 채널)을 직접 선택해 입장하면 됩니다.',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _inviteController,
            focusNode: _inviteFocus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: _inviteController.text.trim().isEmpty
                    ? null
                    : () => _copyInviteLink(_inviteController.text.trim()),
              ),
            ),
            onChanged: _handleInviteChanged,
            onSubmitted: (_) async {
              await _saveInvite(reason: 'input_submit');
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pasteInviteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('클립보드'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openInvite,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('초대 열기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedContainer(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDiscordChannelUrl(_channelController.text)
                  ? Theme.of(context).colorScheme.primaryContainer.withAlpha(92)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('채널 직접 링크'),
                const SizedBox(height: 8),
                _supportText(
                  '빠른 실행의 “서드 파티 사용”에서 바로 열 디스코드 채널 링크를 저장할 수 있습니다.\n형식: https://discord.com/channels/SERVER_ID/CHANNEL_ID',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _channelController,
                  focusNode: _channelFocus,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: _channelController.text.trim().isEmpty
                          ? null
                          : () => _copyChannelLink(
                                _channelController.text.trim(),
                              ),
                    ),
                  ),
                  onChanged: _handleChannelChanged,
                  onSubmitted: (_) async {
                    await _saveChannel(reason: 'input_submit');
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pasteChannelFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('클립보드'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openChannel,
                        icon: const Icon(Icons.forum_rounded),
                        label: const Text('채널 열기'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _supportText(
            '서버에 들어갔으면 아래의 “완료”를 눌러 주세요.\n초대 링크는 커뮤니티 허브에서 사용하고, 저장된 채널 링크는 빠른 실행의 “서드 파티 사용”에서 바로 열 수 있습니다.',
          ),
        ],
      ),
    );
  }

  Widget _buildStepTransition({required bool reduceMotion}) {
    final motion =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return AnimatedSwitcher(
      duration: motion,
      reverseDuration: motion,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            child: child,
            builder: (context, transitionChild) {
              return Transform.translate(
                offset: Offset(0, 8 * (1 - curved.value)),
                child: transitionChild,
              );
            },
          ),
        );
      },
      child: Stepper(
        key: ValueKey<int>(_currentStep),
        currentStep: _currentStep,
        onStepTapped: (index) => _changeStep(index, source: 'step_tap'),
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == 2;
          return Row(
            children: [
              if (!isLastStep)
                FilledButton(
                  onPressed: () =>
                      _changeStep(_currentStep + 1, source: 'next'),
                  child: const Text('다음'),
                ),
              if (isLastStep)
                FilledButton(
                  onPressed: _markDone,
                  child: const Text('완료'),
                ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _currentStep == 0
                    ? null
                    : () => _changeStep(
                          _currentStep - 1,
                          source: 'previous',
                        ),
                child: const Text('이전'),
              ),
            ],
          );
        },
        steps: [
          _installStep(),
          _signupStep(),
          _joinServerStep(),
        ],
      ),
    );
  }

  Widget _buildSheet(BuildContext context, {required bool reduceMotion}) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      key: const ValueKey<String>('discord_sheet_content'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: _showDeveloperStatus,
                    child: Text(
                      '디스코드 시작하기',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearSaved,
                  child: const Text('초기화'),
                ),
                IconButton(
                  onPressed: _closeSheet,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: _buildStepTransition(reduceMotion: reduceMotion),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    return AnimatedSwitcher(
      duration: motion,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: _loading
          ? const SizedBox(
              key: ValueKey<String>('discord_sheet_loading'),
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            )
          : _buildSheet(context, reduceMotion: reduceMotion),
    );
  }
}
