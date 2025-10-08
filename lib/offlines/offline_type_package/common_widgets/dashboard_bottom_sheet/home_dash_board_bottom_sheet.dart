// lib/screens/.../home_dash_board_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

import '../../../../utils/external_openers.dart';
import 'home_dash_board_controller.dart';
import 'widgets/home_user_info_card.dart';
import 'widgets/home_break_button_widget.dart';

class HomeDashBoardBottomSheet extends StatefulWidget {
  const HomeDashBoardBottomSheet({super.key});

  @override
  State<HomeDashBoardBottomSheet> createState() => _HomeDashBoardBottomSheetState();
}

class _HomeDashBoardBottomSheetState extends State<HomeDashBoardBottomSheet> {
  // true = 숨김(기본), false = 펼침
  bool _layerHidden = true;

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
                    const SizedBox(height: 24),
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
                          // 1) 휴게 사용 확인 (기존 위젯 재사용)
                          HomeBreakButtonWidget(controller: controller),
                          const SizedBox(height: 16),

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

                          // 4) Gmail 열기
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.email),
                              label: const Text('Gmail 열기'),
                              style: _gmailBtnStyle(),
                              onPressed: () => openGmailInbox(context),
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

ButtonStyle _gmailBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
