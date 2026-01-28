import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

import '../../../../common_package/memo_package/dash_memo.dart';
import '../../../../common_package/sheet_tool/fielder_document_box_sheet.dart';
import '../../../../common_package/sheet_tool/leader_document_box_sheet.dart';
import 'widgets/minor_dashboard_punch_recorder_section.dart';

import 'package:easydev/screens/common_package/camera_package/photo_transfer_mail_page.dart';
import 'package:easydev/screens/secondary_page.dart';

class MinorHomeDashBoardBottomSheet extends StatefulWidget {
  const MinorHomeDashBoardBottomSheet({super.key});

  @override
  State<MinorHomeDashBoardBottomSheet> createState() => _MinorHomeDashBoardBottomSheetState();
}

class _MinorHomeDashBoardBottomSheetState extends State<MinorHomeDashBoardBottomSheet> {
  static const String screenTag = 'DashBoard B';

  bool _layerHidden = true;

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
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
    final dynamic rawRole = userState.user?.role;
    final String role =
    rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
    return role == 'fieldCommon';
  }

  void _onPhotoTransferPressed(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    rootNav.push(MaterialPageRoute(builder: (_) => const PhotoTransferMailPage()));
  }

  void _onOpenSecondaryPressed(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    rootNav.push(MaterialPageRoute(builder: (_) => const SecondaryPage()));
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
            border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
          ),
          child: Consumer<UserState>(
            builder: (context, userState, _) {
              final areaState = context.read<AreaState>();
              final bool isFieldCommon = _isFieldCommon(userState);

              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 60,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildScreenTag(context),
                    const SizedBox(height: 16),

                    MinorDashboardPunchRecorderSection(
                      userId: userState.name,
                      userName: userState.name,
                      area: areaState.currentArea,
                      division: areaState.currentDivision,
                    ),

                    const SizedBox(height: 16),
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
                              icon: const Icon(Icons.sticky_note_2_rounded),
                              label: const Text('메모'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () async {
                                await DashMemo.init();
                                DashMemo.mountIfNeeded();
                                await DashMemo.togglePanel();
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.photo_camera_back_rounded),
                              label: const Text('사진 전송'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () => _onPhotoTransferPressed(context),
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('서류함 열기'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () {
                                if (isFieldCommon) {
                                  openFielderDocumentBox(context);
                                } else {
                                  openLeaderDocumentBox(context);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('보조 페이지 열기'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () => _onOpenSecondaryPressed(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    if (_layerHidden) const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

ButtonStyle _outlinedSurfaceBtnStyle(BuildContext context, {double height = 55}) {
  final cs = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    minimumSize: Size.fromHeight(height),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed)
          ? cs.outlineVariant.withOpacity(0.12)
          : null,
    ),
  );
}
