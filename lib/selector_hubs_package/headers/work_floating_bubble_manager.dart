// lib/selector_hubs_package/headers/work_floating_bubble_manager.dart
//
// 헤더에서 on/off 할 수 있는 플로팅 버블 구현부입니다.
// - 인앱 OverlayEntry 기반 버블(앱 안에서만 보이는 모드)
// - ANDROID 에서는 MethodChannel 을 통해 "앱 밖" 시스템 오버레이 버블도 지원하도록 확장했습니다.
// - 버블 안/밖에서 출근 / 퇴근 / 휴게 기록 버튼을 누르면 기존 컨트롤러 로직을 그대로 호출합니다.

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../states/user/user_state.dart';
import '../../utils/snackbar_helper.dart';
import '../../screens/commute_package/commute_inside_package/commute_inside_controller.dart';
import '../../screens/type_package/common_widgets/dashboard_bottom_sheet/home_dash_board_controller.dart';

/// 플로팅 버블 on/off 를 관리하는 싱글톤 매니저
class WorkFloatingBubbleManager {
  WorkFloatingBubbleManager._() {
    // 네이티브(시스템 버블)에서 오는 콜백 처리
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final WorkFloatingBubbleManager instance =
  WorkFloatingBubbleManager._();

  /// ANDROID 시스템 오버레이용 채널
  ///
  /// - Dart → Native:
  ///   - 'showBubble' : 시스템 버블 표시 요청
  ///   - 'hideBubble' : 시스템 버블 숨김 요청
  /// - Native → Dart:
  ///   - 'onClockIn'  : 시스템 버블에서 "출근" 버튼 눌림
  ///   - 'onClockOut' : 시스템 버블에서 "퇴근" 버튼 눌림
  ///   - 'onBreak'    : 시스템 버블에서 "휴게" 버튼 눌림
  ///   - 'onHide'     : 버블 닫기 요청
  static const MethodChannel _channel =
  MethodChannel('com.quintus.work_floating_bubble');

  OverlayEntry? _entry; // 인앱 버블용
  bool _systemShowing = false; // 시스템(앱 밖) 버블 표시 여부

  /// 출근/퇴근/휴게 로직에서 사용할 앱 쪽 BuildContext (Provider / Snackbar 접근용)
  BuildContext? _appContext;

  bool get isShowing => _systemShowing || _entry != null;

  /// 플로팅 버블 표시
  ///
  /// - ANDROID 인 경우:
  ///   1) 우선 네이티브 시스템 오버레이 버블 (앱 밖) 표시 시도
  ///   2) 실패하면 인앱 Overlay 로 폴백
  /// - 그 외 플랫폼: 인앱 Overlay 만 사용
  Future<bool> show(BuildContext context) async {
    // 출근/퇴근/휴게 로직에서 쓸 수 있도록 최신 context 저장
    _appContext = context;

    // 1) ANDROID 시스템 오버레이 시도
    if (Platform.isAndroid) {
      try {
        final ok = await _channel.invokeMethod<bool>('showBubble');
        if (ok == true) {
          _systemShowing = true;
          debugPrint('[WorkFloatingBubbleManager] 시스템 버블 표시 성공');
          return true;
        } else {
          debugPrint(
              '[WorkFloatingBubbleManager] 시스템 버블 표시 실패 (결과: $ok), 인앱 버블로 폴백');
        }
      } catch (e, st) {
        debugPrint(
            '[WorkFloatingBubbleManager] 시스템 버블 표시 중 예외 발생: $e\n$st\n→ 인앱 버블로 폴백합니다.');
      }
    }

    // 2) 인앱 Overlay 버블 (앱 안에서만 보임)
    if (_entry != null) {
      // 이미 떠 있으면 true
      return true;
    }

    final overlayState = Overlay.of(context, rootOverlay: true);
    if (overlayState == null) {
      debugPrint(
          '[WorkFloatingBubbleManager] OverlayState 를 찾지 못해 인앱 버블을 표시할 수 없습니다.');
      return false;
    }

    final rootContext = context;
    _entry = OverlayEntry(
      builder: (overlayContext) {
        return WorkFloatingBubbleOverlay(
          appContext: rootContext,
          onCloseRequested: hide,
        );
      },
    );

    overlayState.insert(_entry!);
    debugPrint('[WorkFloatingBubbleManager] 인앱 버블 표시');
    return true;
  }

  /// 플로팅 버블 숨김
  ///
  /// - 시스템 버블이 켜져 있으면 먼저 네이티브에 hideBubble 요청
  /// - 인앱 Overlay 버블이 있으면 제거
  Future<void> hide() async {
    // 1) 시스템 오버레이 버블 끄기
    if (_systemShowing && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('hideBubble');
        debugPrint('[WorkFloatingBubbleManager] 시스템 버블 숨김 요청 전송');
      } catch (e, st) {
        debugPrint(
            '[WorkFloatingBubbleManager] 시스템 버블 숨김 중 예외 발생: $e\n$st');
      } finally {
        _systemShowing = false;
      }
    }

    // 2) 인앱 Overlay 버블 제거
    final entry = _entry;
    if (entry != null) {
      entry.remove();
      _entry = null;
      debugPrint('[WorkFloatingBubbleManager] 인앱 버블 제거');
    }
  }

  /// 네이티브(시스템 버블)에서 들어오는 콜백 처리
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final ctx = _appContext;
    if (ctx == null) {
      debugPrint(
          '[WorkFloatingBubbleManager] _handleNativeCall: appContext 가 없어 호출을 처리할 수 없습니다. method=${call.method}');
      return null;
    }

    debugPrint('[WorkFloatingBubbleManager] 네이티브 콜백: ${call.method}');

