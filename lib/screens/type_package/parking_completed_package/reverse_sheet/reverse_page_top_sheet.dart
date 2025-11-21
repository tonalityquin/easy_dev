// lib/screens/type_package/parking_completed_package/reverse_sheet/reverse_page_top_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<T?> showReversePageTopSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeightFactor = 1, // 시트 높이 비율
  bool barrierDismissible = true,
  Color? barrierColor,
  Duration duration = const Duration(milliseconds: 300),
}) {
  debugPrint('[REV-TOP] showReversePageTopSheet() open requested');
  return showGeneralDialog<T>(
    context: context,
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
            position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(curved),
            child: Material(
              // 배경은 항상 흰색
              color: Colors.white,
              elevation: 12,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _TopSheetContainer(child: builder(ctx)),
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
  const _TopSheetContainer({required this.child});

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

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;

    return GestureDetector(
      onVerticalDragUpdate: (d) {
        _drag += d.delta.dy;
        if (_drag > _dismissThreshold) {
          debugPrint('[REV-TOP] drag to dismiss triggered (dy=$_drag) — no cost added');
          HapticFeedback.selectionClick();
          Navigator.of(context).maybePop();
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
            decoration: BoxDecoration(color: divider, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Expanded(child: widget.child),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
