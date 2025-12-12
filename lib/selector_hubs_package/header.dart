import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/snackbar_helper.dart';
import '../../utils/api/email_config.dart';
import '../../utils/app_exit_flag.dart';

// ⬅️ 오버레이 모드 설정
import '../../utils/overlay_mode_config.dart';

// ✅ commute_true_false Firestore 기록 On/Off(기기별, 기본 OFF + 유지)
import '../../utils/commute_true_false_mode_config.dart';

class Header extends StatefulWidget {
  const Header({super.key});

  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        _TopRow(
          expanded: _expanded,
          onToggle: _toggleExpanded,
        ),
        const SizedBox(height: 12),
        Text(
          '환영합니다',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '화살표 버튼을 누르면 해당 페이지로 진입합니다.',
          style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 상단 가로 레이아웃: [왼쪽 버튼(설정)] [배지(아이콘)] [오른쪽 버튼(앱 종료)]
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  // 앱 종료 처리
  Future<void> _exitApp(BuildContext context) async {
    AppExitFlag.beginExit();

    try {
      if (Platform.isAndroid) {
        try {
          if (await FlutterOverlayWindow.isActive()) {
            await FlutterOverlayWindow.closeOverlay();
          }
        } catch (_) {}

        bool running = false;
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {}

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('포그라운드 중지 실패(플러그인 반환값 false)'),
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('포그라운드 중지 실패: $e')),
            );
          }
          await Future.delayed(const Duration(milliseconds: 150));
        }

