// lib/screens/.../home_dash_board_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

// ✅ 역할별로 다른 문서철 바텀시트를 사용하기 위해 두 파일 모두 import
import 'lite_dashboard_punch_recorder_section.dart';
import 'documents/lite_leader_document_box_sheet.dart';
import 'documents/lite_fielder_document_box_sheet.dart';

import 'memo/lite_dash_memo.dart';

class HomeDashBoardBottomSheet extends StatefulWidget {
  const HomeDashBoardBottomSheet({super.key});

  @override
  State<HomeDashBoardBottomSheet> createState() => _HomeDashBoardBottomSheetState();
}

class _HomeDashBoardBottomSheetState extends State<HomeDashBoardBottomSheet> {
  static const String screenTag = 'DashBoard B';

  bool _layerHidden = true;

  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
            const TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Consumer<UserState>(
            builder: (context, userState, _) {
              final areaState = context.read<AreaState>();

              // ✅ 로그인한 유저의 role 기반으로 fieldCommon 여부 판단
              final dynamic rawRole = userState.user?.role;
              final String role = rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
              final bool isFieldCommon = role == 'fieldCommon';

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
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildScreenTag(context),
                    const SizedBox(height: 16),

                    /// ⬇️ 출퇴근 기록기 카드 (HomeUserInfoCard 대체)
                    DashboardInsidePunchRecorderSection(
                      userId: userState.name,
                      userName: userState.name,
                      area: areaState.currentArea,
                      division: areaState.currentDivision,
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          _layerHidden ? Icons.layers : Icons.layers_clear,
                        ),
                        label: Text(
                          _layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기',
                        ),
                        style: _layerToggleBtnStyle(),
                        onPressed: () => setState(() => _layerHidden = !_layerHidden),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sticky_note_2_rounded),
                              label: const Text('메모'),
                              style: _memoBtnStyle(),
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
                              icon: const Icon(Icons.folder_open),
                              label: const Text('서류함 열기'),
                              style: _docBoxBtnStyle(),
                              onPressed: () {
                                // ✅ role 이 fieldCommon 이면 필드 전용 문서철
                                //    그 외에는 리더 전용 문서철
                                if (isFieldCommon) {
                                  openFielderDocumentBox(context);
                                } else {
                                  openLeaderDocumentBox(context);
                                }
                              },
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

ButtonStyle _layerToggleBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _memoBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _docBoxBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
