import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../app/models/capability.dart';
import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../dev/application/area_state.dart';
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

  bool _loading = true;
  bool _openingApp = false;
  bool _developerMode = false;

  BuildContext get _statusContext =>
      widget.rootContext.mounted ? widget.rootContext : context;

  bool get _canUseThirdParty {
    try {
      return context
          .read<AreaState>()
          .capabilitiesOfCurrentArea
          .contains(Capability.record);
    } catch (_) {
      return false;
    }
  }

  bool get _inviteValid => isDiscordInviteUrl(_inviteController.text);
  bool get _channelValid => isDiscordChannelUrl(_channelController.text);

  @override
  void initState() {
    super.initState();
    _inviteController.addListener(_handleEditorChanged);
    _channelController.addListener(_handleEditorChanged);
    _recordDebug('initialized layout=connection_support_cards');
    _load();
  }

  @override
  void dispose() {
    _inviteController.removeListener(_handleEditorChanged);
    _channelController.removeListener(_handleEditorChanged);
    _inviteController.dispose();
    _channelController.dispose();
    _inviteFocus.dispose();
    _channelFocus.dispose();
    super.dispose();
  }

  void _handleEditorChanged() {
    if (mounted) setState(() {});
  }

  void _recordDebug(String message) {
    final line = '[DiscordConnectionSupport] $message';
    _debugLines.add(line);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
    debugPrint(line);
  }

  Duration _duration(Duration duration) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? Duration.zero : duration;
  }

  Future<void> _load() async {
    try {
      final invite = await loadDiscordInviteUrl();
      final channel = await loadDiscordChannelUrl();
      final developerMode = await DevAuth.isDevModeEnabled();
      _inviteController.text = invite;
      _channelController.text = channel;
      _recordDebug(
        'load_complete capability=$_canUseThirdParty invitePresent=${invite.isNotEmpty} inviteValid=${isDiscordInviteUrl(invite)} channelPresent=${channel.isNotEmpty} channelValid=${isDiscordChannelUrl(channel)} developerMode=$developerMode',
      );
      if (!mounted) return;
      setState(() {
        _developerMode = developerMode;
        _loading = false;
      });
    } catch (error, stackTrace) {
      _recordDebug('load_failure error=$error');
      debugPrintStack(
        label: '[DiscordConnectionSupport] load_failure',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<bool> _launchExternal(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      _recordDebug('launch_failure uri=$value error=$error');
      debugPrintStack(
        label: '[DiscordConnectionSupport] launch_failure',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _openDiscordOrStore() async {
    if (!_canUseThirdParty || _openingApp) return;
    HapticFeedback.selectionClick();
    setState(() => _openingApp = true);
    _recordDebug('discord_app_open_start');
    var opened = await _launchExternal(_discordSchemeUrl);
    var destination = 'discord_app';
    if (!opened) {
      destination = 'store';
      if (Platform.isAndroid) {
        opened = await _launchExternal(_androidStoreMarket);
        if (!opened) {
          opened = await _launchExternal(_androidStoreWeb);
        }
      } else if (Platform.isIOS) {
        opened = await _launchExternal(_iosStoreUrl);
      } else {
        opened = await _launchExternal('https://discord.com/download');
      }
    }
    _recordDebug(
      'discord_app_open_result opened=$opened destination=$destination',
    );
    if (mounted) setState(() => _openingApp = false);
    if (!opened && _statusContext.mounted) {
      await StatusDialog.showFailure(
        _statusContext,
        title: 'Discord 앱 또는 설치 페이지를 열 수 없습니다.',
        useCommonUi: true,
      );
    }
    await _showOperationTrace(
      title: 'Discord 앱 연결',
      lines: <String>[
        'capability=record enabled=$_canUseThirdParty',
        'opened=$opened destination=$destination',
        'policy=discord_scheme_then_platform_store',
      ],
      success: opened,
      successMessage: 'Discord 앱 연결 요청이 완료되었습니다.',
      failureMessage: 'Discord 앱 연결 요청에 실패했습니다.',
    );
  }

  Future<void> _openInvite() async {
    if (!_inviteValid) return;
    HapticFeedback.selectionClick();
    final opened = await _launchExternal(_inviteController.text.trim());
    _recordDebug('invite_open_result opened=$opened');
    if (!opened && _statusContext.mounted) {
      await StatusDialog.showFailure(
        _statusContext,
        title: 'Discord 초대 링크를 열 수 없습니다.',
        useCommonUi: true,
      );
    }
  }

  Future<void> _openChannel() async {
    if (!_channelValid) return;
    HapticFeedback.selectionClick();
    final channel = _channelController.text.trim();
    final deepLink = discordChannelDeepLink(channel);
    var opened = false;
    var destination = 'https_channel';
    if (deepLink != null) {
      opened = await _launchExternal(deepLink);
      if (opened) destination = 'discord_app_channel';
    }
    if (!opened) {
      opened = await _launchExternal(channel);
    }
    _recordDebug(
      'channel_open_result opened=$opened destination=$destination',
    );
    if (!opened && _statusContext.mounted) {
      await StatusDialog.showFailure(
        _statusContext,
        title: 'Discord 업무 채널을 열 수 없습니다.',
        useCommonUi: true,
      );
    }
    await _showOperationTrace(
      title: 'Discord 업무 채널 연결',
      lines: <String>[
        'capability=record enabled=$_canUseThirdParty',
        'channelValid=$_channelValid destination=$destination opened=$opened',
        'launchPolicy=discord_scheme_then_https_fallback',
      ],
      success: opened,
      successMessage: 'Discord 업무 채널 연결 요청이 완료되었습니다.',
      failureMessage: 'Discord 업무 채널 연결 요청에 실패했습니다.',
    );
  }

  Future<void> _showOperationTrace({
    required String title,
    required List<String> lines,
    required bool success,
    required String successMessage,
    required String failureMessage,
  }) async {
    final trace = await DeveloperOperationTrace.start(
      context: _statusContext,
      title: title,
      initialMessage: '서드파티 연결 상태를 기록합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 클립보드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    for (var i = 0; i < lines.length; i++) {
      trace.log(lines[i], progress: .2 + ((i + 1) / lines.length) * .62);
    }
    trace.log(
      'inviteValid=$_inviteValid channelValid=$_channelValid reduceMotion=${MediaQuery.maybeOf(context)?.disableAnimations ?? false}',
      progress: .88,
    );
    if (success) {
      await trace.succeed(successMessage);
    } else {
      await trace.fail(failureMessage);
    }
    if (trace.developerMode && _statusContext.mounted) {
      await trace.showStatusDialog(_statusContext);
    }
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !_statusContext.mounted) return;
    HapticFeedback.mediumImpact();
    await _showOperationTrace(
      title: '서드파티 연결 지원 상태',
      lines: <String>[
        'capability=record enabled=$_canUseThirdParty',
        'invitePresent=${_inviteController.text.trim().isNotEmpty} inviteValid=$_inviteValid source=sqlite_snapshot',
        'channelPresent=${_channelController.text.trim().isNotEmpty} channelValid=$_channelValid source=sqlite_snapshot',
        'layout=connection_support_cards animation=selection190_component230 reducedMotion=${MediaQuery.maybeOf(context)?.disableAnimations ?? false}',
        ..._debugLines,
      ],
      success: true,
      successMessage: '서드파티 연결 지원 상태 수집이 완료되었습니다.',
      failureMessage: '서드파티 연결 지원 상태 수집에 실패했습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final canUse = context
        .watch<AreaState>()
        .capabilitiesOfCurrentArea
        .contains(Capability.record);
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: tokens.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: _duration(CommonUiMotion.selection),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: canUse
                          ? tokens.accentContainer
                          : tokens.surfaceDisabled,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.extension_rounded,
                      color: canUse
                          ? tokens.onAccentContainer
                          : tokens.textDisabled,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '서드파티 연결 지원',
                          style: text.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Discord 설치 · 서버 초대 · 업무 채널',
                          style: text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_developerMode)
                    IconButton(
                      tooltip: '개발자 상태',
                      onPressed: _showDeveloperStatus,
                      icon: const Icon(Icons.bug_report_outlined),
                    ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.borderSubtle),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedSwitcher(
                            duration: _duration(CommonUiMotion.component),
                            child: canUse
                                ? const SizedBox.shrink(
                                    key: ValueKey<String>('capability-enabled'),
                                  )
                                : _CapabilityBlockedCard(
                                    key: const ValueKey<String>(
                                      'capability-disabled',
                                    ),
                                  ),
                          ),
                          if (!canUse) const SizedBox(height: 12),
                          _ConnectionStepCard(
                            index: 1,
                            icon: Icons.download_for_offline_rounded,
                            title: 'Discord 앱 준비',
                            description:
                                '앱이 설치되어 있으면 바로 열고, 없으면 설치 페이지로 이동합니다.',
                            complete: false,
                            enabled: canUse,
                            actionLabel: _openingApp ? '확인 중' : 'Discord 열기 / 설치',
                            onAction: _openingApp ? null : _openDiscordOrStore,
                          ),
                          const SizedBox(height: 12),
                          _ConnectionEditorCard(
                            index: 2,
                            icon: Icons.group_add_rounded,
                            title: '서버 초대',
                            description: '본사 내려받기 SQLite Snapshot의 Discord 초대 링크를 사용합니다.',
                            controller: _inviteController,
                            focusNode: _inviteFocus,
                            label: '초대 링크',
                            valid: _inviteValid,
                            enabled: canUse,
                            onOpen: _inviteValid ? _openInvite : null,
                            openLabel: '초대 열기',
                          ),
                          const SizedBox(height: 12),
                          _ConnectionEditorCard(
                            index: 3,
                            icon: Icons.forum_rounded,
                            title: '업무 채널',
                            description:
                                '본사 내려받기 SQLite Snapshot의 Discord 업무 채널 링크를 사용합니다.',
                            controller: _channelController,
                            focusNode: _channelFocus,
                            label: '채널 링크',
                            valid: _channelValid,
                            enabled: canUse,
                            onOpen: _channelValid ? _openChannel : null,
                            openLabel: '채널 열기',
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityBlockedCard extends StatelessWidget {
  const _CapabilityBlockedCard({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.warningContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.warning.withOpacity(.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: tokens.onWarningContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '현재 지역에서 서드파티 연결 capability가 비활성화되어 있습니다.',
              style: TextStyle(
                color: tokens.onWarningContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStepCard extends StatelessWidget {
  const _ConnectionStepCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.description,
    required this.complete,
    required this.enabled,
    required this.actionLabel,
    required this.onAction,
  });

  final int index;
  final IconData icon;
  final String title;
  final String description;
  final bool complete;
  final bool enabled;
  final String actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedOpacity(
      opacity: enabled ? 1 : .5,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: complete ? tokens.accentContainer : tokens.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: complete ? tokens.accent : tokens.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StepIcon(index: index, icon: icon, complete: complete),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: enabled && onAction != null ? () => onAction!() : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionEditorCard extends StatelessWidget {
  const _ConnectionEditorCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.description,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.valid,
    required this.enabled,
    required this.onOpen,
    required this.openLabel,
  });

  final int index;
  final IconData icon;
  final String title;
  final String description;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool valid;
  final bool enabled;
  final Future<void> Function()? onOpen;
  final String openLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedOpacity(
      opacity: enabled ? 1 : .5,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: valid
              ? tokens.accentContainer.withOpacity(.34)
              : tokens.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: valid ? tokens.accent.withOpacity(.7) : tokens.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StepIcon(index: index, icon: icon, complete: valid),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Icon(
                    valid
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    key: ValueKey<bool>(valid),
                    color: valid ? tokens.success : tokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              readOnly: true,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: Icon(
                  valid ? Icons.verified_rounded : Icons.link_off_rounded,
                  color: valid ? tokens.success : tokens.textSecondary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: enabled && onOpen != null ? () => onOpen!() : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(openLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({
    required this.index,
    required this.icon,
    required this.complete,
  });

  final int index;
  final IconData icon;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: complete ? tokens.accentContainer : tokens.surfaceSelected,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: complete ? tokens.accent : tokens.borderSubtle,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: .86, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              complete ? Icons.check_rounded : icon,
              key: ValueKey<bool>(complete),
              color: complete ? tokens.accent : tokens.textSecondary,
            ),
          ),
          Positioned(
            right: 3,
            bottom: 2,
            child: Text(
              '$index',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
