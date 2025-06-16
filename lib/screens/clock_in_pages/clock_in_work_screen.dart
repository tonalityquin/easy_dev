import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../../../states/user/user_state.dart';
import 'clock_in_controller.dart';
import 'widgets/plate_count_widget.dart';
import 'widgets/work_button_widget.dart';
import 'widgets/user_info_card.dart';

class ClockInWorkScreen extends StatefulWidget {
  const ClockInWorkScreen({super.key});

  @override
  State<ClockInWorkScreen> createState() => _ClockInWorkScreenState();
}

class _ClockInWorkScreenState extends State<ClockInWorkScreen> {
  final controller = ClockInController();

  @override
  void initState() {
    super.initState();
    controller.initialize(context);
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      await userState.clearUserToPhone();

      // ✅ 앱 종료
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            controller.redirectIfWorking(context, userState);
          }

          return SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 96),
                          SizedBox(
                            height: 120,
                            child: Image.asset('assets/images/belivus_logo.PNG'),
                          ),
                          const SizedBox(height: 96),
                          Center(
                            child: Text(
                              '출근 전 사용자 정보 확인',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const UserInfoCard(),
                          const PlateCountWidget(),
                          const SizedBox(height: 32),
                          WorkButtonWidget(controller: controller),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'logout') {
                        _handleLogout(context);
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
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
