import 'package:flutter/material.dart';

import 'common_ui_theme.dart';

Future<T?> showCommonOverlayDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  String? barrierLabel,
}) {
  final tokens = CommonUiTheme.of(context);
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: tokens.scrim,
    transitionDuration: reduceMotion ? Duration.zero : CommonUiMotion.overlay,
    pageBuilder: (dialogContext, _, __) {
      return CommonUiScope(
        child: SafeArea(
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Builder(
                builder: (scopedContext) => builder(scopedContext),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: CommonUiMotion.enter,
        reverseCurve: CommonUiMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Future<T?> showCommonOverlayBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = false,
  bool useRootNavigator = false,
  bool transparentBackground = true,
}) {
  final tokens = CommonUiTheme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    backgroundColor:
        transparentBackground ? tokens.transparent : tokens.surfaceRaised,
    barrierColor: tokens.scrim,
    elevation: 0,
    shape: transparentBackground
        ? null
        : RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CommonUiShapes.sheet),
            ),
            side: BorderSide(color: tokens.borderSubtle),
          ),
    clipBehavior: transparentBackground ? Clip.none : Clip.antiAlias,
    builder: (sheetContext) {
      return CommonUiScope(
        child: Builder(
          builder: (scopedContext) => builder(scopedContext),
        ),
      );
    },
  );
}

Future<DateTime?> showCommonDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: (pickerContext, child) {
      return CommonUiScope(child: child ?? const SizedBox.shrink());
    },
  );
}

Future<TimeOfDay?> showCommonTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TransitionBuilder? builder,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (pickerContext, child) {
      final scoped = CommonUiScope(
        child: child ?? const SizedBox.shrink(),
      );
      return builder == null ? scoped : builder(pickerContext, scoped);
    },
  );
}

Future<DateTimeRange?> showCommonDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? cancelText,
  String? confirmText,
}) {
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    cancelText: cancelText,
    confirmText: confirmText,
    builder: (pickerContext, child) {
      return CommonUiScope(child: child ?? const SizedBox.shrink());
    },
  );
}
