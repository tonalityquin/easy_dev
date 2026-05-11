import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../app/di/routes.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/selector/sheets/service_bottom_sheet.dart';
import '../../../../../shared/secondary/pages/secondary_page.dart';
import '../../../../shared/sheet_tool/document_box_action_executor.dart';
import '../../../../shared/sheet_tool/fielder_document_box_sheet.dart';
import '../../../../shared/sheet_tool/leader_document_box_sheet.dart';
import '../../../camera/photo_transfer_mail_page.dart';
import '../../widgets/productivity_sheet.dart';
import 'widgets/triple_dashboard_punch_recorder_section.dart';

class TripleHomeDashBoardBottomSheet extends StatefulWidget {
  const TripleHomeDashBoardBottomSheet({super.key});

  @override
  State<TripleHomeDashBoardBottomSheet> createState() =>
      _TripleHomeDashBoardBottomSheetState();
}

class _TripleHomeDashBoardBottomSheetState
    extends State<TripleHomeDashBoardBottomSheet> {
  static const String screenTag = 'DashBoard B';

  bool _layerHidden = true;

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseText = Theme.of(context).textTheme.labelSmall;

    final style = (baseText ??
            TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ))
        .copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: $screenTag',
            child: Text(screenTag, style: style),
          ),
        ),
      ),
    );
  }

  bool _isFieldCommon(UserState userState) {
    final dynamic rawRole = userState.session?.role;
    final String role =
        rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
    return role == 'fieldCommon';
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

  Future<void> _openMemoSheet(BuildContext context) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      await ProductivitySheet.init();
      ProductivitySheet.mountIfNeeded();
      await ProductivitySheet.openPanel(tab: ProductivitySheetTab.memo);
    });
  }

  Future<void> _openServiceSettings(BuildContext context) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      await ServiceBottomSheet.show(
        context: rootContext,
      );
    });
  }

  void _onPhotoTransferPressed(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);

    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    rootNav.push(
      MaterialPageRoute(builder: (_) => const PhotoTransferMailPage()),
    );
  }

  void _onOpenSecondaryPressed(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);

    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    rootNav.push(
      MaterialPageRoute(builder: (_) => const SecondaryPage()),
    );
  }

  Future<void> _onOpenCommunityPressed(BuildContext context) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      await Navigator.of(rootContext, rootNavigator: true).pushNamed(
        AppRoutes.communityStub,
      );
    });
  }

  Future<void> _onOpenFaqPressed(BuildContext context) async {
    await _closeCurrentSheetAndRun(context, (rootContext) async {
      await Navigator.of(rootContext, rootNavigator: true).pushNamed(
        AppRoutes.faq,
      );
    });
  }

  Widget _buildFixedHeader(
    BuildContext context, {
    required ColorScheme cs,
    required UserState userState,
    required AreaState areaState,
  }) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 60,
          height: 6,
          decoration: BoxDecoration(
            color: cs.outlineVariant.withOpacity(0.75),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        _buildScreenTag(context),
        const SizedBox(height: 16),
        TripleDashboardInsidePunchRecorderSection(
          userId: userState.name,
          userName: userState.name,
          area: areaState.currentArea,
          division: areaState.currentDivision,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildScrollableBody(
    BuildContext context, {
    required ScrollController scrollController,
    required ColorScheme cs,
    required bool isFieldCommon,
  }) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
              label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
              style: _outlinedSurfaceBtnStyle(context, height: 48),
              onPressed: () => setState(() => _layerHidden = !_layerHidden),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _layerHidden
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.groups_rounded),
                    label: const Text('Community'),
                    style: _outlinedSurfaceBtnStyle(context, height: 55),
                    onPressed: () => _onOpenCommunityPressed(context),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.help_center_rounded),
                    label: const Text('FAQ'),
                    style: _outlinedSurfaceBtnStyle(context, height: 55),
                    onPressed: () => _onOpenFaqPressed(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sticky_note_2_rounded),
                    label: const Text('메모'),
                    style: _outlinedSurfaceBtnStyle(context, height: 55),
                    onPressed: () => _openMemoSheet(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('설정'),
                    style: _outlinedSurfaceBtnStyle(
                      context,
                      height: 55,
                      borderColor: cs.primary.withOpacity(0.85),
                      pressedOverlayColor: cs.primary.withOpacity(0.10),
                    ),
                    onPressed: () => _openServiceSettings(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_camera_back_rounded),
                    label: const Text('사진 전송'),
                    style: _outlinedSurfaceBtnStyle(context, height: 55),
                    onPressed: () => _onPhotoTransferPressed(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('서류함 열기'),
                    style: _outlinedSurfaceBtnStyle(context, height: 55),
                    onPressed: () => _openDocumentBox(
                      context,
                      isFieldCommon: isFieldCommon,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('보조 페이지 열기'),
                    style: _outlinedSurfaceBtnStyle(context, height: 55),
                    onPressed: () => _onOpenSecondaryPressed(context),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (_layerHidden) const SizedBox(height: 16),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Consumer<UserState>(
              builder: (context, userState, _) {
                final areaState = context.read<AreaState>();
                final bool isFieldCommon = _isFieldCommon(userState);

                return Column(
                  children: [
                    _buildFixedHeader(
                      context,
                      cs: cs,
                      userState: userState,
                      areaState: areaState,
                    ),
                    Expanded(
                      child: _buildScrollableBody(
                        context,
                        scrollController: scrollController,
                        cs: cs,
                        isFieldCommon: isFieldCommon,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

ButtonStyle _outlinedSurfaceBtnStyle(
  BuildContext context, {
  double height = 55,
  Color? borderColor,
  Color? pressedOverlayColor,
}) {
  final cs = Theme.of(context).colorScheme;

  final Color effectiveBorder =
      borderColor ?? cs.outlineVariant.withOpacity(0.85);
  final Color effectiveOverlay =
      pressedOverlayColor ?? cs.outlineVariant.withOpacity(0.12);

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    minimumSize: Size.fromHeight(height),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: effectiveBorder, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
      (states) =>
          states.contains(MaterialState.pressed) ? effectiveOverlay : null,
    ),
  );
}
