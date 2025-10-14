// lib/screens/.../HqDashBoardPage.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

import '../../../../utils/external_openers.dart';
import '../../../../utils/logout_helper.dart';
import 'home_dash_board_controller.dart';
import 'widgets/home_user_info_card.dart';
import 'widgets/home_break_button_widget.dart';

class HqDashBoardPage extends StatefulWidget {
  const HqDashBoardPage({super.key});

  @override
  State<HqDashBoardPage> createState() => _HqDashBoardPageState();
}

class _HqDashBoardPageState extends State<HqDashBoardPage> {
  // true = 숨김(기본), false = 펼침
  bool _layerHidden = true;

  @override
  Widget build(BuildContext context) {
    final controller = HomeDashBoardController();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1) 휴게 사용 확인
                      HomeBreakButtonWidget(controller: controller),
                      const SizedBox(height: 16),

                      // 2) 퇴근하기 (명시 버튼) — 근무 중/아님에 따라 내부에서 처리
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('퇴근하기'),
                          style: _clockOutBtnStyle(),
                          onPressed: () =>
                              controller.handleWorkStatus(userState, context),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2.5) 로그아웃
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('로그아웃'),
                          style: _logoutBtnStyle(),
                          onPressed: () => LogoutHelper.logoutAndGoToLogin(context),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3) Gmail 열기
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.email),
                          label: const Text('Gmail 열기'),
                          style: _gmailBtnStyle(),
                          onPressed: () => openGmailInbox(context),
                        ),
                      ),
                    ],
                  ),
                ),

                // 접힘 상태일 때 하단 여백
                if (_layerHidden) const SizedBox(height: 16),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
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

ButtonStyle _logoutBtnStyle() {
  // 로그아웃은 중립 톤(회색 보더) 유지
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
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
