import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/models/capability.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../../selector/application/dev_auth.dart';
import '../../application/discord/discord_config.dart';

enum DiscordConnectionSupportAccessPolicy {
  areaCapability,
  headquarter,
}

Future<bool?> showDiscordConnectionSupportSideDock({
  required BuildContext context,
  required String source,
  CommonSideDockSide side = CommonSideDockSide.right,
  DiscordConnectionSupportAccessPolicy accessPolicy =
      DiscordConnectionSupportAccessPolicy.areaCapability,
}) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final sideName = side == CommonSideDockSide.left ? 'left' : 'right';
  final presentation = '${sideName}_side_dock';
  debugPrint(
    '[DiscordConnectionSupport] side_dock_open source=$source presentation=$presentation layout=list_surface side=$sideName accessPolicy=${accessPolicy.name} maxWidth=440 widthFactor=0.94 reduceMotion=$reduceMotion',
  );
  final builder = (BuildContext _) => DiscordConnectionSupportSideDock(
        rootContext: context,
        source: source,
        side: side,
        accessPolicy: accessPolicy,
      );
  final result = side == CommonSideDockSide.left
      ? await showCommonLeftSideDock<bool>(
          context: context,
          useRootNavigator: true,
          maxWidth: 440,
          widthFactor: .94,
          barrierLabel: '서드파티 연결 지원',
          barrierDismissible: true,
          builder: builder,
        )
      : await showCommonRightSideDock<bool>(
          context: context,
          useRootNavigator: true,
          maxWidth: 440,
          widthFactor: .94,
          barrierLabel: '서드파티 연결 지원',
          barrierDismissible: true,
          builder: builder,
        );
  debugPrint(
    '[DiscordConnectionSupport] side_dock_closed source=$source side=$sideName accessPolicy=${accessPolicy.name} result=$result',
  );
  return result;
}

class DiscordConnectionSupportSideDock extends StatefulWidget {
  const DiscordConnectionSupportSideDock({
    super.key,
    required this.rootContext,
    required this.source,
    required this.side,
    required this.accessPolicy,
  });

  final BuildContext rootContext;
  final String source;
  final CommonSideDockSide side;
  final DiscordConnectionSupportAccessPolicy accessPolicy;

  @override
  State<DiscordConnectionSupportSideDock> createState() =>
      _DiscordConnectionSupportSideDockState();
}