    switch (call.method) {
      case 'onClockIn':
        await performClockIn(ctx);
        break;
      case 'onClockOut':
        await performClockOut(ctx);
        // 퇴근 후에는 버블을 닫아주는 것이 자연스러움
        await hide();
        break;
      case 'onBreak':
        await performBreak(ctx);
        break;
      case 'onHide':
        await hide();
        break;
      default:
        debugPrint(
            '[WorkFloatingBubbleManager] 알 수 없는 네이티브 메서드: ${call.method}');
    }

    return null;
  }

  /// 실제 출근 처리 로직 (인앱/시스템 공용)
  Future<void> performClockIn(BuildContext context) async {
    try {
      final userState = context.read<UserState>(); // Provider 에서 상태 가져오기
      final controller = CommuteInsideController();

      await controller.handleWorkStatusAndDecide(
        context,
        userState,
      );
      // 내비게이션은 컨트롤러/호출 측 구조에 따라 처리 (여기서는 로그/상태만)
    } catch (e, st) {
      debugPrint('[WorkFloatingBubbleManager] 출근 처리 중 오류: $e\n$st');
      try {
        showFailedSnackbar(
          context,
          '출근 처리 중 오류가 발생했습니다. 다시 시도해 주세요.',
        );
      } catch (_) {}
    }
  }

  /// 실제 퇴근 처리 로직 (인앱/시스템 공용)
  Future<void> performClockOut(BuildContext context) async {
    try {
      final userState = context.read<UserState>();
      final controller = HomeDashBoardController();

      await controller.handleWorkStatus(userState, context);

      // handleWorkStatus 안에서:
      // - 퇴근 로그 저장
      // - isWorking 플래그 false
      // - EndtimeReminderService 취소
      // - 포그라운드 서비스 종료 및 앱 종료(SystemNavigator.pop)
      //
      // 시스템 버블 모드에서는 앱이 종료되면 네이티브 쪽에서 버블 정리를
      // 동시에 해주는 것이 자연스럽습니다. (Dart 쪽에서는 hide() 를 호출해 둠)
    } catch (e, st) {
      debugPrint('[WorkFloatingBubbleManager] 퇴근 처리 중 오류: $e\n$st');
      try {
        showFailedSnackbar(
          context,
          '퇴근 처리 중 오류가 발생했습니다. 다시 시도해 주세요.',
        );
      } catch (_) {}
    }
  }

  /// 실제 휴게 기록 처리 로직 (인앱/시스템 공용)
  Future<void> performBreak(BuildContext context) async {
    try {
      final controller = HomeDashBoardController();
      await controller.recordBreakTime(context);
      // 성공/실패 스낵바는 컨트롤러 내부에서 처리
    } catch (e, st) {
      debugPrint('[WorkFloatingBubbleManager] 휴게 처리 중 오류: $e\n$st');
      try {
        showFailedSnackbar(
          context,
          '휴게 기록 중 오류가 발생했습니다. 다시 시도해 주세요.',
        );
      } catch (_) {}
    }
  }
}

/// 실제로 화면 위에 떠 있는 "인앱 버블" 위젯
///
/// - 앱 안에서만 보이는 오버레이 버블
/// - 버튼을 누르면 WorkFloatingBubbleManager 의 공용 처리 함수 호출
class WorkFloatingBubbleOverlay extends StatefulWidget {
  const WorkFloatingBubbleOverlay({
    super.key,
    required this.appContext,
    required this.onCloseRequested,
  });

  /// 실제 업무 로직 / Provider / Snackbar 에 접근할 때 사용할 상위 BuildContext
  final BuildContext appContext;

  /// 퇴근 등으로 버블을 닫아야 할 때 호출
  final VoidCallback onCloseRequested;

  @override
  State<WorkFloatingBubbleOverlay> createState() =>
      _WorkFloatingBubbleOverlayState();
}

class _WorkFloatingBubbleOverlayState
    extends State<WorkFloatingBubbleOverlay> {
  bool _expanded = false;
  bool _busy = false;

  void _toggleExpanded() {
    if (_busy) return;
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 120),
            child: _buildBubble(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.98),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.centerLeft,
          child: _expanded
              ? _buildExpandedContent(context, colorScheme)
              : _buildCollapsedContent(context, colorScheme),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent(
      BuildContext context,
      ColorScheme colorScheme,
      ) {
    return InkWell(
      onTap: _toggleExpanded,
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bubble_chart,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '근무 버블',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_left_rounded,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
      BuildContext context,
      ColorScheme colorScheme,
      ) {
    final disabled = _busy;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: Icons.login_rounded,
          label: '출근',
          color: colorScheme.primary,
          onTap: disabled ? null : _handleClockIn,
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.free_breakfast_outlined,
          label: '휴게',
          color: colorScheme.tertiary,
          onTap: disabled ? null : _handleBreak,
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          icon: Icons.logout_rounded,
          label: '퇴근',
          color: colorScheme.error,
          onTap: disabled ? null : _handleClockOut,
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: disabled ? null : _toggleExpanded,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 20),
          tooltip: '버블 접기',
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Future<void> Function()? onTap,
  }) {
    final isDisabled = onTap == null;

    return GestureDetector(
      onTap: isDisabled
          ? null
          : () {
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDisabled ? Colors.grey[200] : color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: isDisabled ? Colors.grey : color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleClockIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });

    try {
      await WorkFloatingBubbleManager.instance
          .performClockIn(widget.appContext);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _handleClockOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });

    try {
      await WorkFloatingBubbleManager.instance
          .performClockOut(widget.appContext);
      // 인앱 버블 모드에서도 퇴근 후에는 버블을 닫아주는 것이 자연스러움
      widget.onCloseRequested();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _handleBreak() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });

    try {
      await WorkFloatingBubbleManager.instance
          .performBreak(widget.appContext);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}
