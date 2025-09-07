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
import '../states/pad_mode_state.dart';

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
      color: Colors.transparent,
      child: InkWell(
        onTap: isAreaSelectable ? () => _openTopNavDialog(context) : null,
        splashColor: Colors.grey.withOpacity(0.2),
        highlightColor: Colors.grey.withOpacity(0.1),
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

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final isSmallPad = dialogCtx.watch<PadModeState>().isSmall;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.9,
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

                  const SizedBox(height: 16),
                  // 패드 모드 섹션
                  Row(
                    children: const [
                      Icon(Icons.dialpad, size: 18, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('패드 모드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Big Pad 버튼 (기본값)
                  _PadModeButton(
                    label: 'Big Pad 모드',
                    subtitle: '좌: 출차요청 목록  ·  우: 검색/키패드',
                    icon: Icons.grid_view_rounded,
                    selected: !isSmallPad,
                    onPressed: () {
                      dialogCtx.read<PadModeState>().setMode(PadMode.big);
                      Navigator.of(dialogCtx).pop();
                      showSuccessSnackbar(context, 'Big Pad 모드로 전환되었습니다.');
                    },
                  ),
                  const SizedBox(height: 8),

                  // Small Pad 버튼 (키패드 100%)
                  _PadModeButton(
                    label: 'Small Pad 모드',
                    subtitle: '키패드 화면 100%  ·  결과는 다이얼로그 표시',
                    icon: Icons.dialpad_rounded,
                    selected: isSmallPad,
                    onPressed: () {
                      dialogCtx.read<PadModeState>().setMode(PadMode.small);
                      Navigator.of(dialogCtx).pop();
                      showSuccessSnackbar(context, 'Small Pad 모드로 전환되었습니다.');
                    },
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),

                  const SizedBox(height: 16),

                  // 로그아웃 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('로그아웃'),
                      onPressed: () async {
                        // 다이얼로그 닫고 로그아웃 진행
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

                  // 닫기
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

          // Foreground service 중지
          await FlutterForegroundTask.stopService();

          // 근무 상태 갱신(필요 시)
          await userState.isHeWorking();
          await Future.delayed(const Duration(seconds: 1));

          // 로컬 상태/저장소 초기화
          await userState.clearUserToPhone();
        },
      );

      if (!context.mounted) return;

      // 로그인 화면으로 안전하게 라우팅 (기존 스택 제거)
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);

      showSuccessSnackbar(context, '로그아웃 되었습니다.');
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }
  }
}

class _PadModeButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _PadModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      backgroundColor: selected ? Colors.indigo.withOpacity(0.08) : Colors.white,
      foregroundColor: Colors.black87,
      side: BorderSide(color: selected ? Colors.indigo : Colors.grey.shade400, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return OutlinedButton(
      style: style,
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(icon, color: selected ? Colors.indigo : Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.indigo.shade700 : Colors.black87,
                    )),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? Colors.indigo : Colors.grey,
            size: 20,
          ),
        ],
      ),
    );
  }
}
