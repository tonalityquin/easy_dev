import 'package:flutter/material.dart';
import '../dash_board_controller.dart';

class BreakButtonWidget extends StatelessWidget {
  final DashBoardController controller;

  const BreakButtonWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => controller.recordBreakTime(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 55,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF81C784), Color(0xFF43A047)], // 연한 초록 -> 진한 초록
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.15 * 255).round()),
              blurRadius: 6,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.coffee, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '휴게 사용 확인',
                style: TextStyle(
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
