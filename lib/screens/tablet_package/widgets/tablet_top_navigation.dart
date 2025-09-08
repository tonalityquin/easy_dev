// lib/screens/tablet_pages/widgets/tablet_top_navigation.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../routes.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/blocking_dialog.dart';
import '../../../utils/snackbar_helper.dart';
import '../states/tablet_pad_mode_state.dart';

class TabletTopNavigation extends StatelessWidget {
  final bool isAreaSelectable;

  const TabletTopNavigation({
    super.key,
    this.isAreaSelectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final selectedArea = context.watch<AreaState>().currentArea;

    return Material(
      color: Colors.white, // 네비게이션 배경 흰색
      child: InkWell(
        onTap: isAreaSelectable ? () => _openTopNavDialog(context) : null,
        splashColor: Colors.grey.withOpacity(0.12),
        highlightColor: Colors.grey.withOpacity(0.06),
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.car, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 6),
              Text(
                (selectedArea.trim().isNotEmpty) ? selectedArea : '지역 없음',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (isAreaSelectable) ...[
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTopNavDialog(BuildContext context) async {
    final area = context.read<AreaState>().currentArea;
    final padMode = context.read<TabletPadModeState>().mode;

    Widget modeButton({
      required PadMode target,
      required String title,
      required String subtitle,
      required IconData icon,
      required Color background, // 각 버튼 고유 배경색
    }) {
      final bool selected = padMode == target;
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () {
            context.read<TabletPadModeState>().setMode(target);
            Navigator.of(context, rootNavigator: true).pop();
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            side: BorderSide(color: selected ? Colors.blue : Colors.grey.shade400, width: selected ? 1.5 : 1.0),
            backgroundColor: background,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.blueAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: Colors.blue),
              ],
            ],
          ),
        ),
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white, // ✅ 다이얼로그 배경 흰색 고정
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더
                  Row(
                    children: [
                      const Icon(CupertinoIcons.car, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      const Text(
                        '상단 메뉴',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 현재 지역 표시
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.map, size: 18, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '현재 지역: ${(area.trim().isNotEmpty) ? area : '지역 없음'}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 화면 모드 섹션 타이틀
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '화면 모드',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ▶ 각 버튼 다른 배경색
                  modeButton(
                    target: PadMode.big,
                    title: 'Big Pad (기본)',
                    subtitle: '왼쪽: 출차 요청 / 오른쪽: 검색 + 키패드(하단 45%)',
                    icon: Icons.dashboard_customize_outlined,
                    background: Colors.blue.shade50,
                  ),
                  const SizedBox(height: 8),
                  modeButton(
                    target: PadMode.small,
                    title: 'Small Pad',
                    subtitle: '왼쪽 유지 / 오른쪽: 키패드가 패널 높이 100%',
                    icon: Icons.keyboard_alt_outlined,
                    background: Colors.green.shade50,
                  ),
                  const SizedBox(height: 8),
                  modeButton(
                    target: PadMode.show,
                    title: 'Show',
                    subtitle: '왼쪽 패널만 전체 화면(출차 요청 차량만 표시)',
                    icon: Icons.view_list_outlined,
                    background: Colors.amber.shade50,
                  ),

                  const SizedBox(height: 20),

                  // 로그아웃 버튼 (기존 스타일 유지)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('로그아웃'),
                      onPressed: () async {
                        Navigator.of(dialogCtx).pop();
                        await _logout(context);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        side: const BorderSide(color: Colors.grey, width: 1.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('닫기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await runWithBlockingDialog(
        context: context,
        message: '로그아웃 중입니다...',
        task: () async {
          final userState = Provider.of<UserState>(context, listen: false);
          await FlutterForegroundTask.stopService();
          await userState.isHeWorking();
          await Future.delayed(const Duration(seconds: 1));
          await userState.clearUserToPhone();
        },
      );

      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.serviceLogin, (route) => false);
      showSuccessSnackbar(context, '로그아웃 되었습니다.');
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }
  }
}
