import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../design_system/prompt_ui/prompt_ui_theme.dart';
import 'document_box_action.dart';
import 'document_item.dart';

class PromptDocumentBoxSheet extends StatelessWidget {
  const PromptDocumentBoxSheet({
    super.key,
    required this.title,
    required this.description,
    required this.stream,
    required this.actionFor,
  });

  final String title;
  final String description;
  final Stream<List<DocumentItem>> stream;
  final DocumentBoxAction? Function(DocumentItem item) actionFor;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (sheetContext, scrollController) {
        return PromptSheetScaffold(
          title: title,
          icon: Icons.folder_open_rounded,
          onClose: () => Navigator.of(sheetContext).maybePop(),
          body: Column(
            children: [
              _DocumentBoxDescription(description: description),
              Expanded(
                child: StreamBuilder<List<DocumentItem>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snapshot.data ?? const <DocumentItem>[];
                    if (items.isEmpty) {
                      return const _DocumentBoxEmptyState();
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final action = actionFor(item);
                        return PromptAnimatedReveal(
                          delay: Duration(milliseconds: 35 * index.clamp(0, 6).toInt()),
                          offset: Offset.zero,
                          child: _PromptDocumentItem(
                            item: item,
                            enabled: action != null,
                            onTap: action == null
                                ? null
                                : () => Navigator.of(context).pop(action),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentBoxDescription extends StatelessWidget {
  const _DocumentBoxDescription({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.infoContainer,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          border: Border.all(color: tokens.info.withOpacity(0.38)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: tokens.onInfoContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.onInfoContainer,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptDocumentItem extends StatefulWidget {
  const _PromptDocumentItem({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  final DocumentItem item;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_PromptDocumentItem> createState() => _PromptDocumentItemState();
}

class _PromptDocumentItemState extends State<_PromptDocumentItem> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _frameScheduled = false;

  void _queueState({bool? pressed, bool? hovered, bool? focused}) {
    if (pressed != null) _pendingPressed = pressed;
    if (hovered != null) _pendingHovered = hovered;
    if (focused != null) _pendingFocused = focused;
    if (_frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final nextPressed = _pendingPressed;
      final nextHovered = _pendingHovered;
      final nextFocused = _pendingFocused;
      _pendingPressed = null;
      _pendingHovered = null;
      _pendingFocused = null;
      final changed =
          (nextPressed != null && nextPressed != _pressed) ||
              (nextHovered != null && nextHovered != _hovered) ||
              (nextFocused != null && nextFocused != _focused);
      if (!changed) return;
      setState(() {
        if (nextPressed != null) _pressed = nextPressed;
        if (nextHovered != null) _hovered = nextHovered;
        if (nextFocused != null) _focused = nextFocused;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tone = _documentTone(tokens, widget.item);
    final background = _pressed || _hovered
        ? tokens.surfaceSelected
        : tokens.surfaceRaised;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.item.title,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          curve: PromptUiMotion.standard,
          decoration: BoxDecoration(
            color: widget.enabled ? background : tokens.surfaceDisabled,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            border: Border.all(
              color: _focused ? tokens.focusRing : tokens.borderSubtle,
              width: _focused ? 2 : 1,
            ),
            boxShadow: [
              if (_hovered && widget.enabled)
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) {
                if (_pressed == value && _pendingPressed == null) return;
                _queueState(pressed: value);
              },
              onHover: (value) {
                if (_hovered == value && _pendingHovered == null) return;
                _queueState(hovered: value);
              },
              onFocusChange: (value) {
                if (_focused == value && _pendingFocused == null) return;
                _queueState(focused: value);
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: tone.container,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _iconForType(widget.item.type),
                        size: 22,
                        color: tone.foreground,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyLarge?.copyWith(
                              color: widget.enabled
                                  ? tokens.textPrimary
                                  : tokens.textDisabled,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _buildSubtitle(widget.item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: widget.enabled
                                  ? tokens.textSecondary
                                  : tokens.textDisabled,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tone.container,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.pill),
                            ),
                            child: Text(
                              _typeLabelForItem(widget.item),
                              style: textTheme.labelSmall?.copyWith(
                                color: tone.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedScale(
                      scale: _pressed ? 0.9 : 1,
                      duration:
                          reduceMotion ? Duration.zero : PromptUiMotion.press,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: widget.enabled
                            ? tokens.iconSecondary
                            : tokens.iconDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentBoxEmptyState extends StatelessWidget {
  const _DocumentBoxEmptyState();

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: PromptAnimatedReveal(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(PromptUiShapes.card),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  size: 34,
                  color: tokens.iconSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '표시할 서류가 없어요',
                style: textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '사용할 수 있는 문서가 생성되면 이곳에 표시됩니다.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentTone {
  const _DocumentTone(this.container, this.foreground);

  final Color container;
  final Color foreground;
}

_DocumentTone _documentTone(PromptUiTokens tokens, DocumentItem item) {
  if (item.type == DocumentType.workStartReportForm) {
    return _DocumentTone(tokens.successContainer, tokens.onSuccessContainer);
  }
  if (item.type == DocumentType.workEndReportForm) {
    return _DocumentTone(tokens.warningContainer, tokens.onWarningContainer);
  }
  if (item.type == DocumentType.statementForm) {
    return _DocumentTone(tokens.infoContainer, tokens.onInfoContainer);
  }
  return _DocumentTone(tokens.accentContainer, tokens.onAccentContainer);
}

IconData _iconForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return Icons.wb_sunny_outlined;
    case DocumentType.workEndReportForm:
      return Icons.nights_stay_outlined;
    case DocumentType.statementForm:
      return Icons.description_outlined;
    case DocumentType.generic:
      return Icons.insert_drive_file_outlined;
  }
}

String _buildSubtitle(DocumentItem item) {
  final parts = <String>[];
  if (item.subtitle != null && item.subtitle!.isNotEmpty) {
    parts.add(item.subtitle!);
  }
  parts.add('수정: ${_formatDateTime(item.updatedAt)}');
  return parts.join(' • ');
}

String _formatDateTime(DateTime dateTime) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} '
      '${two(dateTime.hour)}:${two(dateTime.minute)}';
}

String _typeLabelForItem(DocumentItem item) {
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') return '퇴근 보고';
    if (item.id == 'template-end-work-report') return '업무 종료 보고';
  }
  if (item.type == DocumentType.statementForm) {
    if (item.id == 'template-commute-record') return '출퇴근 기록';
    if (item.id == 'template-resttime-record') return '휴게시간 기록';
  }
  switch (item.type) {
    case DocumentType.workStartReportForm:
      return '업무 시작 보고';
    case DocumentType.workEndReportForm:
      return '퇴근·업무 종료';
    case DocumentType.statementForm:
      return '경위서';
    case DocumentType.generic:
      return '기타 문서';
  }
}
