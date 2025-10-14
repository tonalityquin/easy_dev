// lib/offlines/login_package/service/sections/offline_login_form.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../../../routes.dart'; // ✅ AppRoutes 사용 (경로는 현재 파일 위치 기준)
import '../offline_login_controller.dart';

/// Hubs 카드 팔레트를 Theme에 실어 전달하기 위한 확장.
/// SelectorHubs에서 아래 확장을 Theme에 넣어주면 이 폼이 해당 값을 자동으로 사용합니다.
/// 예)
// Theme(
//   data: theme.copyWith(
//     extensions: <ThemeExtension<dynamic>>[
//       const HubCardsPalette(
//         offlinePrimary: Color(0xFFF4511E), // ← 오프라인 카드 base
//         offlineTint: Color(0xFFFFAB91),    // ← 오프라인 카드 light
//       ),
//     ],
//   ),
//   child: ...
// )
@immutable
class HubCardsPalette extends ThemeExtension<HubCardsPalette> {
  final Color? offlinePrimary; // 오프라인 카드 메인
  final Color? offlineTint;    // 오프라인 카드 틴트/보조

  const HubCardsPalette({this.offlinePrimary, this.offlineTint});

  @override
  HubCardsPalette copyWith({Color? offlinePrimary, Color? offlineTint}) {
    return HubCardsPalette(
      offlinePrimary: offlinePrimary ?? this.offlinePrimary,
      offlineTint: offlineTint ?? this.offlineTint,
    );
  }

  @override
  HubCardsPalette lerp(ThemeExtension<HubCardsPalette>? other, double t) {
    if (other is! HubCardsPalette) return this;
    return HubCardsPalette(
      offlinePrimary: Color.lerp(offlinePrimary, other.offlinePrimary, t),
      offlineTint: Color.lerp(offlineTint, other.offlineTint, t),
    );
  }
}

/// 폼 내부에서 사용할 팔레트 리졸버.
/// 1) Theme.extensions의 HubCardsPalette에서 색을 읽어오고
/// 2) 없으면 오프라인 서비스 카드 팔레트(주황 계열)로 폴백합니다.
class _OfflineCardPalette {
  final Color base;
  final Color tint;

  const _OfflineCardPalette({required this.base, required this.tint});

  // ⬇️ ParkingCard 팔레트와 동일하게 폴백 색상 적용
  static const Color _fallbackBase = Color(0xFFF4511E); // base (오프라인 카드)
  static const Color _fallbackTint = Color(0xFFFFAB91); // light(tint) (오프라인 카드)

  static _OfflineCardPalette of(BuildContext context) {
    final ext = Theme.of(context).extension<HubCardsPalette>();
    return _OfflineCardPalette(
      base: ext?.offlinePrimary ?? _fallbackBase,
      tint: ext?.offlineTint ?? _fallbackTint,
    );
  }
}

class OfflineLoginForm extends StatefulWidget {
  final OfflineLoginController controller;

  const OfflineLoginForm({super.key, required this.controller});

  @override
  State<OfflineLoginForm> createState() => _OfflineLoginFormState();
}

class _OfflineLoginFormState extends State<OfflineLoginForm> {
  late final OfflineLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller; // ✅ init은 상위(LoginScreen)에서만 수행
  }

  void _handleLogin() {
    // ✅ BuildContext와 setState를 둘 다 넘깁니다.
    _controller.login(context, setState);
  }

  void _onLoginButtonPressed() {
    if (!_controller.isLoading) {
      _handleLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final pal = _OfflineCardPalette.of(context); // ⬅ 오프라인 카드 색 추출

    final themed = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: pal.base,
        onPrimary: Colors.white,
        primaryContainer: pal.tint,
        onPrimaryContainer: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pal.base,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(55),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 1.5,
          shadowColor: pal.base.withOpacity(0.25),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: pal.base,
          splashFactory: InkRipple.splashFactory,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // 라벨/힌트 기본은 테마 그대로 두고, 포커스/아이콘 색만 액센트
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: pal.base, width: 1.6),
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.black.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(10),
        ),
        prefixIconColor: MaterialStateColor.resolveWith(
              (states) => states.contains(MaterialState.focused) ? pal.base : Colors.black54,
        ),
        suffixIconColor: MaterialStateColor.resolveWith(
              (states) => states.contains(MaterialState.focused) ? pal.base : Colors.black54,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: pal.base,
        selectionColor: pal.tint.withOpacity(.35),
        selectionHandleColor: pal.base,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          // ✅ 오프라인 로그인 폼에만 카드 팔레트 적용
          data: themed,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () {},
                  child: SizedBox(
                    height: 360,
                    child: Image.asset('assets/images/easyvalet_logo_car.png'),
                  ),
                ),

                const SizedBox(height: 12),

                // 이름
                TextField(
                  controller: _controller.nameController,
                  focusNode: _controller.nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.phoneFocus),
                  decoration: _controller
                      .inputDecoration(
                    label: "이름",
                    icon: Icons.person,
                  )
                      .copyWith(
                    hintText: 'tester', // ⬅ 힌트 추가
                  ),
                ),
                const SizedBox(height: 16),

                // 전화번호
                TextField(
                  controller: _controller.phoneController,
                  focusNode: _controller.phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) =>
                      _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_controller.passwordFocus),
                  decoration: _controller
                      .inputDecoration(
                    label: "전화번호",
                    icon: Icons.phone,
                  )
                      .copyWith(
                    hintText: '01012345678', // ⬅ 힌트 추가
                  ),
                ),
                const SizedBox(height: 16),

                // 비밀번호
                TextField(
                  controller: _controller.passwordController,
                  focusNode: _controller.passwordFocus,
                  obscureText: _controller.obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _onLoginButtonPressed(),
                  decoration: _controller
                      .inputDecoration(
                    label: "비밀번호(5자리 이상)",
                    icon: Icons.lock,
                    suffixIcon: IconButton(
                      icon: Icon(_controller.obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _controller.togglePassword()),
                      tooltip: _controller.obscurePassword ? '표시' : '숨기기',
                    ),
                  )
                      .copyWith(
                    hintText: '12345', // ⬅ 힌트 추가
                  ),
                ),

                const SizedBox(height: 32),

                // ▶ 팔레트 반영된 기본 ElevatedButtonTheme 사용
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(
                      _controller.isLoading ? '로딩 중...' : '오프라인 로그인',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    onPressed:
                    _controller.isLoading ? null : _onLoginButtonPressed,
                  ),
                ),

                const SizedBox(height: 1),

                // ▼ 펠리컨: 탭하면 LoginSelectorPage로 복귀
                Center(
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.selector, (route) => false),
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
