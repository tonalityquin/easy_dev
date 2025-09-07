import 'package:flutter/material.dart';

class ErrorMessageText extends StatelessWidget {
  final String? message;

  const ErrorMessageText({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Text(
      message!,
      style: const TextStyle(color: Colors.red),
    );
  }
}
