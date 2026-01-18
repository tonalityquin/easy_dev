import 'package:flutter/material.dart';

import '../../../../../routes.dart';
import '../../../../../theme.dart';
import '../minor_login_controller.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class MinorLoginForm extends StatefulWidget {
  final MinorLoginController controller;

  const MinorLoginForm({super.key, required this.controller});

  @override
  State<MinorLoginForm> createState() => _MinorLoginFormState();
}

class _MinorLoginFormState extends State<MinorLoginForm> {
  late final MinorLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  void _handleLogin() {
    _controller.login(setState);
  }

  void _onLoginButtonPressed() {
    if (_controller.isLoading) return;

    _trace(
      '마이너 로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'minor_login',
        'action': 'login',
      },
    );

    _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'minor_login',
        'asset': 'assets/images/easyvalet_logo_car.png',
        'action': 'tap',
      },
    );
  }

  void _onPelicanLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'minor_login',
        'asset': 'assets/images/pelican.png',
        'action': 'back_to_selector',
        'to': AppRoutes.selector,
      },
    );

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    final palette = AppCardPalette.of(context);
    // ✅ minor 색상만 반영 (UI 레이아웃은 그대로)
    final base = palette.minorBase;
    final light = palette.minorLight;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          data: baseTheme.copyWith(
            colorScheme: baseTheme.colorScheme.copyWith(
              primary: base,
              onPrimary: Colors.white,
              primaryContainer: light,
              onPrimaryContainer: Colors.white,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: base,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(55),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 1.5,
                shadowColor: base.withOpacity(0.25),
              ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: base,
                splashFactory: InkRipple.splashFactory,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: base, width: 1.6),
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIconColor: MaterialStateColor.resolveWith(
                    (states) => states.contains(MaterialState.focused) ? base : Colors.black54,
              ),
              suffixIconColor: MaterialStateColor.resolveWith(
                    (states) => states.contains(MaterialState.focused) ? base : Colors.black54,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: base,
              selectionColor: light.withOpacity(.35),
              selectionHandleColor: base,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Semantics(
                      label: 'screen_tag: minor login',
                      child: const Text(
                        'minor login',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),

                GestureDetector(
                  onTap: _onTopCompanyLogoTapped,
                  child: SizedBox(
                    height: 360,
                    child: Image.asset('assets/images/easyvalet_logo_car.png'),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _controller.nameController,
                  focusNode: _controller.nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.phoneFocus),
                  decoration: _controller.inputDecoration(
                    label: "이름",
                    icon: Icons.person,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _controller.phoneController,
                  focusNode: _controller.phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) => _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.passwordFocus),
                  decoration: _controller.inputDecoration(
                    label: "전화번호",
                    icon: Icons.phone,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _controller.passwordController,
                  focusNode: _controller.passwordFocus,
                  obscureText: _controller.obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _onLoginButtonPressed(),
                  decoration: _controller.inputDecoration(
                    label: "비밀번호(5자리 이상)",
                    icon: Icons.lock,
                    suffixIcon: IconButton(
                      icon: Icon(_controller.obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _controller.togglePassword()),
                      tooltip: _controller.obscurePassword ? '표시' : '숨기기',
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(
                      _controller.isLoading ? '로딩 중...' : '마이너 로그인',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
                  ),
                ),

                const SizedBox(height: 1),

                Center(
                  child: InkWell(
                    onTap: _onPelicanLogoTapped,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 80,
                      child: Image.asset('assets/images/pelican.png'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
