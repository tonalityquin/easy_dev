import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            controller.redirectIfWorking(context, userState);
          }

          return SafeArea(
            child: SingleChildScrollView(
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
                      Text(
                        '출근 전 사용자 정보 확인',
                        style: Theme.of(context).textTheme.titleLarge,
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
          );
        },
      ),
    );
  }
}
