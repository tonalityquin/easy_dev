import 'package:flutter/material.dart';
import '../../../../../states/user/user_state.dart';
import '../dash_board_controller.dart';

class WorkButtonWidget extends StatelessWidget {
  final DashBoardController controller;
  final UserState userState;

  const WorkButtonWidget({
    super.key,
    required this.controller,
    required this.userState,
  });

  @override
  Widget build(BuildContext context) {
    final isWorking = userState.isWorking;
    final label = isWorking ? '퇴근하기' : '출근하기';
    final icon = isWorking ? Icons.logout : Icons.login;
    final colors = isWorking ? [Colors.redAccent, Colors.deepOrange] : [Colors.green.shade400, Colors.teal];

    return InkWell(
      onTap: () => controller.handleWorkStatus(userState, context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 55,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(38, 0, 0, 0),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
