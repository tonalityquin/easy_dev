import 'package:flutter/material.dart';

import '../../../../../routes.dart';
import '../double_login_controller.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
///
/// - 텍스트/단색 로고 PNG가 “검정 픽셀로 고정”인 경우
///   다크/브랜드 배경에서 그대로 쓰면 안 보일 수 있습니다.
/// - 해결: 알파(투명도)를 마스크로 사용해서 ColorScheme 기반으로 tint.
/// - preferred(primary)가 배경과 대비가 부족하면 fallback(onBackground)로 폴백.
///
/// NOTE: 로고/큰 텍스트는 minContrast=3.0 기준을 기본으로 둡니다.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}

/// ✅ (신규) “단색/검정 고정” PNG 로고를 테마에 맞춰 tint 하는 위젯
///
/// - assetPath/height를 required로 두어
///   private 위젯에서 optional param 미사용 경고가 나지 않게 함.
/// - BlendMode.srcIn: 원본 RGB는 버리고 알파만 유지한 채 tint 색을 적용.
class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
  });

  final String assetPath;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ✅ 실제 화면 배경 기준(가장 근접한 값)
    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: cs.primary, // 브랜드 색 우선
      fallback: cs.onBackground, // 대비 부족 시 가독성 우선
      minContrast: 3.0,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

class DoubleLoginForm extends StatefulWidget {
  final DoubleLoginController controller;

  const DoubleLoginForm({super.key, required this.controller});

  @override
  State<DoubleLoginForm> createState() => _DoubleLoginFormState();
}

class _DoubleLoginFormState extends State<DoubleLoginForm> {
  late final DoubleLoginController _controller;

  // ✅ WorkFlow A login 텍스트 대신 표시할 “첨부 이미지” 에셋 경로
  static const String _kWorkFlowTagAsset = 'assets/images/pelican_text.png';

  // ✅ (신규) 태그 이미지 “보이는 크기”만 키우는 배율
  // - 여기 숫자를 바꾸면 “화면에서 보이는 크기”가 변합니다.
  // - 레이아웃(세로 점유 높이)은 거의 변하지 않습니다.
  static const double _kTagScale = 3.0;

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
      'WorkFlow A 로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'lite_login',
        'action': 'login',
      },
    );

    _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'lite_login',
        'asset': 'assets/images/ParkinWorkin_logo.png',
        'action': 'tap',
      },
    );
  }

  void _onPelicanLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'lite_login',
        'asset': 'assets/images/ParkinWorkin_text.png',
        'action': 'back_to_selector',
        'to': AppRoutes.selector,
      },
    );

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
          (route) => false,
    );
  }

  ThemeData _buildBrandLocalTheme(ThemeData baseTheme) {
    final cs = baseTheme.colorScheme;

    // ✅ “브랜드 테마 수정안” 반영:
    // - 모든 색은 ColorScheme 기반
    // - 그림자도 primary tint 대신 cs.shadow 기반(중립)
    return baseTheme.copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size.fromHeight(55),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 1.5,
          shadowColor: cs.shadow.withOpacity(0.18),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: cs.primary,
          splashFactory: InkRipple.splashFactory,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primaryContainer.withOpacity(.35),
        selectionHandleColor: cs.primary,
      ),
    );
  }

  TextStyle _screenTagStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant.withOpacity(0.80),
      letterSpacing: 0.2,
    );
  }

  /// ✅ (신규) “WorkFlow A login” 텍스트 위치에 pelican_text.png를 넣되,
  /// 레이아웃 높이는 기존 텍스트 수준으로 유지하고(=아래가 안 밀리게),
  /// 보이는 크기만 Transform.scale로 확대합니다.
  Widget _buildWorkflowTagImage(BuildContext context) {
    final tagStyle = _screenTagStyle(context);
    final tagFontSize = (tagStyle.fontSize ?? 11).toDouble();

    // ✅ 레이아웃이 점유하는 높이: 기존 텍스트 체감치(폰트+여유) 수준
    final tagLayoutHeight = tagFontSize + 3.0;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Semantics(
          label: 'screen_tag: WorkFlow A login image',
          child: SizedBox(
            height: tagLayoutHeight, // ✅ 레이아웃 점유 높이 고정(세로 길이 영향 최소화)
            child: Align(
              alignment: Alignment.centerLeft,
              child: Transform.scale(
                scale: _kTagScale, // ✅ “보이는 크기”만 키움 (여기 조절)
                alignment: Alignment.centerLeft,
                child: _BrandTintedLogo(
                  assetPath: _kWorkFlowTagAsset,
                  height: tagLayoutHeight, // ✅ 내부 Image 높이도 레이아웃 기준값 사용
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final themed = _buildBrandLocalTheme(baseTheme);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          data: themed,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ✅ (변경) WorkFlow A login 텍스트 → pelican_text.png (레이아웃 고정 + 스케일 확대)
                _buildWorkflowTagImage(context),

                // ✅ 상단 로고 tint 적용
                GestureDetector(
                  onTap: _onTopCompanyLogoTapped,
                  child: SizedBox(
                    height: 360,
                    child: Center(
                      child: _BrandTintedLogo(
                        assetPath: 'assets/images/ParkinWorkin_logo.png',
                        height: 360,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _controller.nameController,
                  focusNode: _controller.nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.phoneFocus),
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
                  onChanged: (value) =>
                      _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.passwordFocus),
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
                      icon: Icon(_controller.obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _controller.togglePassword()),
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
                      _controller.isLoading ? '로딩 중...' : '로그인',
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
                      // ✅ 하단 텍스트 로고 tint 적용
                      child: _BrandTintedLogo(
                        assetPath: 'assets/images/ParkinWorkin_text.png',
                        height: 80,
                      ),
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
