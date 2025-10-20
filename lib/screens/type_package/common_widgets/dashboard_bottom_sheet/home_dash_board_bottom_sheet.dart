// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/home_dash_board_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/secondary/secondary_info.dart'; // 🔎 RoleType 사용

import 'home_dash_board_controller.dart';
import 'widgets/home_user_info_card.dart';
import 'widgets/home_break_button_widget.dart';
// HomeWorkButtonWidget는 이번 요구사항(퇴근하기 단일 버튼)에서 사용하지 않으므로 제거
import 'widgets/home_show_report_dialog.dart';

// ✅ 서류함 바텀시트 오픈 (같은 폴더)
import 'document_box_sheet.dart';

// ✅ 신규: 대시보드 전용 메모 + 플로팅 버블
import 'memo/dash_memo.dart';

class HomeDashBoardBottomSheet extends StatefulWidget {
  const HomeDashBoardBottomSheet({super.key});

  @override
  State<HomeDashBoardBottomSheet> createState() => _HomeDashBoardBottomSheetState();
}

class _HomeDashBoardBottomSheetState extends State<HomeDashBoardBottomSheet> {
  // 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'DashBoard B';

  // true = 숨김(기본), false = 펼침
  bool _layerHidden = true;

  // 좌측 상단(11시) 고정 태그
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

    return IgnorePointer( // 드래그/스크롤 제스처 간섭 방지
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
    final controller = HomeDashBoardController();

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
              // ✅ 현재 로그인 유저의 RoleType 감지
              final roleType = RoleType.fromName(userState.role);
              final isFieldCommon = roleType == RoleType.fieldCommon;

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

                    // ⬇️ 좌측 상단(11시) 화면 태그
                    const SizedBox(height: 4),
                    _buildScreenTag(context),

                    const SizedBox(height: 16),
                    const HomeUserInfoCard(),
                    const SizedBox(height: 16),

                    // 레이어(토글) 버튼: 기본 true(숨김) → 누르면 false(펼침)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                        label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
                        style: _layerToggleBtnStyle(),
                        onPressed: () => setState(() => _layerHidden = !_layerHidden),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 숨김/펼침 영역
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState:
                      _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          // 0) 메모 (신규) — 휴게 버튼 위에 위치
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sticky_note_2_rounded),
                              label: const Text('메모'),
                              style: _memoBtnStyle(),
                              onPressed: () async {
                                // 필요 시 지연 초기화 + 오버레이 부착
                                await DashMemo.init();
                                DashMemo.mountIfNeeded();
                                await DashMemo.togglePanel();
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 1) 휴게 사용 확인 (기존 위젯 재사용)
                          HomeBreakButtonWidget(controller: controller),
                          const SizedBox(height: 16),

                          // 2) 보고 작성 — ❗ fieldCommon 역할이면 숨김
                          if (!isFieldCommon) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.assignment),
                                label: const Text('보고 작성'),
                                style: _reportBtnStyle(),
                                onPressed: () => showHomeReportDialog(context),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 3) 퇴근하기 (명시 버튼) — 근무 중/아님에 따라 내부에서 처리
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.exit_to_app),
                              label: const Text('퇴근하기'),
                              style: _clockOutBtnStyle(),
                              onPressed: () => controller.handleWorkStatus(userState, context),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 4) 서류함 열기 — 사용자 전용 인벤토리(바텀시트) 열기
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('서류함 열기'),
                              style: _docBoxBtnStyle(),
                              onPressed: () => openDocumentBox(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 접힘 상태일 때 하단 여백
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
  // 토글 버튼도 공통 톤 유지(화이트 + 블랙)
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
  // 메모 버튼도 동일 톤
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _reportBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _clockOutBtnStyle() {
  // 눈에 띄도록 경고톤 보더만 살짝 진하게(실수 방지 목적)
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.redAccent, width: 1.0),
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
