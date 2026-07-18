import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class HeadTutorials {
  HeadTutorials._();

  static const List<TutorialItem> items = <TutorialItem>[
    TutorialItem(
      title: '본사 1차',
      assetPath: 'assets/00.head.pdf',
    ),
    TutorialItem(
      title: '본사 2차',
      assetPath: 'assets/01.head.pdf',
    ),
    TutorialItem(
      title: '약식 모드',
      assetPath: 'assets/02.simple.pdf',
    ),
    TutorialItem(
      title: '경량 모드',
      assetPath: 'assets/03.lite.pdf',
    ),
    TutorialItem(
      title: '서비스 모드',
      assetPath: 'assets/04.service.pdf',
    ),
  ];

  static Future<TutorialItem?> showPickerBottomSheet(
    BuildContext context, {
    bool usePromptUi = false,
  }) {
    if (usePromptUi) {
      return showPromptOverlayBottomSheet<TutorialItem>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const TutorialPickerBottomSheet(items: items),
      );
    }

    return showModalBottomSheet<TutorialItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TutorialPickerBottomSheet(items: items),
    );
  }

  static Future<void> open(
    BuildContext context, {
    bool usePromptUi = false,
  }) async {
    final selected = await showPickerBottomSheet(
      context,
      usePromptUi: usePromptUi,
    );
    if (selected == null || !context.mounted) return;
    await TutorialPdfViewer.open(
      context,
      selected,
      usePromptUi: usePromptUi,
    );
  }
}

class TutorialItem {
  const TutorialItem({
    required this.title,
    this.assetPath,
    this.filePath,
  });

  final String title;
  final String? assetPath;
  final String? filePath;

  String get sourceLabel => assetPath != null ? '앱 에셋' : '로컬 파일';

  String get sourcePathText => assetPath ?? filePath ?? '-';
}

class TutorialPickerBottomSheet extends StatelessWidget {
  const TutorialPickerBottomSheet({
    super.key,
    required this.items,
  });

  final List<TutorialItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.52,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, controller) {
          return Container(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PromptUiShapes.sheet),
              ),
              border: Border.all(color: tokens.borderSubtle),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 22,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.handle,
                    borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tokens.dangerContainer,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.control),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: tokens.onDangerContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '튜토리얼',
                              style: textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '읽을 문서를 선택하세요.',
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PromptIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).maybePop(),
                        haptic: PromptHaptic.selection,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return PromptAnimatedReveal(
                        delay: Duration(milliseconds: index * 40),
                        offset: const Offset(0, 0.035),
                        child: Material(
                          color: tokens.surface,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.control),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(PromptUiShapes.control),
                            onTap: () => Navigator.of(context).pop(item),
                            child: Ink(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                                border:
                                    Border.all(color: tokens.borderSubtle),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: tokens.surfaceOverlay,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      Icons.menu_book_rounded,
                                      color: tokens.accent,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          item.title,
                                          style: textTheme.titleSmall?.copyWith(
                                            color: tokens.textPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${item.sourceLabel} · ${item.sourcePathText}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: tokens.iconSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TutorialPdfViewer extends StatefulWidget {
  const TutorialPdfViewer({
    super.key,
    required this.title,
    required this.controller,
    this.usePromptUi = false,
  });

  final String title;
  final PdfControllerPinch controller;
  final bool usePromptUi;

  static Future<void> open(
    BuildContext context,
    TutorialItem item, {
    bool usePromptUi = false,
  }) async {
    final Future<PdfDocument> document;

    if (item.assetPath != null) {
      document = PdfDocument.openAsset(item.assetPath!);
    } else if (item.filePath != null) {
      final file = File(item.filePath!);
      if (!file.existsSync()) {
        showFailedSnackbar(
          context,
          'PDF 파일을 찾을 수 없습니다.',
          usePromptUi: usePromptUi,
        );
        return;
      }
      document = PdfDocument.openFile(item.filePath!);
    } else {
      showFailedSnackbar(
        context,
        '열 수 있는 PDF 경로가 없습니다.',
        usePromptUi: usePromptUi,
      );
      return;
    }

    final controller = PdfControllerPinch(document: document);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : PromptUiMotion.overlay;

    final route = PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) {
        final page = TutorialPdfViewer(
          title: item.title,
          controller: controller,
          usePromptUi: usePromptUi,
        );
        return usePromptUi ? PromptUiScope(child: page) : page;
      },
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
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

    await Navigator.of(context).push(route);
  }

  @override
  State<TutorialPdfViewer> createState() => _TutorialPdfViewerState();
}

class _TutorialPdfViewerState extends State<TutorialPdfViewer> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: tokens.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(
          bottom: BorderSide(color: tokens.borderSubtle),
        ),
        actions: <Widget>[
          PromptIconButton(
            icon: Icons.first_page_rounded,
            tooltip: '첫 페이지',
            onPressed: () => widget.controller.jumpToPage(1),
            haptic: PromptHaptic.selection,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ColoredBox(
        color: tokens.surfaceOverlay,
        child: PdfViewPinch(
          controller: widget.controller,
          onDocumentError: (error) {
            showFailedSnackbar(
              context,
              'PDF 오류: $error',
              usePromptUi: widget.usePromptUi,
            );
          },
        ),
      ),
    );
  }
}
