import 'package:flutter/material.dart';
import 'login_form.dart';
import 'login_controller.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = LoginController(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: LoginForm(controller: controller),
          ),
        ),
      ),
    );
  }
}