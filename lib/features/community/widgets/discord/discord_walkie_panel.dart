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
  final List<String> _debugLines = <String>[];

  int _currentPage = 0;
  bool _loading = true;
  bool _connected = false;
  bool _developerMode = false;
  bool _pageCorrectionScheduled = false;
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  Duration _motion(Duration duration) {
    return _reduceMotion ? Duration.zero : duration;
  }

  @override
  void initState() {
    super.initState();
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
      'developer_status_open connected=$_connected page=$_currentPage inviteValid=${isDiscordInviteUrl(invite)} channelValid=${isDiscordChannelUrl(channel)} reduceMotion=$_reduceMotion',
    );
    await StatusDialog.showSuccess(
      context,
      title: 'Discord 무전 연결 상태',
      description:
          'connected=$_connected · page=${_currentPage + 1}/$_pageCount · inviteValid=${isDiscordInviteUrl(invite)} · channelValid=${isDiscordChannelUrl(channel)}',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      awaitManualClose: true,
      useCommonUi: true,
    );
  }

  Future<void> _load() async {
    _recordDebug('load_start');
    try {
      final prefs = await SharedPreferences.getInstance();
      final invite = await loadDiscordInviteUrl();
      final channel = await loadDiscordChannelUrl();
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(discordWalkieTutorialDoneKey, true);
      _recordDebug(
        'connect_confirm_success inviteLength=${invite.length} channelLength=${channel.length}',
      );
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() => _connected = true);
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
        return _buildInvitePage();
      case _channelPage:
        return _buildChannelPage();
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

  Widget _buildInvitePage() {
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
                            '서버 참가',
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
                  readOnly: true,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: valid ? _openInvite : null,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('서버 참가'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelPage() {
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
                            '채널 연결',
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
                  readOnly: true,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: valid ? _openChannel : null,
                    icon: const Icon(Icons.forum_rounded),
                    label: const Text('채널 열기'),
                  ),
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
    final channel = _channelController.text.trim();
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
      return _buildConnectedView();
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
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    _pageController.dispose();
    _inviteController.dispose();
    _channelController.dispose();
    super.dispose();
  }
}
