import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import '../../../../widgets/navigation/secondary_mini_navigation.dart';
import 'dash_board_controller.dart';
import 'widgets/user_info_card.dart';
import 'widgets/break_button_widget.dart';
import 'widgets/work_button_widget.dart';

class DashBoardScreen extends StatelessWidget {
  const DashBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DashBoardController();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '대시보드',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                controller.logout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('로그아웃'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          )
        ],
      ),
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      '사용자 정보',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    UserInfoCard(userState: userState),
                    const SizedBox(height: 32),
                    BreakButtonWidget(controller: controller),
                    const SizedBox(height: 16),
                    WorkButtonWidget(controller: controller, userState: userState),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