class _DiscordConnectionSupportSideDockState
    extends State<DiscordConnectionSupportSideDock> {
  static const String _discordSchemeUrl = 'discord://';
  static const String _androidStoreWeb =
      'https://play.google.com/store/apps/details?id=com.discord';
  static const String _androidStoreMarket = 'market://details?id=com.discord';
  static const String _iosStoreUrl =
      'https://apps.apple.com/app/discord-chat-talk-hangout/id985746746';

  final List<String> _debugLines = <String>[];

  String _inviteUrl = '';
  String _channelUrl = '';
  bool _loading = true;
  bool _openingApp = false;
  bool _developerMode = false;

  BuildContext get _statusContext =>
      widget.rootContext.mounted ? widget.rootContext : context;

  String get _sideName =>
      widget.side == CommonSideDockSide.left ? 'left' : 'right';

  String get _presentationName => '${_sideName}_side_dock';

  String get _sideDockMotion => widget.side == CommonSideDockSide.left
      ? 'negative_x_to_zero_240ms'
      : 'positive_x_to_zero_240ms';

  String get _accessSummary => widget.accessPolicy ==
          DiscordConnectionSupportAccessPolicy.headquarter
      ? 'accessPolicy=headquarter enabled=true'
      : 'accessPolicy=areaCapability capability=record enabled=$_canUseThirdParty';

  bool get _canUseThirdParty {
    if (widget.accessPolicy ==
        DiscordConnectionSupportAccessPolicy.headquarter) {
      return true;
    }
    try {
      return context
          .read<AreaState>()
          .capabilitiesOfCurrentArea
          .contains(Capability.record);
    } catch (_) {
      return false;
    }
  }

  bool get _inviteValid => isDiscordInviteUrl(_inviteUrl);
  bool get _channelValid => isDiscordChannelUrl(_channelUrl);

  @override
  void initState() {
    super.initState();
    _recordDebug(
      'initialized source=${widget.source} presentation=$_presentationName side=$_sideName accessPolicy=${widget.accessPolicy.name} layout=list_surface header=common_side_dock_frame sections=connection_status,connection_steps',
    );
    _load();
  }

  @override
  void dispose() {
    debugPrint(
      '[DiscordConnectionSupport] disposed source=${widget.source} inviteValid=$_inviteValid channelValid=$_channelValid',
    );
    super.dispose();
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
      _recordDebug(
        'load_complete source=${widget.source} $_accessSummary invitePresent=${invite.isNotEmpty} inviteValid=${isDiscordInviteUrl(invite)} channelPresent=${channel.isNotEmpty} channelValid=${isDiscordChannelUrl(channel)} developerMode=$developerMode configSource=sqlite_snapshot',
      );
      if (!mounted) return;
      setState(() {
        _inviteUrl = invite.trim();
        _channelUrl = channel.trim();
        _developerMode = developerMode;
        _loading = false;
      });
    } catch (error, stackTrace) {
      _recordDebug('load_failure source=${widget.source} error=$error');
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
    if (mounted) setState(() => _openingApp = true);
    _recordDebug('discord_app_open_start source=${widget.source}');
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
      'discord_app_open_result source=${widget.source} opened=$opened destination=$destination',
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
        _accessSummary,
        'opened=$opened destination=$destination',
        'policy=discord_scheme_then_platform_store',
      ],
      success: opened,
      successMessage: 'Discord 앱 연결 요청이 완료되었습니다.',
      failureMessage: 'Discord 앱 연결 요청에 실패했습니다.',
    );
  }

  Future<void> _openInvite() async {
    if (!_canUseThirdParty || !_inviteValid) return;
    HapticFeedback.selectionClick();
    _recordDebug(
      'invite_open_start source=${widget.source} inviteValid=$_inviteValid',
    );
    final opened = await _launchExternal(_inviteUrl);
    _recordDebug(
      'invite_open_result source=${widget.source} opened=$opened',
    );
    if (!opened && _statusContext.mounted) {
      await StatusDialog.showFailure(
        _statusContext,
        title: 'Discord 초대 링크를 열 수 없습니다.',
        useCommonUi: true,
      );
    }
    await _showOperationTrace(
      title: 'Discord 서버 초대 연결',
      lines: <String>[
        _accessSummary,
        'inviteValid=$_inviteValid opened=$opened',
        'launchPolicy=https_external_application',
      ],
      success: opened,
      successMessage: 'Discord 서버 초대 연결 요청이 완료되었습니다.',
      failureMessage: 'Discord 서버 초대 연결 요청에 실패했습니다.',
    );
  }

  Future<void> _openChannel() async {
    if (!_canUseThirdParty || !_channelValid) return;
    HapticFeedback.selectionClick();
    final channel = _channelUrl;
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
      'channel_open_result source=${widget.source} opened=$opened destination=$destination',
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
        _accessSummary,
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
    final recentDebug = _debugLines.length > 24
        ? _debugLines.sublist(_debugLines.length - 24)
        : List<String>.of(_debugLines);
    final traceLines = <String>[
      'source=${widget.source} presentation=$_presentationName side=$_sideName accessPolicy=${widget.accessPolicy.name} layout=list_surface header=common_side_dock_frame sections=connection_status,connection_steps',
      'stepPresentation=continuous_list_rows configSource=sqlite_snapshot',
      ...lines,
      'inviteValid=$_inviteValid channelValid=$_channelValid reduceMotion=${MediaQuery.maybeOf(context)?.disableAnimations ?? false}',
      ...recentDebug.map((line) => 'debug=$line'),
    ];
    for (var i = 0; i < traceLines.length; i++) {
      final progress = .14 + ((i + 1) / traceLines.length) * .72;
      trace.log(traceLines[i], progress: progress.clamp(0.14, .86).toDouble());
    }
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
        _accessSummary,
        'invitePresent=${_inviteUrl.isNotEmpty} inviteValid=$_inviteValid source=sqlite_snapshot',
        'channelPresent=${_channelUrl.isNotEmpty} channelValid=$_channelValid source=sqlite_snapshot',
        'sideDockMotion=$_sideDockMotion internalMotion=section_stagger22_selection190_component230',
      ],
      success: true,
      successMessage: '서드파티 연결 지원 상태 수집이 완료되었습니다.',
      failureMessage: '서드파티 연결 지원 상태 수집에 실패했습니다.',
    );
  }

  void _requestClose() {
    _recordDebug('close_requested source=header entrySource=${widget.source}');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final canUse = widget.accessPolicy ==
            DiscordConnectionSupportAccessPolicy.headquarter
        ? true
        : context
            .watch<AreaState>()
            .capabilitiesOfCurrentArea
            .contains(Capability.record);

    return CommonSideDockFrame(
      title: '서드파티 연결 지원',
      subtitle: 'Discord 앱 · 서버 초대 · 업무 채널',
      icon: Icons.extension_rounded,
      onClose: _requestClose,
      headerAction: _developerMode
          ? Semantics(
              button: true,
              label: '서드파티 연결 지원 개발자 상태',
              child: IconButton(
                onPressed: _showDeveloperStatus,
                icon: Icon(
                  Icons.bug_report_rounded,
                  color: tokens.accent,
                ),
              ),
            )
          : null,
      child: AnimatedSwitcher(
        duration: _duration(CommonUiMotion.component),
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) {
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          if (reduceMotion) return child;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .018),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _loading
            ? _buildLoadingBody(context)
            : _buildSupportBody(context, canUse),
      ),
    );
  }

  Widget _buildLoadingBody(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('third_party_support_loading'),
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        CommonSideDockSection(
          title: '연결 상태',
          order: 1,
          child: OpsDockListSurface(
            child: SizedBox(
              height: 92,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: CommonUiTheme.of(context).accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportBody(BuildContext context, bool canUse) {
    return ListView(
      key: const ValueKey<String>('third_party_support_content'),
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        CommonSideDockSection(
          title: '연결 상태',
          order: 1,
          child: OpsDockListSurface(
            child: Column(
              children: [
                _ConnectionInfoRow(
                  icon: canUse
                      ? Icons.check_circle_rounded
                      : Icons.lock_outline_rounded,
                  title: '현재 지역',
                  value: canUse ? '연결 가능' : '연결 비활성',
                  description: canUse
                      ? '서드파티 연결 기능을 사용할 수 있습니다.'
                      : '서드파티 연결 capability가 필요합니다.',
                  positive: canUse,
                ),
                const OpsDivider(),
                const _ConnectionInfoRow(
                  icon: Icons.cloud_download_rounded,
                  title: '설정 출처',
                  value: '본사 내려받기',
                  description: '서버 초대와 업무 채널 링크를 내려받은 설정에서 사용합니다.',
                  positive: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        CommonSideDockSection(
          title: '연결 단계',
          subtitle: '필요한 항목을 선택하면 외부 앱으로 바로 연결합니다.',
          order: 2,
          child: OpsDockListSurface(
            child: Column(
              children: [
                _ConnectionActionRow(
                  index: 1,
                  icon: Icons.download_for_offline_rounded,
                  title: 'Discord 앱 준비',
                  description: '앱이 설치되어 있으면 열고, 없으면 설치 페이지로 이동합니다.',
                  detail: _openingApp ? 'Discord 연결 상태를 확인하고 있습니다.' : 'Discord 앱 열기 또는 설치',
                  enabled: canUse && !_openingApp,
                  complete: false,
                  busy: _openingApp,
                  onTap: _openingApp ? null : _openDiscordOrStore,
                ),
                const OpsDivider(),
                _ConnectionActionRow(
                  index: 2,
                  icon: Icons.group_add_rounded,
                  title: '서버 초대',
                  description: '본사에서 내려받은 Discord 초대 링크를 사용합니다.',
                  detail: _inviteValid ? _inviteUrl : '초대 링크가 없습니다.',
                  enabled: canUse && _inviteValid,
                  complete: _inviteValid,
                  busy: false,
                  onTap: _inviteValid ? _openInvite : null,
                ),
                const OpsDivider(),
                _ConnectionActionRow(
                  index: 3,
                  icon: Icons.forum_rounded,
                  title: '업무 채널',
                  description: '본사에서 내려받은 Discord 업무 채널 링크를 사용합니다.',
                  detail: _channelValid ? _channelUrl : '업무 채널 링크가 없습니다.',
                  enabled: canUse && _channelValid,
                  complete: _channelValid,
                  busy: false,
                  onTap: _channelValid ? _openChannel : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionInfoRow extends StatelessWidget {
  const _ConnectionInfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.description,
    required this.positive,
  });

  final IconData icon;
  final String title;
  final String value;
  final String description;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tone = positive ? tokens.success : tokens.warning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 19, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: text.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      child: Text(
                        value,
                        key: ValueKey<String>(value),
                        style: text.bodySmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionActionRow extends StatefulWidget {
  const _ConnectionActionRow({
    required this.index,
    required this.icon,
    required this.title,
    required this.description,
    required this.detail,
    required this.enabled,
    required this.complete,
    required this.busy,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final String title;
  final String description;
  final String detail;
  final bool enabled;
  final bool complete;
  final bool busy;
  final Future<void> Function()? onTap;

  @override
  State<_ConnectionActionRow> createState() => _ConnectionActionRowState();
}

class _ConnectionActionRowState extends State<_ConnectionActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.enabled && widget.onTap != null;
    final statusColor = widget.complete ? tokens.success : tokens.iconSecondary;

    return AnimatedOpacity(
      opacity: enabled || widget.busy ? 1 : .56,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => widget.onTap!() : null,
          onHighlightChanged: enabled
              ? (value) {
                  if (!mounted) return;
                  setState(() => _pressed = value);
                }
              : null,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
            curve: CommonUiMotion.enter,
            color: _pressed
                ? tokens.surfaceSelected.withOpacity(.58)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: widget.complete
                        ? tokens.accentContainer
                        : tokens.surfaceSelected,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: .88, end: 1)
                                .animate(animation),
                            child: child,
                          ),
                        ),
                        child: Icon(
                          widget.complete ? Icons.check_rounded : widget.icon,
                          key: ValueKey<bool>(widget.complete),
                          size: 20,
                          color: widget.complete
                              ? tokens.accent
                              : tokens.iconSecondary,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 1,
                        child: Text(
                          '${widget.index}',
                          style: text.labelSmall?.copyWith(
                            color: tokens.textSecondary,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: text.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.description,
                        style: text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SelectionArea(
                        child: Text(
                          widget.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: widget.complete
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                            height: 1.25,
                            fontWeight: widget.complete
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  height: 38,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .88, end: 1)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: widget.busy
                          ? SizedBox(
                              key: const ValueKey<String>('busy'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: tokens.accent,
                              ),
                            )
                          : Icon(
                              enabled
                                  ? Icons.chevron_right_rounded
                                  : widget.complete
                                      ? Icons.check_circle_rounded
                                      : Icons.info_outline_rounded,
                              key: ValueKey<String>(
                                'trailing_${enabled}_${widget.complete}',
                              ),
                              size: 21,
                              color: enabled
                                  ? tokens.accent
                                  : statusColor,
                            ),
                    ),
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
