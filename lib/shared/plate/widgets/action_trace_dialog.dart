import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ActionTraceController {
  final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<bool> isCompleted = ValueNotifier<bool>(false);

  void add(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    lines.value = List<String>.from(lines.value)
      ..add('[$hh:$mm:$ss] $message');
  }

  void complete([String? message]) {
    if (message != null && message.trim().isNotEmpty) add(message);
    isCompleted.value = true;
  }
}

class ActionTraceDialog extends StatefulWidget {
  final String title;
  final ActionTraceController controller;

  const ActionTraceDialog({
    super.key,
    required this.title,
    required this.controller,
  });

  static Future<void> showAndRun(
    BuildContext context, {
    required String title,
    required Future<void> Function(ActionTraceController trace) task,
  }) async {
    if (!context.mounted) return;
    final controller = ActionTraceController();
    showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActionTraceDialog(
        title: title,
        controller: controller,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await task(controller);
    } catch (error, stackTrace) {
      controller.add('예외: $error');
      final compactStack = stackTrace
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(6)
          .join(' | ');
      if (compactStack.isNotEmpty) controller.add(compactStack);
    } finally {
      controller.complete('작업 종료');
    }
  }

  @override
  State<ActionTraceDialog> createState() => _ActionTraceDialogState();
}

class _ActionTraceDialogState extends State<ActionTraceDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.lines.addListener(_scheduleScrollToBottom);
  }

  @override
  void dispose() {
    widget.controller.lines.removeListener(_scheduleScrollToBottom);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : PromptUiMotion.selection,
        curve: PromptUiMotion.enter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return WillPopScope(
      onWillPop: () async => false,
      child: PromptDialogFrame(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tokens.infoContainer,
                      borderRadius: BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(color: tokens.info.withOpacity(.36)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.manage_search_rounded, color: tokens.info),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.surfaceOverlay,
                    borderRadius: BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: widget.controller.lines,
                    builder: (_, lines, __) {
                      return SingleChildScrollView(
                        controller: _scrollController,
                        child: SelectableText(
                          lines.isEmpty ? '대기 중...' : lines.join('\n'),
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.textPrimary,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: widget.controller.isCompleted,
                builder: (_, isCompleted, __) {
                  return PromptButton(
                    label: isCompleted ? '닫기' : '진행 중',
                    loading: !isCompleted,
                    expand: true,
                    onPressed: isCompleted
                        ? () => Navigator.of(context, rootNavigator: true)
                            .maybePop()
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
