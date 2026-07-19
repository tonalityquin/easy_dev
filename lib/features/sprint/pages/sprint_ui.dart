import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';

void sprintShowMessage({
  required BuildContext context,
  required String message,
  bool danger = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final tokens = PromptUiTheme.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 0,
      backgroundColor:
          danger ? tokens.dangerContainer : tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        side: BorderSide(
          color: danger ? tokens.danger : tokens.borderSubtle,
        ),
      ),
      content: Row(
        children: [
          Icon(
            danger ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: danger
                ? tokens.onDangerContainer
                : tokens.onSuccessContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: danger
                        ? tokens.onDangerContainer
                        : tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<T?> sprintShowBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  bool useRootNavigator = false,
}) {
  return showPromptOverlayBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useRootNavigator: useRootNavigator,
    transparentBackground: false,
  );
}

Future<T?> sprintShowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return showPromptOverlayDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
  );
}

Future<DateTime?> sprintShowDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? cancelText,
  String? confirmText,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    cancelText: cancelText,
    confirmText: confirmText,
    builder: (pickerContext, child) {
      return PromptUiScope(child: child ?? const SizedBox.shrink());
    },
  );
}

Route<T> sprintPageRoute<T>({
  required BuildContext context,
  required Widget page,
  Offset beginOffset = const Offset(0.035, 0),
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return PageRouteBuilder<T>(
    transitionDuration: reduceMotion ? Duration.zero : PromptUiMotion.overlay,
    reverseTransitionDuration:
        reduceMotion ? Duration.zero : PromptUiMotion.component,
    pageBuilder: (_, __, ___) => SprintPromptScope(child: page),
    transitionsBuilder: (_, animation, __, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: PromptUiMotion.enter,
        reverseCurve: PromptUiMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Color sprintTransparent(BuildContext context) {
  return PromptUiTheme.of(context).transparent;
}

Future<String?> sprintSelectTaskProject({
  required BuildContext context,
  required SprintModeStore store,
  String? initialProjectId,
}) async {
  final preferred = store.preferredTaskProjectId(initialProjectId);
  if (preferred != null) return preferred;
  final projects = store.projects;
  if (projects.isEmpty) {
    sprintShowMessage(
      context: context,
      message: '업무를 추가하려면 먼저 프로젝트를 생성하세요.',
      danger: true,
    );
    return null;
  }
  return sprintShowBottomSheet<String>(
    context: context,
    builder: (sheetContext) {
      final reduceMotion =
          MediaQuery.maybeOf(sheetContext)?.disableAnimations ?? false;
      final duration = reduceMotion ? Duration.zero : PromptUiMotion.component;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: AnimatedSize(
          duration: duration,
          curve: PromptUiMotion.enter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '프로젝트 선택',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              ...projects.indexed.map(
                (entry) => PromptAnimatedReveal(
                  delay: reduceMotion
                      ? Duration.zero
                      : Duration(milliseconds: entry.$1 * 45),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SprintSurface(
                      padding: EdgeInsets.zero,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(entry.$2.id),
                      child: ListTile(
                        minTileHeight: 56,
                        leading: Icon(entry.$2.icon),
                        title: Text(
                          entry.$2.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<SprintTask?> sprintCreateTaskFromComposer({
  required BuildContext context,
  required SprintModeStore store,
  required String rawText,
}) async {
  if (rawText.trim().isEmpty) return null;
  final projectId = await sprintSelectTaskProject(
    context: context,
    store: store,
    initialProjectId: store.selectedProjectId,
  );
  if (projectId == null || !context.mounted) return null;
  final preview = store.previewTaskFromText(rawText, projectId: projectId);
  if (preview == null) {
    final error = store.taskInputError;
    if (error != null && context.mounted) {
      sprintShowMessage(context: context, message: error, danger: true);
    }
    return null;
  }
  if (preview.hasHardConflict) {
    if (context.mounted) {
      sprintShowMessage(
        context: context,
        message: store.taskInputError ?? '업무 날짜를 확인하세요.',
        danger: true,
      );
    }
    return null;
  }
  final task = await store.createTaskFromPreview(preview);
  if (task == null && context.mounted) {
    sprintShowMessage(
      context: context,
      message: store.taskInputError ?? '업무를 추가하지 못했습니다.',
      danger: true,
    );
  }
  return task;
}

String sprintTwoDigits(int value) => value.toString().padLeft(2, '0');

String sprintFormatTime(DateTime value) {
  return '${sprintTwoDigits(value.hour)}:${sprintTwoDigits(value.minute)}';
}

String sprintFormatDate(DateTime value) {
  return '${value.month}월 ${value.day}일 ${sprintWeekday(value.weekday)}요일';
}

String sprintFormatShortDate(DateTime value) {
  return '${value.month}/${value.day}';
}

String sprintFormatDateRange(DateTime start, DateTime end) {
  if (sprintSameDay(start, end)) return sprintFormatDate(start);
  return '${sprintFormatShortDate(start)}–${sprintFormatShortDate(end)}';
}

String sprintPriorityLabel(SprintTaskPriority priority) {
  switch (priority) {
    case SprintTaskPriority.high:
      return '높음';
    case SprintTaskPriority.normal:
      return '보통';
    case SprintTaskPriority.low:
      return '낮음';
  }
}

IconData sprintPriorityIcon(SprintTaskPriority priority) {
  switch (priority) {
    case SprintTaskPriority.high:
      return Icons.keyboard_double_arrow_up_rounded;
    case SprintTaskPriority.normal:
      return Icons.remove_rounded;
    case SprintTaskPriority.low:
      return Icons.keyboard_arrow_down_rounded;
  }
}

String sprintWeekday(int weekday) {
  const labels = <String>['월', '화', '수', '목', '금', '토', '일'];
  return labels[(weekday - 1).clamp(0, 6).toInt()];
}

bool sprintSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class SprintPromptScope extends StatelessWidget {
  const SprintPromptScope({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(child: child);
  }
}

class SprintScaffold extends StatelessWidget {
  const SprintScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.animateBody = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool animateBody;

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (scopedContext) {
          final tokens = PromptUiTheme.of(scopedContext);
          final pageBody = body == null
              ? null
              : animateBody
                  ? PromptAnimatedReveal(
                      offset: const Offset(0, 0.025),
                      child: body!,
                    )
                  : body;
          return Scaffold(
            appBar: appBar,
            body: pageBody,
            floatingActionButton: floatingActionButton,
            floatingActionButtonLocation: floatingActionButtonLocation,
            bottomNavigationBar: bottomNavigationBar,
            backgroundColor: backgroundColor ?? tokens.canvas,
            resizeToAvoidBottomInset: resizeToAvoidBottomInset,
            extendBody: extendBody,
            extendBodyBehindAppBar: extendBodyBehindAppBar,
          );
        },
      ),
    );
  }
}

class SprintSurface extends StatelessWidget {
  const SprintSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
      curve: PromptUiMotion.standard,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(
          color: borderColor ?? tokens.borderSubtle,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: tokens.transparent,
      borderRadius: BorderRadius.circular(PromptUiShapes.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class SprintSectionHeader extends StatelessWidget {
  const SprintSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          PromptButton(
            label: actionLabel!,
            onPressed: onAction,
            variant: PromptButtonVariant.tertiary,
            haptic: PromptHaptic.selection,
            minHeight: 40,
          ),
      ],
    );
  }
}

class SprintMetric extends StatelessWidget {
  const SprintMetric({
    super.key,
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
              ? Duration.zero
              : PromptUiMotion.selection,
          child: Text(
            value,
            key: ValueKey<String>(value),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: warning ? tokens.danger : tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
