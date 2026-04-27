import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class HeadTutorials {
  HeadTutorials._();

  static const List<TutorialItem> items = [
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

  static Future<TutorialItem?> showPickerBottomSheet(BuildContext context) {
    return showModalBottomSheet<TutorialItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TutorialPickerBottomSheet(items: items),
    );
  }

  static Future<void> open(BuildContext context) async {
    final selected = await showPickerBottomSheet(context);
    if (selected != null) {
      await TutorialPdfViewer.open(context, selected);
    }
  }
}

class TutorialItem {
  final String title;

  final String? assetPath;

  final String? filePath;

  const TutorialItem({
    required this.title,
    this.assetPath,
    this.filePath,
  });

  String get sourceLabel => assetPath != null ? '앱 에셋' : '로컬 파일';

  String get sourcePathText => assetPath ?? filePath ?? '-';
}

class TutorialPickerBottomSheet extends StatelessWidget {
  final List<TutorialItem> items;

  const TutorialPickerBottomSheet({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(.06),
                  blurRadius: 20,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                const ListTile(
                  title: Text('튜토리얼',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('읽을 항목을 선택하세요'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = items[i];

                      return ListTile(
                        leading: const Icon(Icons.picture_as_pdf_rounded),
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${item.sourceLabel} · ${item.sourcePathText}',
                          style: TextStyle(color: cs.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(item),
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
  final String title;
  final PdfControllerPinch controller;

  const TutorialPdfViewer({
    super.key,
    required this.title,
    required this.controller,
  });

  static Future<void> open(BuildContext context, TutorialItem item) async {
    Future<PdfDocument> futureDoc;

    if (item.assetPath != null) {
      futureDoc = PdfDocument.openAsset(item.assetPath!);
    } else if (item.filePath != null) {
      final file = File(item.filePath!);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 파일을 찾을 수 없습니다.')),
        );
        return;
      }
      futureDoc = PdfDocument.openFile(item.filePath!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('열 수 있는 PDF 경로가 없습니다.')),
      );
      return;
    }

    final controller = PdfControllerPinch(document: futureDoc);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorialPdfViewer(
          title: item.title,
          controller: controller,
        ),
        fullscreenDialog: true,
      ),
    );
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '첫 페이지',
            icon: const Icon(Icons.first_page_rounded),
            onPressed: () => widget.controller.jumpToPage(1),
          ),
        ],
      ),
      body: Container(
        color: cs.surface,
        child: PdfViewPinch(
          controller: widget.controller,
          onDocumentError: (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF 오류: $e')),
            );
          },
        ),
      ),
    );
  }
}
