import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<T?> showNormalReversePageTopSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeightFactor = 1, // 시트 높이 비율
  bool barrierDismissible = true,
  Color? barrierColor,
  Duration duration = const Duration(milliseconds: 300),

  /// ✅ 추가: 루트 네비게이터 사용 여부(기본 true)
  /// - TopSheet가 showGeneralDialog로 뜨므로, dismiss/popup이 확실히 같은 네비게이터를 사용하도록 통일합니다.
  bool useRootNavigator = true,
}) {
  debugPrint('[REV-TOP] showReversePageTopSheet() open requested');
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator, // ✅ 추가
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: duration,
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: maxHeightFactor,
          widthFactor: 1.0,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(curved),
            child: Material(
              color: Colors.white,
              elevation: 12,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _TopSheetContainer(
                child: builder(ctx),
                useRootNavigator: useRootNavigator, // ✅ 전달
              ),
            ),
          ),
        ),
      );
    },
  ).then((value) {
    debugPrint('[REV-TOP] showReversePageTopSheet() closed (result=$value)');
    return value;
  });
}

class _TopSheetContainer extends StatefulWidget {
  final Widget child;

  /// ✅ 추가: dismiss 시 동일 네비게이터로 pop하도록 옵션 전달
  final bool useRootNavigator;

  const _TopSheetContainer({
    required this.child,
    required this.useRootNavigator,
  });

  @override
  State<_TopSheetContainer> createState() => _TopSheetContainerState();
}

class _TopSheetContainerState extends State<_TopSheetContainer> {
  double _drag = 0;
  static const _dismissThreshold = 90.0; // 이 이상 내리면 닫기

  @override
  void initState() {
    super.initState();
    debugPrint('[REV-TOP] TopSheetContainer mounted');
  }

  @override
  void dispose() {
    debugPrint('[REV-TOP] TopSheetContainer disposed');
    super.dispose();
  }

  void _dismissSheet() {
    debugPrint('[REV-TOP] dismiss requested (rootNavigator=${widget.useRootNavigator})');
    Navigator.of(context, rootNavigator: widget.useRootNavigator).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (d) {
        _drag += d.delta.dy;
        if (_drag > _dismissThreshold) {
          debugPrint('[REV-TOP] drag to dismiss triggered (dy=$_drag) — no cost added');
          HapticFeedback.selectionClick();
          _dismissSheet(); // ✅ 통일
          _drag = 0;
        }
      },
      onVerticalDragEnd: (_) {
        debugPrint('[REV-TOP] drag end (dy=$_drag)');
        _drag = 0;
      },
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: widget.child),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
