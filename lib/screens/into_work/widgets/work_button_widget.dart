import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import '../into_work_controller.dart';

class WorkButtonWidget extends StatefulWidget {
  final IntoWorkController controller;

  const WorkButtonWidget({super.key, required this.controller});

  @override
  State<WorkButtonWidget> createState() => _WorkButtonWidgetState();
}

class _WorkButtonWidgetState extends State<WorkButtonWidget> {
  bool _isLoading = false;

  void _toggleLoading() {
    setState(() {
      _isLoading = !_isLoading;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;

    final label = isWorking ? '출근 중' : '출근하기';
    final icon = Icons.login;
    final colors = isWorking
        ? [Colors.grey.shade400, Colors.grey.shade600]
        : [Colors.green.shade400, Colors.teal];

    return InkWell(
      onTap: _isLoading || isWorking
          ? null
          : () => widget.controller.handleWorkStatus(context, userState, _toggleLoading),
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
              color: Colors.black.withAlpha(30),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              : Row(
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
