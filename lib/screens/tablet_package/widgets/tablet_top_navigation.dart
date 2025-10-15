import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../states/area/area_state.dart';
import '../../../widgets/tts_filter_sheet.dart';
import '../states/tablet_pad_mode_state.dart';

// ⬇️ TTS 사용자 필터
import '../../../utils/tts/tts_user_filters.dart';
// ⬇️ 로그아웃 공통 헬퍼
import '../../../utils/logout_helper.dart';

// ✅ 앱 isolate/Chat/Plate TTS 동기화
import '../../../utils/tts/chat_tts_listener_service.dart';
import '../../../utils/tts/plate_tts_listener_service.dart';

// ✅ 출차 요청 구독 토글을 위해 PlateState/PlateType/스낵바
import '../../../states/plate/plate_state.dart';
import '../../../enums/plate_type.dart';
import '../../../utils/snackbar_helper.dart';

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

    // ✅ Busy 상태를 안전하게 유지하기 위한 Notifier (StatefulBuilder 리빌드에도 보존)
    final depBusy = ValueNotifier<bool>(false);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white, // 다이얼로그 배경 흰색
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              // ✅ 오버플로 방지: 머리/꼬리는 고정, 본문은 Expanded+Scroll
              child: StatefulBuilder(
                builder: (innerCtx, setSB) {
                  final plateState = innerCtx.watch<PlateState>();

                  Future<void> _toggleDepartureSubscribe() async {
                    if (depBusy.value) return;
                    depBusy.value = true;
                    try {
                      final isSubscribedDeparture = plateState.isSubscribed(PlateType.departureRequests);
                      if (!isSubscribedDeparture) {
                        // 📱 태블릿 전용 전용 메서드 사용
                        await Future.sync(() => plateState.tabletSubscribeDeparture());
                        final currentArea = plateState.currentArea;
                        showSuccessSnackbar(
                          innerCtx,
                          '✅ [출차 요청] 구독 시작됨\n지역: ${currentArea.isEmpty ? "미지정" : currentArea}',
                        );
                      } else {
                        await Future.sync(() => plateState.tabletUnsubscribeDeparture());
                        final unsubscribedArea =
                            plateState.getSubscribedArea(PlateType.departureRequests) ?? '알 수 없음';
                        showSelectedSnackbar(
                          innerCtx,
                          '⏹ [출차 요청] 구독 해제됨\n지역: $unsubscribedArea',
                        );
                      }
                    } catch (e) {
                      showFailedSnackbar(innerCtx, '작업 실패: $e');
                    } finally {
                      depBusy.value = false;
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ---------- 헤더(고정) ----------
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

                      // ---------- 본문(스크롤 가능) ----------
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                        '현재 지역: ${(area.trim().isNotEmpty) ? area : "지역 없음"}',
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

                              // 🔊 음성 알림(TTS) 설정 섹션
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '음성 알림',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // ✅ [출차 요청 구독] 토글 버튼 (TTS 설정 버튼 상단)
                              Selector<PlateState, bool>(
                                selector: (_, s) => s.isSubscribed(PlateType.departureRequests),
                                builder: (ctx, isSubscribedDeparture, __) {
                                  return ValueListenableBuilder<bool>(
                                    valueListenable: depBusy,
                                    builder: (_, busy, __) {
                                      return SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: busy ? null : _toggleDepartureSubscribe,
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(double.infinity, 48),
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.black,
                                            elevation: 0,
                                            side: BorderSide(
                                              color: isSubscribedDeparture ? Colors.blue : Colors.grey,
                                              width: 1.0,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (busy)
                                                const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              else
                                                Icon(
                                                  isSubscribedDeparture
                                                      ? Icons.notifications_active_outlined
                                                      : Icons.notifications_off_outlined,
                                                ),
                                              const SizedBox(width: 8),
                                              Text(
                                                isSubscribedDeparture ? '출차 요청 구독 해제' : '출차 요청 구독 시작',
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),

                              const SizedBox(height: 8),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.volume_up_outlined),
                                  label: const Text('TTS 설정'),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 48),
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    side: const BorderSide(color: Colors.grey, width: 1.0),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () async {
                                    // 먼저 현재 다이얼로그 닫기
                                    Navigator.of(dialogCtx).pop();

                                    // 시트 열기
                                    await _openTtsFilterSheet(context);

                                    // ✅ 시트에서 저장된 최신 필터를 앱/FG 둘 다에 즉시 동기화
                                    final currentArea = context.read<AreaState>().currentArea;
                                    final filters = await TtsUserFilters.load();

                                    // ✅ Chat TTS 마스터 on/off 반영
                                    try {
                                      await ChatTtsListenerService.setEnabled(filters.chat);
                                    } catch (_) {}

                                    // ✅ Plate TTS 마스터 on/off + 앱 isolate 필터 즉시 반영
                                    try {
                                      final masterOn =
                                          filters.parking || filters.departure || filters.completed;
                                      await PlateTtsListenerService.setEnabled(masterOn);
                                      PlateTtsListenerService.updateFilters(filters); // (앱 isolate)
                                    } catch (_) {}

                                    // ✅ FG isolate에도 최신 필터 전달
                                    if (currentArea.isNotEmpty) {
                                      FlutterForegroundTask.sendDataToTask({
                                        'area': currentArea,
                                        'ttsFilters': filters.toMap(),
                                      });
                                    }
                                  },
                                ),
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
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ---------- 푸터(고정) ----------
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          child: const Text('닫기'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openTtsFilterSheet(BuildContext context) async {
    // 바텀시트 열기 (SafeArea & 둥근 모서리)
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TtsFilterSheet(),
    );
    // 저장은 시트 내부에서 하도록 가정
  }

  Future<void> _logout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
      // 목적지 미지정 → 기본(허브 선택)으로 이동
    );
  }
}
