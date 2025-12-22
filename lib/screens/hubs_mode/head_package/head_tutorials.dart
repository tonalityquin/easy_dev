// lib/screens/hubs_mode/head_package/head_tutorials.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// ─────────────────────────────────────────────────────────────────
/// 튜토리얼: 아이템 / 바텀시트 / PDF 뷰어
/// - HeadStubPage와 HeadHubActions(버블)이 공통으로 호출하기 위해 분리
/// ─────────────────────────────────────────────────────────────────

class HeadTutorials {
  HeadTutorials._();

  /// 본사 허브 튜토리얼 목록(필요 시 추가)
  static const List<TutorialItem> items = [
    TutorialItem(
      title: '00.basic',
      assetPath: 'assets/00.basic.pdf',
    ),
  ];

  /// 튜토리얼 선택 바텀시트만 띄우고 선택값을 반환
  static Future<TutorialItem?> showPickerBottomSheet(BuildContext context) {
    return showModalBottomSheet<TutorialItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TutorialPickerBottomSheet(items: items),
    );
  }

  /// (권장) 선택 바텀시트 → 선택 시 PDF Viewer까지 이어서 오픈
  static Future<void> open(BuildContext context) async {
    final selected = await showPickerBottomSheet(context);
    if (selected != null) {
      await TutorialPdfViewer.open(context, selected);
    }
  }
}

class TutorialItem {
  final String title;
  final String? assetPath; // 예: assets/00.basic.pdf
  final String? filePath; // 예: /storage/emulated/0/Download/00.basic.pdf

  const TutorialItem({
    required this.title,
    this.assetPath,
    this.filePath,
  });
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                  title: Text('튜토리얼', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('읽을 항목을 선택하세요'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return ListTile(
                        leading: const Icon(Icons.picture_as_pdf_rounded),
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          item.assetPath != null ? '앱 에셋' : '로컬 파일',
                          style: TextStyle(color: cs.outline),
                        ),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: items.length,
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

  /// 선택한 튜토리얼을 열기 위한 헬퍼
  static Future<void> open(BuildContext context, TutorialItem item) async {
    Future<PdfDocument> futureDoc;

    if (item.assetPath != null) {
      futureDoc = PdfDocument.openAsset(item.assetPath!);
    } else if (item.filePath != null) {
      if (!File(item.filePath!).existsSync()) {
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

    // ignore: use_build_context_synchronously
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorialPdfViewer(title: item.title, controller: controller),
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 오류: $e')));
          },
        ),
      ),
    );
  }
}
