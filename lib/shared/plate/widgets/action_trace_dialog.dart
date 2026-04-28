import 'package:flutter/material.dart';

class ActionTraceController {
  final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<bool> isCompleted = ValueNotifier<bool>(false);

  void add(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    lines.value = List<String>.from(lines.value)..add('[$hh:$mm:$ss] $message');
  }

  void complete([String? message]) {
    if (message != null && message.trim().isNotEmpty) {
      add(message);
    }
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

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => ActionTraceDialog(
        title: title,
        controller: controller,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      await task(controller);
    } catch (e, st) {
      controller.add('예외: $e');
      final compactStack = st
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(6)
          .join(' | ');
      if (compactStack.isNotEmpty) {
        controller.add(compactStack);
      }
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
      final position = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: [
            Icon(Icons.manage_search_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 320,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
            ),
            child: ValueListenableBuilder<List<String>>(
              valueListenable: widget.controller.lines,
              builder: (_, lines, __) {
                final text = lines.isEmpty ? '대기 중...' : lines.join('\n');
                return SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    text,
                    style: tt.bodySmall?.copyWith(
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: widget.controller.isCompleted,
            builder: (_, isCompleted, __) {
              return FilledButton(
                onPressed: isCompleted
                    ? () => Navigator.of(context, rootNavigator: true).maybePop()
                    : null,
                child: Text(isCompleted ? '닫기' : '진행 중'),
              );
            },
          ),
        ],
      ),
    );
  }
}
