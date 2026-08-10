import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../selector/application/dev_auth.dart';
import '../../application/discord/discord_config.dart';

class DiscordWalkiePanel extends StatefulWidget {
  const DiscordWalkiePanel({
    super.key,
    this.areaName,
  });

  final String? areaName;

  @override
  State<DiscordWalkiePanel> createState() => _DiscordWalkiePanelState();
}

class _DiscordWalkiePanelState extends State<DiscordWalkiePanel> {
  static const String _discordSchemeUrl = 'discord://';
  static const String _androidStoreWeb =
      'https://play.google.com/store/apps/details?id=com.discord';
  static const String _androidStoreMarket = 'market://details?id=com.discord';
  static const String _iosStoreUrl =
      'https://apps.apple.com/app/discord-chat-talk-hangout/id985746746';
  static const int _pageCount = 5;
  static const int _invitePage = 2;
  static const int _channelPage = 3;
  static const int _confirmPage = 4;

  final PageController _pageController = PageController();
  final TextEditingController _inviteController = TextEditingController();
  final TextEditingController _channelController = TextEditingController();
  final FocusNode _inviteFocus = FocusNode();
  final FocusNode _channelFocus = FocusNode();
  final List<String> _debugLines = <String>[];

  Timer? _inviteSaveDebounce;
  Timer? _channelSaveDebounce;
  int _currentPage = 0;
  int? _editingStep;
  bool _loading = true;
  bool _connected = false;
  bool _inviteDirty = false;
  bool _channelDirty = false;
  bool _developerMode = false;
  bool _pageCorrectionScheduled = false;
  String _lastPersistedInvite = '';
  String _lastPersistedChannel = '';

  bool get _editingConnectedValue => _connected && _editingStep != null;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  Duration _motion(Duration duration) {
    return _reduceMotion ? Duration.zero : duration;
  }

