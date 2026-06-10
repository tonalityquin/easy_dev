import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/di/routes.dart';
import '../../../account/applications/user_state.dart';
import '../../../camera/photo_transfer_mail_page.dart';
import '../../../dev/application/area_state.dart';
import '../../../selector/sheets/service_bottom_sheet.dart';
import '../../../../shared/secondary/pages/secondary_page.dart';
import '../../../../shared/sheet_tool/document_box_action_executor.dart';
import '../../../../shared/sheet_tool/fielder_document_box_sheet.dart';
import '../../../../shared/sheet_tool/leader_document_box_sheet.dart';
import '../../widgets/widgets/info/my_info_dialog.dart';

class OpsDashboardBottomSheet extends StatefulWidget {
  const OpsDashboardBottomSheet({
    super.key,
    required this.modeLabel,
    required this.modeIcon,
    required this.punchRecorderBuilder,
  });

  final String modeLabel;
  final IconData modeIcon;
  final Widget Function(
    BuildContext context,
    UserState userState,
    AreaState areaState,
  ) punchRecorderBuilder;

  @override
  State<OpsDashboardBottomSheet> createState() => _OpsDashboardBottomSheetState();
}

class _OpsDashboardBottomSheetState extends State<OpsDashboardBottomSheet> {
  bool _actionsMode = false;
  ScrollController? _sheetScrollController;

  bool _isFieldCommon(UserState userState) {
    final dynamic rawRole = userState.session?.role;
    final role = rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
    return role == 'fieldCommon';
  }

  void _scrollSheetTopSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _sheetScrollController;
      if (controller == null || !controller.hasClients) return;
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openActionsMode() {
    if (_actionsMode) return;
    setState(() => _actionsMode = true);
    _scrollSheetTopSoon();
  }

  void _closeActionsMode() {
    if (!_actionsMode) return;
    setState(() => _actionsMode = false);
    _scrollSheetTopSoon();
  }

