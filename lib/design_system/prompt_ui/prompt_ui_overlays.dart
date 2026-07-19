import 'package:flutter/material.dart';

import 'prompt_ui_theme.dart';

Future<T?> showPromptOverlayDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  String? barrierLabel,
}) {
  final tokens = PromptUiTheme.of(context);
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: tokens.scrim,
    transitionDuration: reduceMotion ? Duration.zero : PromptUiMotion.overlay,
    pageBuilder: (dialogContext, _, __) {
      return PromptUiScope(
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
        curve: PromptUiMotion.enter,
        reverseCurve: PromptUiMotion.exit,
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

Future<T?> showPromptOverlayBottomSheet<T>({
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
  final tokens = PromptUiTheme.of(context);
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
              top: Radius.circular(PromptUiShapes.sheet),
            ),
            side: BorderSide(color: tokens.borderSubtle),
          ),
    clipBehavior: transparentBackground ? Clip.none : Clip.antiAlias,
    builder: (sheetContext) {
      return PromptUiScope(
        child: Builder(
          builder: (scopedContext) => builder(scopedContext),
        ),
      );
    },
  );
}

Future<DateTime?> showPromptDatePicker({
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
      return PromptUiScope(child: child ?? const SizedBox.shrink());
    },
  );
}

Future<TimeOfDay?> showPromptTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  TransitionBuilder? builder,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (pickerContext, child) {
      final scoped = PromptUiScope(
        child: child ?? const SizedBox.shrink(),
      );
      return builder == null ? scoped : builder(pickerContext, scoped);
    },
  );
}

Future<DateTimeRange?> showPromptDateRangePicker({
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
      return PromptUiScope(child: child ?? const SizedBox.shrink());
    },
  );
}