  @override
  void initState() {
    super.initState();
    _inviteFocus.addListener(_handleInviteFocusChange);
    _channelFocus.addListener(_handleChannelFocusChange);
    DevAuth.devModeEnabled.addListener(_handleDeveloperModeChanged);
    _recordDebug('initialized area=${widget.areaName?.trim() ?? ''}');
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant DiscordWalkiePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.areaName ?? '').trim() != (widget.areaName ?? '').trim()) {
      _recordDebug(
        'area_changed from=${oldWidget.areaName?.trim() ?? ''} to=${widget.areaName?.trim() ?? ''}',
      );
    }
  }

  void _handleDeveloperModeChanged() {
    if (!mounted) return;
    final next = DevAuth.devModeEnabled.value;
    if (_developerMode == next) return;
    _recordDebug('developer_mode_changed enabled=$next');
    setState(() => _developerMode = next);
  }

  void _recordDebug(String message) {
    final line = '[DiscordWalkiePanel] $message';
    _debugLines.add(line);
    if (_debugLines.length > 160) {
      _debugLines.removeRange(0, _debugLines.length - 160);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _showDeveloperStatus() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !mounted) return;
    if (!_developerMode) {
      setState(() => _developerMode = true);
    }
    HapticFeedback.mediumImpact();
    final invite = _inviteController.text.trim();
    final channel = _channelController.text.trim();
    _recordDebug(
      'developer_status_open connected=$_connected page=$_currentPage editingStep=$_editingStep inviteDirty=$_inviteDirty channelDirty=$_channelDirty inviteValid=${isDiscordInviteUrl(invite)} channelValid=${isDiscordChannelUrl(channel)} reduceMotion=$_reduceMotion',
    );
    await StatusDialog.showSuccess(
      context,
      title: 'Discord 무전 연결 상태',
      description:
          'connected=$_connected · page=${_currentPage + 1}/$_pageCount · edit=${_editingStep == null ? 'none' : _editingStep! + 1} · inviteValid=${isDiscordInviteUrl(invite)} · channelValid=${isDiscordChannelUrl(channel)}',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: const Duration(seconds: 30),
      useCommonUi: true,
    );
  }

  Future<void> _load() async {
    _recordDebug('load_start');
    try {
      final prefs = await SharedPreferences.getInstance();
      final invite = prefs.getString(discordWalkieInviteUrlKey) ?? '';
      final channel = prefs.getString(discordWalkieChannelUrlKey) ?? '';
      final done = prefs.getBool(discordWalkieTutorialDoneKey) ?? false;
      final developerMode = await DevAuth.isDevModeEnabled();
      final inviteValid = isDiscordInviteUrl(invite);
      final channelValid = isDiscordChannelUrl(channel);
      final connected = done && inviteValid && channelValid;
      var initialPage = 0;
      if (!connected) {
        if (inviteValid && channelValid) {
          initialPage = _confirmPage;
        } else if (inviteValid) {
          initialPage = _channelPage;
        }
      }
      _inviteController.text = invite;
      _channelController.text = channel;
      _lastPersistedInvite = invite.trim();
      _lastPersistedChannel = channel.trim();
      _inviteDirty = false;
      _channelDirty = false;
      _recordDebug(
        'load_complete done=$done connected=$connected initialPage=$initialPage invitePresent=${invite.trim().isNotEmpty} inviteValid=$inviteValid channelPresent=${channel.trim().isNotEmpty} channelValid=$channelValid developerMode=$developerMode',
      );
      if (!mounted) return;
      setState(() {
        _developerMode = developerMode;
        _connected = connected;
        _currentPage = initialPage;
        _loading = false;
      });
      if (!connected && initialPage > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          _pageController.jumpToPage(initialPage);
        });
      }
    } catch (error, stackTrace) {
      _recordDebug('load_failure error=$error\nStackTrace:\n$stackTrace');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveInvite({required String reason}) async {
    _inviteSaveDebounce?.cancel();
    _inviteSaveDebounce = null;
    if (_editingConnectedValue) {
      _recordDebug('invite_save_skipped reason=$reason connected_edit=true');
      return;
    }
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

  Future<void> _saveChannel({required String reason}) async {
    _channelSaveDebounce?.cancel();
    _channelSaveDebounce = null;
    if (_editingConnectedValue) {
      _recordDebug('channel_save_skipped reason=$reason connected_edit=true');
      return;
    }
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

  void _handleInviteFocusChange() {
    _recordDebug('invite_focus=${_inviteFocus.hasFocus}');
    if (!_inviteFocus.hasFocus && _inviteDirty && !_editingConnectedValue) {
      unawaited(_saveInvite(reason: 'focus_lost'));
    }
  }

  void _handleChannelFocusChange() {
    _recordDebug('channel_focus=${_channelFocus.hasFocus}');
    if (!_channelFocus.hasFocus && _channelDirty && !_editingConnectedValue) {
      unawaited(_saveChannel(reason: 'focus_lost'));
    }
  }

  void _handleInviteChanged(String value) {
    _inviteDirty = value.trim() != _lastPersistedInvite;
    _inviteSaveDebounce?.cancel();
    if (_inviteDirty && !_editingConnectedValue) {
      _inviteSaveDebounce = Timer(const Duration(milliseconds: 700), () {
        if (_inviteDirty && !_editingConnectedValue) {
          unawaited(_saveInvite(reason: 'debounce'));
        }
      });
    }
    if (mounted) setState(() {});
  }

  void _handleChannelChanged(String value) {
    _channelDirty = value.trim() != _lastPersistedChannel;
    _channelSaveDebounce?.cancel();
    if (_channelDirty && !_editingConnectedValue) {
      _channelSaveDebounce = Timer(const Duration(milliseconds: 700), () {
        if (_channelDirty && !_editingConnectedValue) {
          unawaited(_saveChannel(reason: 'debounce'));
        }
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _showSuccess(String title) {
    return StatusDialog.showSuccess(
      context,
      title: title,
      useCommonUi: true,
    );
  }

  Future<void> _showFailure(String title) {
    return StatusDialog.showFailure(
      context,
      title: title,
      useCommonUi: true,
    );
  }

  Future<String?> _readClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Future<void> _copyInvite() async {
    final value = _inviteController.text.trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _recordDebug('invite_copy length=${value.length}');
    if (!mounted) return;
    await _showSuccess(StatusDialog.inviteLinkCopySuccess);
  }

  Future<void> _copyChannel() async {
    final value = _channelController.text.trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _recordDebug('channel_copy length=${value.length}');
    if (!mounted) return;
    await _showSuccess('디스코드 채널 링크를 복사했습니다.');
  }

  Future<void> _pasteInvite() async {
    _recordDebug('invite_clipboard_paste_start editing=$_editingConnectedValue');
    final text = await _readClipboard();
    if (text == null) {
      _recordDebug('invite_clipboard_paste_failure reason=empty');
      await _showFailure(StatusDialog.clipboardTextNotFound);
      return;
    }
    if (!isDiscordInviteUrl(text)) {
      _recordDebug(
        'invite_clipboard_paste_failure reason=invalid length=${text.length}',
      );
      await _showFailure(StatusDialog.discordInviteUrlInvalid);
      return;
    }
    _inviteController.text = text;
    _inviteDirty = text.trim() != _lastPersistedInvite;
    if (!_editingConnectedValue) {
      await _saveInvite(reason: 'clipboard_paste');
    }
    if (!mounted) return;
    setState(() {});
    _recordDebug('invite_clipboard_paste_complete length=${text.length}');
    await _showSuccess(
      _editingConnectedValue ? '초대 링크를 확인했습니다.' : StatusDialog.discordInviteUrlSaveSuccess,
    );
  }

  Future<void> _pasteChannel() async {
    _recordDebug('channel_clipboard_paste_start editing=$_editingConnectedValue');
    final text = await _readClipboard();
    if (text == null) {
      _recordDebug('channel_clipboard_paste_failure reason=empty');
      await _showFailure(StatusDialog.clipboardTextNotFound);
      return;
    }
    if (!isDiscordChannelUrl(text)) {
      _recordDebug(
        'channel_clipboard_paste_failure reason=invalid length=${text.length}',
      );
      await _showFailure('디스코드 채널 링크 형식이 아닙니다.');
      return;
    }
    _channelController.text = text;
    _channelDirty = text.trim() != _lastPersistedChannel;
    if (!_editingConnectedValue) {
      await _saveChannel(reason: 'clipboard_paste');
    }
    if (!mounted) return;
    setState(() {});
    _recordDebug('channel_clipboard_paste_complete length=${text.length}');
    await _showSuccess(
      _editingConnectedValue ? '채널 링크를 확인했습니다.' : '디스코드 채널 링크를 저장했습니다.',
    );
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
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      _recordDebug('external_launch kind=$kind opened=$opened');
      return opened;
    } catch (error, stackTrace) {
      _recordDebug(
        'external_launch_failure kind=$kind error=$error\nStackTrace:\n$stackTrace',
      );
      return false;
    }
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
      if (!storeOpened && mounted) {
        await _showFailure(StatusDialog.externalLinkOpenFailed);
      }
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
    if (!webOpened && mounted) {
      await _showFailure(StatusDialog.externalLinkOpenFailed);
    }
  }

  Future<void> _openInvite() async {
    final url = _inviteController.text.trim();
    if (!isDiscordInviteUrl(url)) {
      _recordDebug('invite_open_blocked reason=invalid length=${url.length}');
      await _showFailure(StatusDialog.discordInviteUrlPasteRequired);
      return;
    }
    if (!_editingConnectedValue) {
      await _saveInvite(reason: 'invite_open');
    }
    final opened = await _launchExternal(url);
    _recordDebug('invite_open_result opened=$opened length=${url.length}');
    if (!opened && mounted) {
      await _showFailure(StatusDialog.externalLinkOpenFailed);
    }
  }

  Future<void> _openChannel() async {
    final url = _channelController.text.trim();
    if (!isDiscordChannelUrl(url)) {
      _recordDebug('channel_open_blocked reason=invalid length=${url.length}');
      await _showFailure('디스코드 채널 링크를 입력해 주세요.');
      return;
    }
    if (!_editingConnectedValue) {
      await _saveChannel(reason: 'channel_open');
    }
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
    if (!opened && mounted) {
      await _showFailure(StatusDialog.externalLinkOpenFailed);
    }
  }

  int _maxAllowedPage() {
    if (!isDiscordInviteUrl(_inviteController.text)) return _invitePage;
    if (!isDiscordChannelUrl(_channelController.text)) return _channelPage;
    return _confirmPage;
  }

  void _handlePageChanged(int page) {
    final maxAllowed = _maxAllowedPage();
    if (page > maxAllowed) {
      _recordDebug(
        'page_swipe_blocked requested=$page maxAllowed=$maxAllowed inviteValid=${isDiscordInviteUrl(_inviteController.text)} channelValid=${isDiscordChannelUrl(_channelController.text)}',
      );
      if (!_pageCorrectionScheduled) {
        _pageCorrectionScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageCorrectionScheduled = false;
          if (!mounted || !_pageController.hasClients) return;
          unawaited(_goToPage(maxAllowed, source: 'swipe_guard'));
        });
      }
      return;
    }
    if (_currentPage == page) return;
    final previous = _currentPage;
    _currentPage = page;
    _recordDebug('page_changed from=$previous to=$page source=swipe');
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  Future<void> _goToPage(int page, {required String source}) async {
    final target = page.clamp(0, _pageCount - 1).toInt();
    final maxAllowed = _maxAllowedPage();
    final allowed = target <= maxAllowed ? target : maxAllowed;
    _recordDebug(
      'page_request current=$_currentPage target=$target allowed=$allowed maxAllowed=$maxAllowed source=$source',
    );
    if (!_pageController.hasClients) {
      if (mounted) setState(() => _currentPage = allowed);
      return;
    }
    if (_reduceMotion) {
      _pageController.jumpToPage(allowed);
      return;
    }
    await _pageController.animateToPage(
      allowed,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _nextPage() async {
    if (_currentPage == _invitePage &&
        !isDiscordInviteUrl(_inviteController.text)) {
      _recordDebug('next_blocked page=$_currentPage reason=invalid_invite');
      await _showFailure(StatusDialog.discordInviteUrlRequired);
      return;
    }
    if (_currentPage == _channelPage &&
        !isDiscordChannelUrl(_channelController.text)) {
      _recordDebug('next_blocked page=$_currentPage reason=invalid_channel');
      await _showFailure('디스코드 채널 링크가 필요해요');
      return;
    }
    await _goToPage(_currentPage + 1, source: 'next_button');
  }

  Future<void> _previousPage() {
    return _goToPage(_currentPage - 1, source: 'previous_button');
  }

  Future<void> _markConnected() async {
    final invite = _inviteController.text.trim();
    final channel = _channelController.text.trim();
    if (!isDiscordInviteUrl(invite)) {
      _recordDebug('connect_confirm_blocked reason=invalid_invite');
      await _showFailure(StatusDialog.discordInviteUrlRequired);
      return;
    }
    if (!isDiscordChannelUrl(channel)) {
      _recordDebug('connect_confirm_blocked reason=invalid_channel');
      await _showFailure('디스코드 채널 링크가 필요해요');
      return;
    }
    await _saveInvite(reason: 'connect_confirm');
    await _saveChannel(reason: 'connect_confirm');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(discordWalkieTutorialDoneKey, true);
      _recordDebug(
        'connect_confirm_success inviteLength=${invite.length} channelLength=${channel.length}',
      );
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _editingStep = null;
      });
      await _showSuccess('Discord 연결을 완료했습니다.');
    } catch (error, stackTrace) {
      _recordDebug(
        'connect_confirm_failure error=$error\nStackTrace:\n$stackTrace',
      );
      if (!mounted) return;
      await _showFailure('Discord 연결 상태를 저장하지 못했어요');
    }
  }

  void _stayOnSetup() {
    _recordDebug('connect_confirm_pending page=$_currentPage');
    HapticFeedback.selectionClick();
    unawaited(_goToPage(_channelPage, source: 'confirm_not_yet'));
  }

  void _startEdit(int step) {
    if (step != _invitePage && step != _channelPage) return;
    _inviteSaveDebounce?.cancel();
    _channelSaveDebounce?.cancel();
    _inviteDirty = false;
    _channelDirty = false;
    _inviteController.text = _lastPersistedInvite;
    _channelController.text = _lastPersistedChannel;
    _recordDebug('connected_edit_start step=$step');
    HapticFeedback.selectionClick();
    setState(() => _editingStep = step);
  }

  void _cancelEdit() {
    final step = _editingStep;
    _inviteController.text = _lastPersistedInvite;
    _channelController.text = _lastPersistedChannel;
    _inviteDirty = false;
    _channelDirty = false;
    _recordDebug('connected_edit_cancel step=$step');
    HapticFeedback.selectionClick();
    setState(() => _editingStep = null);
  }

  Future<void> _commitEdit() async {
    final step = _editingStep;
    if (step == _invitePage) {
      final value = _inviteController.text.trim();
      if (!isDiscordInviteUrl(value)) {
        _recordDebug('connected_edit_blocked step=3 reason=invalid_invite');
        await _showFailure(StatusDialog.discordInviteUrlRequired);
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(discordWalkieInviteUrlKey, value);
        _lastPersistedInvite = value;
        _inviteDirty = false;
        _recordDebug('connected_edit_saved step=3 length=${value.length}');
      } catch (error, stackTrace) {
        _recordDebug(
          'connected_edit_failure step=3 error=$error\nStackTrace:\n$stackTrace',
        );
        if (mounted) await _showFailure('서버 링크를 저장하지 못했어요');
        return;
      }
    } else if (step == _channelPage) {
      final value = _channelController.text.trim();
      if (!isDiscordChannelUrl(value)) {
        _recordDebug('connected_edit_blocked step=4 reason=invalid_channel');
        await _showFailure('디스코드 채널 링크가 필요해요');
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(discordWalkieChannelUrlKey, value);
        _lastPersistedChannel = value;
        _channelDirty = false;
        _recordDebug('connected_edit_saved step=4 length=${value.length}');
      } catch (error, stackTrace) {
        _recordDebug(
          'connected_edit_failure step=4 error=$error\nStackTrace:\n$stackTrace',
        );
        if (mounted) await _showFailure('채널 링크를 저장하지 못했어요');
        return;
      }
    } else {
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _editingStep = null);
    await _showSuccess(step == _invitePage ? '서버 링크를 수정했습니다.' : '채널 링크를 수정했습니다.');
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final area = widget.areaName?.trim() ?? '';
    final title = area.isEmpty ? 'Discord 업무 채널' : '$area Discord';
    final subtitle = _connected ? '업무 채널 연결됨' : '업무 채널 연결';
    return Material(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: _motion(const Duration(milliseconds: 220)),
              curve: Curves.easeOutCubic,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _connected ? cs.primaryContainer : cs.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: _motion(const Duration(milliseconds: 220)),
                child: Icon(
                  _connected ? Icons.check_rounded : Icons.forum_rounded,
                  key: ValueKey<bool>(_connected),
                  color: _connected
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (text.titleMedium ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: _motion(const Duration(milliseconds: 180)),
                    child: Text(
                      subtitle,
                      key: ValueKey<String>(subtitle),
                      style: (text.labelMedium ?? const TextStyle()).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_connected && !_loading)
              AnimatedContainer(
                duration: _motion(const Duration(milliseconds: 180)),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentPage + 1}/$_pageCount',
                  style: text.labelMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            if (_developerMode)
              IconButton(
                tooltip: 'Discord 디버그 상태',
                onPressed: _showDeveloperStatus,
                icon: const Icon(Icons.bug_report_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPage(int index) {
    switch (index) {
      case 0:
        return _buildActionPage(
          icon: Icons.download_done_rounded,
          title: 'Discord 준비',
          description: 'Discord 앱을 설치하거나 실행한 뒤 다시 이 화면으로 돌아오세요.',
          primaryIcon: Icons.open_in_new_rounded,
          primaryLabel: 'Discord 설치/열기',
          onPrimary: _openDiscordOrStore,
        );
      case 1:
        return _buildActionPage(
          icon: Icons.person_add_alt_1_rounded,
          title: '계정 준비',
          description: 'Discord 계정을 준비하고 마이크 권한 요청이 나오면 허용하세요.',
          primaryIcon: Icons.open_in_new_rounded,
          primaryLabel: 'Discord 열기',
          onPrimary: _openDiscordOrStore,
        );
      case _invitePage:
        return _buildInvitePage(editing: false);
      case _channelPage:
        return _buildChannelPage(editing: false);
      case _confirmPage:
        return _buildConfirmPage();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildActionPage({
    required IconData icon,
    required String title,
    required String description,
    required IconData primaryIcon,
    required String primaryLabel,
    required VoidCallback onPrimary,
  }) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 36, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPrimary,
                  icon: Icon(primaryIcon),
                  label: Text(primaryLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvitePage({required bool editing}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final valid = isDiscordInviteUrl(_inviteController.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AnimatedContainer(
            duration: _motion(const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: valid
                  ? cs.primaryContainer.withOpacity(.52)
                  : cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: valid
                    ? cs.primary.withOpacity(.52)
                    : cs.outlineVariant.withOpacity(.7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: valid ? cs.primary : cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        valid ? Icons.check_rounded : Icons.link_rounded,
                        color: valid ? cs.onPrimary : cs.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editing ? '서버 링크 수정' : '서버 참가',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '관리자가 전달한 Discord 초대 링크',
                            style: text.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '서버 초대 링크',
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _inviteController,
                  focusNode: _inviteFocus,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link_rounded),
                    suffixIcon: IconButton(
                      tooltip: '초대 링크 복사',
                      onPressed: _inviteController.text.trim().isEmpty
                          ? null
                          : _copyInvite,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                  onChanged: _handleInviteChanged,
                  onSubmitted: (_) {
                    if (!_editingConnectedValue) {
                      unawaited(_saveInvite(reason: 'input_submit'));
                    }
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pasteInvite,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('클립보드'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openInvite,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('서버 참가'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelPage({required bool editing}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final valid = isDiscordChannelUrl(_channelController.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AnimatedContainer(
            duration: _motion(const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: valid
                  ? cs.primaryContainer.withOpacity(.52)
                  : cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: valid
                    ? cs.primary.withOpacity(.52)
                    : cs.outlineVariant.withOpacity(.7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: valid ? cs.primary : cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        valid ? Icons.check_rounded : Icons.tag_rounded,
                        color: valid ? cs.onPrimary : cs.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editing ? '채널 링크 수정' : '채널 연결',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '바로 이동할 Discord 업무 채널',
                            style: text.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '채널 직접 링크',
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _channelController,
                  focusNode: _channelFocus,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.tag_rounded),
                    suffixIcon: IconButton(
                      tooltip: '채널 링크 복사',
                      onPressed: _channelController.text.trim().isEmpty
                          ? null
                          : _copyChannel,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                  onChanged: _handleChannelChanged,
                  onSubmitted: (_) {
                    if (!_editingConnectedValue) {
                      unawaited(_saveChannel(reason: 'input_submit'));
                    }
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pasteChannel,
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
        ),
      ),
    );
  }

  Widget _buildConfirmPage() {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.verified_user_rounded,
                  size: 38,
                  color: cs.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Discord 연결을 성공했나요?',
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                '서버 참가와 업무 채널 연결을 확인한 뒤 연결 상태를 완료할 수 있습니다.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _stayOnSetup,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('아직이에요'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _markConnected,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('연결했어요'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _pageCount,
      physics: const BouncingScrollPhysics(),
      onPageChanged: _handlePageChanged,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _pageController,
          builder: (context, child) {
            var page = _currentPage.toDouble();
            if (_pageController.hasClients &&
                _pageController.position.hasContentDimensions) {
              page = _pageController.page ?? page;
            }
            final distance = (page - index).abs().clamp(0.0, 1.0).toDouble();
            final opacity = _reduceMotion ? 1.0 : 1.0 - distance * 0.28;
            final scale = _reduceMotion ? 1.0 : 1.0 - distance * 0.025;
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            );
          },
          child: _buildStepPage(index),
        );
      },
    );
  }

  Widget _buildSetupNavigation() {
    final cs = Theme.of(context).colorScheme;
    final canGoPrevious = _currentPage > 0;
    final isConfirm = _currentPage == _confirmPage;
    return Material(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: TextButton.icon(
                onPressed: canGoPrevious ? _previousPage : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('이전'),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_pageCount, (index) {
                  final active = index == _currentPage;
                  final complete = index < _currentPage;
                  return AnimatedContainer(
                    duration: _motion(const Duration(milliseconds: 180)),
                    curve: Curves.easeOutCubic,
                    width: active ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active
                          ? cs.primary
                          : complete
                              ? cs.primary.withOpacity(.48)
                              : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
            SizedBox(
              width: 92,
              child: isConfirm
                  ? const SizedBox.shrink()
                  : FilledButton(
                      onPressed: _nextPage,
                      child: const Text('다음'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView() {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final channel = _lastPersistedChannel;
    return SingleChildScrollView(
      key: const ValueKey<String>('discord-connected'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: _reduceMotion ? 1 : .86, end: 1),
                duration: _motion(const Duration(milliseconds: 420)),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Center(
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 48,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Discord 연결됨',
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                '업무 채널을 바로 열 수 있습니다.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              AnimatedContainer(
                duration: _motion(const Duration(milliseconds: 260)),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(.48),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.primary.withOpacity(.36)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _connectionNode(
                          icon: Icons.phone_android_rounded,
                          label: '앱',
                          active: true,
                        ),
                        _connectionLine(),
                        _connectionNode(
                          icon: Icons.forum_rounded,
                          label: 'Discord',
                          active: true,
                        ),
                        _connectionLine(),
                        _connectionNode(
                          icon: Icons.tag_rounded,
                          label: '업무 채널',
                          active: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: channel.isEmpty ? null : _openChannel,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Discord 채널 바로가기'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _startEdit(_invitePage),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('서버 링크 수정'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _startEdit(_channelPage),
                      icon: const Icon(Icons.tag_rounded),
                      label: const Text('채널 수정'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionNode({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          AnimatedContainer(
            duration: _motion(const Duration(milliseconds: 220)),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _connectionLine() {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(.42),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  Widget _buildEditView() {
    final step = _editingStep;
    if (step == null) return _buildConnectedView();
    final page = step == _invitePage
        ? _buildInvitePage(editing: true)
        : _buildChannelPage(editing: true);
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: ValueKey<String>('discord-edit-$step'),
      children: [
        Expanded(child: page),
        Material(
          color: cs.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelEdit,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _commitEdit,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('수정 완료'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panelTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: .985, end: 1).animate(curved),
        child: child,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: ValueKey<String>('discord-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_connected) {
      return AnimatedSwitcher(
        duration: _motion(const Duration(milliseconds: 300)),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _panelTransition,
        child: _editingStep == null ? _buildConnectedView() : _buildEditView(),
      );
    }
    return Column(
      key: const ValueKey<String>('discord-setup'),
      children: [
        Expanded(child: _buildPageView()),
        _buildSetupNavigation(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: AnimatedSwitcher(
                duration: _motion(const Duration(milliseconds: 320)),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _panelTransition,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inviteSaveDebounce?.cancel();
    _channelSaveDebounce?.cancel();
    if (!_editingConnectedValue) {
      if (_inviteDirty) {
        unawaited(_saveInvite(reason: 'dispose'));
      }
      if (_channelDirty) {
        unawaited(_saveChannel(reason: 'dispose'));
      }
    }
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    _inviteFocus.removeListener(_handleInviteFocusChange);
    _channelFocus.removeListener(_handleChannelFocusChange);
    _pageController.dispose();
    _inviteFocus.dispose();
    _channelFocus.dispose();
    _inviteController.dispose();
    _channelController.dispose();
    super.dispose();
  }
}