        await SystemNavigator.pop();
      } else {
        await SystemNavigator.pop();
      }
    } catch (e) {
      AppExitFlag.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('앱 종료 실패: $e')),
      );
    }
  }

  // “설정” 바텀시트 — Gmail(수신자만) + QuickOverlay 오버레이 권한 + 오버레이 모드(항상 노출) + commute_true_false 토글
  Future<void> _openSheetsLinkSheet(BuildContext context) async {
    // Gmail 수신자 로드 (To 만)
    final emailCfg = await EmailConfig.load();
    final mailToCtrl = TextEditingController(text: emailCfg.to);

    // 현재 오버레이 모드 로드
    OverlayMode currentOverlayMode = await OverlayModeConfig.getMode();

    // SharedPreferences 로드
    final prefs = await SharedPreferences.getInstance();

    // 오버레이 형태 기본값(초기 1회만 topHalf로 강제)
    final initialized = prefs.getBool('overlay_mode_initialized_v2') ?? false;
    if (!initialized) {
      currentOverlayMode = OverlayMode.topHalf;
      await OverlayModeConfig.setMode(OverlayMode.topHalf);
      await prefs.setBool('overlay_mode_initialized_v2', true);
    }

    // ✅ commute_true_false Firestore 기록 토글 로드 (기본 OFF)
    bool commuteTrueFalseEnabled = await CommuteTrueFalseModeConfig.isEnabled();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          maxChildSize: 1.0,
          minChildSize: 0.4,
          builder: (ctx, sc) {
            return StatefulBuilder(
              builder: (ctx, setSheetState) {
                // QuickOverlay 권한 섹션
                Widget buildOverlayPermissionSection() {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.bubble_chart_outlined,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '플로팅 버블(QuickOverlay) 권한',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '다른 앱 위에 플로팅 버블 또는 상단 포그라운드 패널(QuickOverlayHome)을 띄우기 위해서는 '
                          '안드로이드 “다른 앱 위에 표시” 권한이 필요합니다.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.info_outline),
                                onPressed: () async {
                                  if (!Platform.isAndroid) {
                                    if (!ctx.mounted) return;
                                    showFailedSnackbar(
                                      context,
                                      '안드로이드에서만 지원되는 기능입니다.',
                                    );
                                    return;
                                  }
                                  try {
                                    final granted = await FlutterOverlayWindow.isPermissionGranted();
                                    if (!ctx.mounted) return;
                                    if (granted) {
                                      showSelectedSnackbar(
                                        context,
                                        '이미 “다른 앱 위에 표시” 권한이 허용되어 있습니다.',
                                      );
                                    } else {
                                      showFailedSnackbar(
                                        context,
                                        '현재 “다른 앱 위에 표시” 권한이 허용되지 않았습니다.',
                                      );
                                    }
                                  } catch (e) {
                                    if (!ctx.mounted) return;
                                    showFailedSnackbar(
                                      context,
                                      '권한 상태를 확인하는 중 오류가 발생했습니다: $e',
                                    );
                                  }
                                },
                                label: const Text('현재 상태 확인'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.open_in_new_rounded),
                                onPressed: () async {
                                  if (!Platform.isAndroid) {
                                    if (!ctx.mounted) return;
                                    showFailedSnackbar(
                                      context,
                                      '안드로이드에서만 지원되는 기능입니다.',
                                    );
                                    return;
                                  }
                                  try {
                                    final already = await FlutterOverlayWindow.isPermissionGranted();
                                    if (already) {
                                      if (!ctx.mounted) return;
                                      showSelectedSnackbar(
                                        context,
                                        '이미 권한이 허용되어 있습니다.\n설정 앱에서 언제든지 변경할 수 있습니다.',
                                      );
                                      return;
                                    }

                                    final result = await FlutterOverlayWindow.requestPermission();

                                    if (!ctx.mounted) return;
                                    if (result == true) {
                                      showSuccessSnackbar(
                                        context,
                                        '권한이 허용되었습니다. 오버레이를 사용할 수 있습니다.',
                                      );
                                    } else {
                                      showFailedSnackbar(
                                        context,
                                        '권한을 허용하지 않았습니다.\n필요 시 “설정 > 다른 앱 위에 표시”에서 직접 허용해 주세요.',
                                      );
                                    }
                                  } catch (e) {
                                    if (!ctx.mounted) return;
                                    showFailedSnackbar(
                                      context,
                                      '권한 설정 화면을 여는 중 오류가 발생했습니다: $e',
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                ),
                                label: const Text('권한 설정 열기'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                // 오버레이 형태 선택 섹션 (✅ 항상 노출)
                Widget buildOverlayModeSection() {
                  String labelFor(OverlayMode mode) {
                    switch (mode) {
                      case OverlayMode.topHalf:
                        return '상단 50% 포그라운드';
                      case OverlayMode.bubble:
                        return '플로팅 버블';
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.view_sidebar_outlined,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '오버레이 형태 선택',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '앱이 백그라운드로 이동했을 때 사용할 오버레이 형태를 선택합니다.\n'
                          '하나만 선택되며, 선택된 모드만 실행/종료 조건을 공유합니다.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('플로팅 버블'),
                              selected: currentOverlayMode == OverlayMode.bubble,
                              onSelected: (selected) async {
                                if (!selected) return;
                                currentOverlayMode = OverlayMode.bubble;
                                setSheetState(() {});
                                await OverlayModeConfig.setMode(
                                  OverlayMode.bubble,
                                );

                                try {
                                  if (await FlutterOverlayWindow.isActive()) {
                                    await FlutterOverlayWindow.shareData('__mode:bubble__');
                                    await FlutterOverlayWindow.shareData('__collapse__');
                                  }
                                } catch (_) {}

                                if (!ctx.mounted) return;
                                showSuccessSnackbar(
                                  context,
                                  '플로팅 버블 모드가 선택되었습니다.',
                                );
                              },
                            ),
                            ChoiceChip(
                              label: const Text('상단 50% 포그라운드'),
                              selected: currentOverlayMode == OverlayMode.topHalf,
                              onSelected: (selected) async {
                                if (!selected) return;
                                currentOverlayMode = OverlayMode.topHalf;
                                setSheetState(() {});
                                await OverlayModeConfig.setMode(
                                  OverlayMode.topHalf,
                                );

                                try {
                                  if (await FlutterOverlayWindow.isActive()) {
                                    await FlutterOverlayWindow.shareData('__mode:topHalf__');
                                    await FlutterOverlayWindow.shareData('__collapse__');
                                  }
                                } catch (_) {}

                                if (!ctx.mounted) return;
                                showSuccessSnackbar(
                                  context,
                                  '상단 50% 포그라운드 모드가 선택되었습니다.',
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '현재 선택: ${labelFor(currentOverlayMode)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // ✅ commute_true_false Firestore 기록 On/Off 섹션
                Widget buildCommuteTrueFalseToggleSection() {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.cloud_upload_outlined,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '출근 시각 Firestore 기록(commute_true_false)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '이 설정은 “기기별(로컬)”로 저장됩니다.\n'
                          'ON이면 출근 버튼을 누를 때 commute_true_false 컬렉션에 출근 시각(Timestamp)을 기록합니다.\n'
                          'OFF이면 해당 Firestore 업데이트는 모두 건너뛰고, 로컬(SQLite) 기록만 수행합니다.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            commuteTrueFalseEnabled ? 'ON (기록함)' : 'OFF (기록 안 함)',
                          ),
                          subtitle: Text(
                            commuteTrueFalseEnabled
                                ? '출근 시 commute_true_false 업데이트가 실행됩니다.'
                                : '출근 시 commute_true_false 업데이트를 스킵합니다.',
                          ),
                          value: commuteTrueFalseEnabled,
                          onChanged: (v) async {
                            commuteTrueFalseEnabled = v;
                            setSheetState(() {});
                            await CommuteTrueFalseModeConfig.setEnabled(v);

                            if (!ctx.mounted) return;
                            showSuccessSnackbar(
                              context,
                              v
                                  ? '이 기기에서 commute_true_false 기록을 ON으로 설정했습니다.'
                                  : '이 기기에서 commute_true_false 기록을 OFF로 설정했습니다.',
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }

                // Gmail 수신자 섹션(To 만)
                Widget buildGmailSection() {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.mail_outline,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '메일 전송 설정 (수신자만)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '기본값으로 초기화',
                              onPressed: () async {
                                await EmailConfig.clear();
                                final cfg = await EmailConfig.load();
                                mailToCtrl.text = cfg.to;
                                if (!ctx.mounted) return;
                                showSelectedSnackbar(
                                  context,
                                  '수신자를 기본값(빈 값)으로 복원했습니다.',
                                );
                              },
                              icon: const Icon(
                                Icons.restore,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: mailToCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: '수신자(To)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                            helperText: '쉼표로 여러 명 입력 가능 (예: a@x.com, b@y.com)',
                          ),
                          onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: () async {
                                  final to = mailToCtrl.text.trim();
                                  if (!EmailConfig.isValidToList(to)) {
                                    if (!ctx.mounted) return;
                                    showFailedSnackbar(
                                      context,
                                      '수신자 이메일 형식을 확인해 주세요.',
                                    );
                                    return;
                                  }
                                  await EmailConfig.save(EmailConfig(to: to));
                                  if (!ctx.mounted) return;
                                  showSuccessSnackbar(
                                    context,
                                    '수신자 설정을 저장했습니다.',
                                  );
                                },
                                label: const Text('저장'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy_all_outlined),
                                onPressed: () async {
                                  final raw = 'To: ${mailToCtrl.text}';
                                  await Clipboard.setData(
                                    ClipboardData(text: raw),
                                  );
                                  if (!ctx.mounted) return;
                                  showSuccessSnackbar(
                                    context,
                                    '현재 수신자 설정을 복사했습니다.',
                                  );
                                },
                                label: const Text('설정 복사'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '※ 저장되는 항목은 수신자(To)뿐입니다. 메일 제목·본문은 경위서 화면에서 작성합니다.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  controller: sc,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune_rounded),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '서비스 설정',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          color: Colors.black.withOpacity(.08),
                        ),
                        const SizedBox(height: 16),

                        // 오버레이 권한 (누구나)
                        buildOverlayPermissionSection(),

                        // ✅ 오버레이 모드 (항상 노출)
                        buildOverlayModeSection(),

                        // commute_true_false 토글
                        buildCommuteTrueFalseToggleSection(),

                        // Gmail 수신자(To) 설정
                        buildGmailSection(),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AnimatedSide(
          show: expanded,
          axisAlignment: -1.0,
          child: FilledButton.icon(
            onPressed: () => _openSheetsLinkSheet(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('설정'),
          ),
        ),
        const SizedBox(width: 12),
        HeaderBadge(size: 64, ring: 3, onToggle: onToggle),
        const SizedBox(width: 12),
        _AnimatedSide(
          show: expanded,
          axisAlignment: 1.0,
          child: FilledButton.icon(
            onPressed: () async => _exitApp(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.power_settings_new),
            label: const Text('앱 종료'),
          ),
        ),
      ],
    );
  }
}

class _AnimatedSide extends StatelessWidget {
  const _AnimatedSide({
    required this.show,
    required this.child,
    this.axisAlignment = 0.0,
  });

  final bool show;
  final Widget child;
  final double axisAlignment;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          return FadeTransition(
            opacity: anim,
            child: SizeTransition(
              axis: Axis.horizontal,
              sizeFactor: anim,
              axisAlignment: axisAlignment,
              child: ClipRect(child: child),
            ),
          );
        },
        child: show
            ? Container(
                key: const ValueKey('side-on'),
                alignment: Alignment.center,
                child: child,
              )
            : const SizedBox.shrink(key: ValueKey('side-off')),
      ),
    );
  }
}

class HeaderBadge extends StatelessWidget {
  const HeaderBadge({
    super.key,
    this.size = 64,
    this.ring = 3,
    this.onToggle,
  });

  final double size;
  final double ring;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: .92, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: Padding(
            padding: EdgeInsets.all(ring),
            child: _HeaderBadgeInner(onToggle: onToggle),
          ),
        ),
      ),
    );
  }
}

class _HeaderBadgeInner extends StatefulWidget {
  const _HeaderBadgeInner({this.onToggle});

  final VoidCallback? onToggle;

  @override
  State<_HeaderBadgeInner> createState() => _HeaderBadgeInnerState();
}

class _HeaderBadgeInnerState extends State<_HeaderBadgeInner> with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _rotCtrl.forward(from: 0);
    widget.onToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  child: Center(
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _rotCtrl,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: const Icon(
                        Icons.dashboard_customize_rounded,
                        color: Colors.black,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: cons.maxHeight * 0.12,
                left: cons.maxWidth * 0.22,
                right: cons.maxWidth * 0.22,
                child: IgnorePointer(
                  child: Container(
                    height: cons.maxHeight * 0.18,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
