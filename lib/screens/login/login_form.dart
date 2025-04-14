import 'package:flutter/material.dart';
import 'login_controller.dart';

class LoginForm extends StatefulWidget {
  final LoginController controller;

  const LoginForm({super.key, required this.controller});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 96),
        SizedBox(height: 120, child: Image.asset('assets/images/belivus_logo.PNG')),
        const SizedBox(height: 96),
        TextField(
          controller: _controller.nameController,
          focusNode: _controller.nameFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.phoneFocus),
          decoration: _controller.inputDecoration(label: "이름", icon: Icons.person),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller.phoneController,
          focusNode: _controller.phoneFocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.passwordFocus),
          decoration: _controller.inputDecoration(label: "전화번호", icon: Icons.phone),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller.passwordController,
          focusNode: _controller.passwordFocus,
          obscureText: _controller.obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
          decoration: _controller.inputDecoration(
            label: "비밀번호(5자리 이상)",
            icon: Icons.lock,
            suffixIcon: IconButton(
              icon: Icon(_controller.obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _controller.togglePassword()),
            ),
          ),
        ),
        const SizedBox(height: 32),
        InkWell(
          onTap: _controller.isLoading ? null : _handleLogin,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Container(
              key: ValueKey<bool>(_controller.isLoading),
              height: 55,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F93E6), Color(0xFF1976D2)],
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
                child: _controller.isLoading
                    ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  "로그인",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleLogin() {
    _controller.login(setState);
  }
}
