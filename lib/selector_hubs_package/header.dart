// lib/screens/selector_hubs_package/header.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ▼ 추가: 시트 ID 관련 유틸 & 스낵바 헬퍼
import '../../utils/sheets_config.dart';
import '../../utils/snackbar_helper.dart';

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

  // 앱 종료 처리:
  // 1) Android: flutter_foreground_task가 실행 중이면 중지 시도 → 앱 종료
  // 2) 그 외: 바로 앱 종료 (iOS는 정책상 완전 종료가 보장되지 않을 수 있음)
  Future<void> _exitApp(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        bool running = false;
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) { /* 일부 기기에서 조회 실패 가능 → 무시 */ }

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('포그라운드 중지 실패(플러그인 반환값 false)')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('앱 종료 실패: $e')),
      );
    }
  }

  // ▼ 추가: “설정” 바텀시트 (최상단까지) — 두 시트(업로드/업무종료) 한 번에 관리
  Future<void> _openSheetsLinkSheet(BuildContext context) async {
    // 현재 저장된 값 선조회
    final commuteCurrent = await SheetsConfig.getCommuteSheetId();
    final endReportCurrent = await SheetsConfig.getEndReportSheetId();

    final commuteCtrl = TextEditingController(text: commuteCurrent ?? '');
    final endReportCtrl = TextEditingController(text: endReportCurrent ?? '');

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
            // StatefulBuilder로 내부 setState(시트 상태) 사용
            return StatefulBuilder(
              builder: (ctx, setSheetState) {
                // 공통 섹션 위젯 빌더
                Widget buildSheetSection({
                  required IconData icon,
                  required String title,
                  required TextEditingController controller,
                  required String? currentValue,
                  required Future<void> Function(String id) onSave,
                  required Future<void> Function() onClear,
                }) {
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
                              child: Icon(icon, size: 20, color: Colors.black87),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            // 현재값 복사 / 초기화
                            IconButton(
                              tooltip: '복사',
                              onPressed: (currentValue == null || currentValue.isEmpty)
                                  ? null
                                  : () async {
                                await Clipboard.setData(ClipboardData(text: currentValue));
                                if (!ctx.mounted) return;
                                showSuccessSnackbar(context, '현재 ID를 복사했습니다.');
                              },
                              icon: const Icon(Icons.copy_rounded, color: Colors.black87),
                            ),
                            IconButton(
                              tooltip: '초기화',
                              onPressed: (currentValue == null || currentValue.isEmpty)
                                  ? null
                                  : () async {
                                await onClear();
                                if (!ctx.mounted) return;
                                controller.text = '';
                                setSheetState(() {}); // 버튼 활성/비활성 갱신
                                showSelectedSnackbar(context, 'ID를 초기화했습니다.');
                              },
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.black87),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: controller,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: '스프레드시트 ID 또는 URL (붙여넣기 가능)',
                            helperText: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy_rounded),
                                onPressed: () async {
                                  final raw = controller.text.trim();
                                  if (raw.isEmpty) return;
                                  await Clipboard.setData(ClipboardData(text: raw));
                                  if (!ctx.mounted) return;
                                  showSuccessSnackbar(context, '입력값을 복사했습니다.');
                                },
                                label: const Text('입력값 복사'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.save),
                                onPressed: () async {
                                  final raw = controller.text.trim();
                                  if (raw.isEmpty) return;
                                  final id = SheetsConfig.extractSpreadsheetId(raw);
                                  await onSave(id);
                                  if (!ctx.mounted) return;
                                  showSuccessSnackbar(context, '저장되었습니다.');
                                  // 상단 현재값/버튼 상태 갱신
                                  setSheetState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                ),
                                label: const Text('저장'),
                              ),
                            ),
                          ],
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
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, // 키보드 패딩
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 헤더줄
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
                        Divider(height: 1, color: Colors.black.withOpacity(.08)),
                        const SizedBox(height: 16),

                        // 업로드용 Google Sheets
                        buildSheetSection(
                          icon: Icons.assignment_outlined,
                          title: '업로드용 Google Sheets',
                          controller: commuteCtrl,
                          currentValue: commuteCurrent,
                          onSave: (id) async {
                            await SheetsConfig.setCommuteSheetId(id);
                            // 최신 현재값으로 갱신
                            final cur = await SheetsConfig.getCommuteSheetId();
                            commuteCtrl.text = cur ?? '';
                          },
                          onClear: () async {
                            await SheetsConfig.clearCommuteSheetId();
                          },
                        ),

                        // 업무 종료 보고용 Google Sheets
                        buildSheetSection(
                          icon: Icons.assignment_turned_in_outlined,
                          title: '업무 종료 보고용 Google Sheets',
                          controller: endReportCtrl,
                          currentValue: endReportCurrent,
                          onSave: (id) async {
                            await SheetsConfig.setEndReportSheetId(id);
                            final cur = await SheetsConfig.getEndReportSheetId();
                            endReportCtrl.text = cur ?? '';
                          },
                          onClear: () async {
                            await SheetsConfig.clearEndReportSheetId();
                          },
                        ),
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
    // 버튼 자체가 가로로 줄 수 있도록 Flexible 로 감싸고,
    // 폭을 직접 애니메이션하지 않고 Size/Fade로 등장·퇴장시킵니다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 왼쪽: 설정 (바텀시트 열기)
        _AnimatedSide(
          show: expanded,
          axisAlignment: -1.0, // 왼쪽에서 펼쳐지는 느낌
          child: FilledButton.icon(
            onPressed: () => _openSheetsLinkSheet(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),       // 가로 최소=0으로 수축 허용
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('설정'),
          ),
        ),

        const SizedBox(width: 12),

        // 중앙 배지(아이콘). 탭하면 회전 + onToggle 호출로 좌/우 버튼 토글
        HeaderBadge(size: 64, ring: 3, onToggle: onToggle),

        const SizedBox(width: 12),

        // 오른쪽: 앱 종료 (포그라운드 서비스까지 종료)
        _AnimatedSide(
          show: expanded,
          axisAlignment: 1.0, // 오른쪽에서 펼쳐지는 느낌
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

/// 좌/우 버튼의 등장/퇴장 애니메이션
/// - 폭을 직접 0→확대하지 않고, SizeTransition(가로) + Fade로 처리
/// - Flexible 로 감싸 Row 내에서 수축/확장을 허용
class _AnimatedSide extends StatelessWidget {
  const _AnimatedSide({
    required this.show,
    required this.child,
    this.axisAlignment = 0.0, // -1.0(좌측), 1.0(우측), 0.0(중심)
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
              child: ClipRect(child: child), // 그려지는 영역을 안전하게 클립
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
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: Padding(
            padding: EdgeInsets.all(ring),           // ring 값 적용
            child: _HeaderBadgeInner(onToggle: onToggle), // 콜백 전달
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

class _HeaderBadgeInnerState extends State<_HeaderBadgeInner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // 회전 시간
    );
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _rotCtrl.forward(from: 0);     // 360도 회전
    widget.onToggle?.call();       // 좌/우 버튼 토글
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
              // 배지 전체 탭 → 회전 + 토글
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

              // 빛 반사 하이라이트(탭 방해 X)
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