  Future<void> _closeCurrentSheetAndRun(
    BuildContext context,
    Future<void> Function(BuildContext rootContext) action,
  ) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      await Future<void>.delayed(Duration.zero);
    }
    await action(rootNavigator.context);
  }

  Future<void> _openDocumentBox(
    BuildContext context, {
    required bool isFieldCommon,
  }) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      final action = isFieldCommon
          ? await openFielderDocumentBox(rootContext)
          : await openLeaderDocumentBox(rootContext);
      if (action == null) return;
      await executeDocumentBoxAction(rootContext, action);
    });
  }

  Future<void> _openServiceSettings(BuildContext context) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      await ServiceBottomSheet.show(context: rootContext);
    });
  }

  Future<void> _openCommunity(BuildContext context) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      await Navigator.of(rootContext, rootNavigator: true).pushNamed(AppRoutes.communityStub);
    });
  }

  void _openPhotoTransfer(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    rootNav.push(MaterialPageRoute(builder: (_) => const PhotoTransferMailPage()));
  }

  void _openSecondary(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
    rootNav.push(MaterialPageRoute(builder: (_) => const SecondaryPage()));
  }

  String _roleLabel(UserState userState) {
    final dynamic rawRole = userState.session?.role;
    final role = rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
    if (role.isEmpty) return '권한 미확인';
    if (role == 'fieldCommon') return '현장 공통';
    if (role == 'leader') return '리더';
    if (role == 'manager') return '관리자';
    return role;
  }

  Widget _metricChip({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.34),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cs.outlineVariant.withOpacity(.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (tt.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required UserState userState,
    required AreaState areaState,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final area = areaState.currentArea.trim().isEmpty ? '지역 미설정' : areaState.currentArea.trim();
    final division = areaState.currentDivision.trim().isEmpty ? '구역 미설정' : areaState.currentDivision.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(widget.modeIcon, color: cs.onPrimary, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '대시보드',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (tt.titleLarge ?? const TextStyle(fontSize: 20)).copyWith(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.25,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _modeBadge(context),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (tt.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(
                              color: cs.onInverseSurface.withOpacity(.76),
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _metricChip(
                  context: context,
                  label: '근무자',
                  value: userState.name.trim().isEmpty ? '미확인' : userState.name.trim(),
                  icon: Icons.badge_rounded,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                _metricChip(
                  context: context,
                  label: '구역',
                  value: division,
                  icon: Icons.map_rounded,
                  color: cs.secondary,
                ),
                const SizedBox(width: 8),
                _metricChip(
                  context: context,
                  label: '권한',
                  value: _roleLabel(userState),
                  icon: Icons.verified_user_rounded,
                  color: cs.tertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBadge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.20)),
      ),
      child: Text(
        widget.modeLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
          color: cs.onInverseSurface,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }

  Widget _dragHandle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 56,
        height: 5,
        decoration: BoxDecoration(
          color: cs.outlineVariant.withOpacity(.86),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildPunchPanel(
    BuildContext context, {
    required UserState userState,
    required AreaState areaState,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(.60)),
      ),
      child: widget.punchRecorderBuilder(context, userState, areaState),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (tt.titleSmall ?? const TextStyle(fontSize: 15)).copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: -.15,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
          ),
          child: Text(
            value,
            style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _openActionsButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openActionsMode,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.primary.withOpacity(.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.open_in_full_rounded, color: cs.primary, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '운영 액션 열기',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (tt.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  List<_DashboardAction> _actions(BuildContext context, bool isFieldCommon) {
    final cs = Theme.of(context).colorScheme;
    final actions = <_DashboardAction>[
      _DashboardAction(
        label: '내 정보',
        description: '계정과 근무 정보를 확인합니다',
        icon: Icons.person_rounded,
        color: cs.primary,
        onPressed: () => showMyInfoDialog(context: context),
      ),
      _DashboardAction(
        label: 'Community',
        description: '운영 커뮤니티로 이동합니다',
        icon: Icons.groups_rounded,
        color: cs.secondary,
        onPressed: () => _openCommunity(context),
      ),
      _DashboardAction(
        label: '설정',
        description: '서비스 설정을 조정합니다',
        icon: Icons.settings_rounded,
        color: cs.primary,
        emphasized: true,
        onPressed: () => _openServiceSettings(context),
      ),
      _DashboardAction(
        label: '사진 전송',
        description: '사진 전송 메일 화면으로 이동합니다',
        icon: Icons.photo_camera_back_rounded,
        color: cs.secondary,
        onPressed: () => _openPhotoTransfer(context),
      ),
      _DashboardAction(
        label: '서류함 열기',
        description: isFieldCommon ? '현장 공통 서류함을 엽니다' : '리더 서류함을 엽니다',
        icon: Icons.folder_open_rounded,
        color: cs.tertiary,
        onPressed: () => _openDocumentBox(context, isFieldCommon: isFieldCommon),
      ),
    ];

    if (!isFieldCommon) {
      actions.add(
        _DashboardAction(
          label: '보조 페이지 열기',
          description: '운영 관리 콘솔로 이동합니다',
          icon: Icons.open_in_new_rounded,
          color: cs.primary,
          onPressed: () => _openSecondary(context),
        ),
      );
    }

    return actions;
  }

  Widget _actionsHeader(BuildContext context, int actionCount) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.tune_rounded, color: cs.onPrimary, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '운영 액션',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (tt.titleLarge ?? const TextStyle(fontSize: 20)).copyWith(
                color: cs.onInverseSurface,
                fontWeight: FontWeight.w900,
                letterSpacing: -.25,
                height: 1,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: cs.onInverseSurface.withOpacity(.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.onInverseSurface.withOpacity(.20)),
            ),
            child: Text(
              '$actionCount개',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
                color: cs.onInverseSurface,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: '대시보드로 돌아가기',
            onPressed: _closeActionsMode,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _dashboardContent(
    BuildContext context, {
    required UserState userState,
    required AreaState areaState,
  }) {
    return Column(
      key: const ValueKey<String>('dashboard-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dragHandle(context),
        const SizedBox(height: 14),
        _buildHeader(context, userState: userState, areaState: areaState),
        const SizedBox(height: 14),
        _sectionTitle(context, '출퇴근 기록', '최우선'),
        const SizedBox(height: 8),
        _buildPunchPanel(context, userState: userState, areaState: areaState),
        const SizedBox(height: 14),
        _sectionTitle(context, '운영 액션', '동일 우선순위'),
        const SizedBox(height: 8),
        _openActionsButton(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _actionsContent(BuildContext context, bool isFieldCommon) {
    final actions = _actions(context, isFieldCommon);
    return Column(
      key: const ValueKey<String>('dashboard-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dragHandle(context),
        const SizedBox(height: 14),
        _actionsHeader(context, actions.length),
        const SizedBox(height: 14),
        _sectionTitle(context, '액션 목록', '동일 우선순위'),
        const SizedBox(height: 8),
        for (var i = 0; i < actions.length; i++) ...[
          _DashboardActionTile(action: actions[i]),
          if (i != actions.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _body(
    BuildContext context, {
    required ScrollController scrollController,
    required UserState userState,
    required AreaState areaState,
    required bool isFieldCommon,
  }) {
    _sheetScrollController = scrollController;
    final content = _actionsMode
        ? _actionsContent(context, isFieldCommon)
        : _dashboardContent(
            context,
            userState: userState,
            areaState: areaState,
          );

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final position = Tween<Offset>(
            begin: const Offset(.07, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: position,
              child: child,
            ),
          );
        },
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_actionsMode,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_actionsMode) _closeActionsMode();
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.95,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(.18),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.70))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Consumer2<UserState, AreaState>(
                  builder: (context, userState, areaState, _) {
                    final isFieldCommon = _isFieldCommon(userState);
                    return _body(
                      context,
                      scrollController: scrollController,
                      userState: userState,
                      areaState: areaState,
                      isFieldCommon: isFieldCommon,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
class _DashboardAction {
  const _DashboardAction({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool emphasized;
}

class _DashboardActionTile extends StatelessWidget {
  const _DashboardActionTile({required this.action});

  final _DashboardAction action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final borderColor = action.emphasized ? action.color.withOpacity(.62) : cs.outlineVariant.withOpacity(.68);
    final backgroundColor = action.emphasized ? action.color.withOpacity(.10) : cs.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: action.color.withOpacity(.13),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: action.color.withOpacity(.23)),
                ),
                child: Icon(action.icon, color: action.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (tt.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      action.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant.withOpacity(.78)),
            ],
          ),
        ),
      ),
    );
  }
}
