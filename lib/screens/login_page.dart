import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/user/user_state.dart';
import '../states/area/area_state.dart';
import '../repositories/user/user_repository.dart';
import '../utils/show_snackbar.dart';
import 'dart:io';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkLoginState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _checkLoginState() async {
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.loadUserToLogIn();

    if (userState.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  String? _validatePhone(String phone) {
    final trimmedPhone = phone.trim();
    final phoneRegex = RegExp(r'^[0-9]{10,11}$');
    if (trimmedPhone.isEmpty) return '전화번호를 입력해주세요.';
    if (!phoneRegex.hasMatch(trimmedPhone)) return '유효한 전화번호를 입력해주세요.';
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 5) return '비밀번호는 최소 5자 이상이어야 합니다.';
    return null;
  }

  Future<bool> _isInternetConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _login() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = _passwordController.text.trim();

    final phoneError = _validatePhone(phone);
    final passwordError = _validatePassword(password);

    if (name.isEmpty) {
      showSnackbar(context, '이름을 입력해주세요.');
      return;
    }
    if (phoneError != null) {
      showSnackbar(context, phoneError);
      return;
    }
    if (passwordError != null) {
      showSnackbar(context, passwordError);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    if (!await _isInternetConnected()) {
      Navigator.of(context).pop();
      showSnackbar(context, '인터넷 연결이 필요합니다.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (user != null) {
        if (user.name == name && user.password == password) {
          final userState = Provider.of<UserState>(context, listen: false);
          final areaState = Provider.of<AreaState>(context, listen: false);

          final updatedUser = user.copyWith(isSaved: true);
          userState.updateUserCard(updatedUser);
          areaState.updateArea(updatedUser.area);

          Navigator.of(context).pop(); // close loading
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.of(context).pop();
          showSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
      } else {
        Navigator.of(context).pop();
        showSnackbar(context, '해당 전화번호가 등록되지 않았습니다.');
      }
    } catch (e) {
      Navigator.of(context).pop();
      showSnackbar(context, '로그인 실패: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 96),
                SizedBox(
                  height: 120,
                  child: Image.asset('assets/images/belivus_logo.PNG'),
                ),
                const SizedBox(height: 96),
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
                  decoration: const InputDecoration(
                    labelText: "이름",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                  decoration: const InputDecoration(
                    labelText: "전화번호",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: "비밀번호(5자리 이상)",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text("로그인"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
