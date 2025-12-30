// lib/screens/hubs_mode/head_package/head_tutorials.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// ─────────────────────────────────────────────────────────────────
/// 튜토리얼: 아이템 / 바텀시트 / PDF 뷰어
/// - 여러 화면(예: HeadStubPage, HeadHubActions 등)에서 공통 호출 가능하도록 분리
/// - '튜토리얼' 카드를 누르면 바텀시트에서 항목을 선택하고, 선택한 PDF를 뷰어로 연다.
/// ─────────────────────────────────────────────────────────────────
class HeadTutorials {
  HeadTutorials._();

  /// 튜토리얼 목록
  /// 요구사항:
  ///  - 본사 1차   -> assets/00.head.pdf
  ///  - 본사 2차   -> assets/01.head.pdf
  ///  - 약식 모드  -> assets/02.simple.pdf
  ///  - 경량 모드  -> assets/03.lite.pdf
  ///  - 서비스 모드-> assets/04.service.pdf
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

  /// 예: assets/00.head.pdf
  final String? assetPath;

  /// 예: /storage/emulated/0/Download/00.head.pdf
  /// (확장용: 필요하면 로컬 파일 PDF도 열 수 있도록 기존 로직 유지)
  final String? filePath;

  const TutorialItem({
    required this.title,
    this.assetPath,
    this.filePath,
  });

  String get sourceLabel => assetPath != null ? '앱 에셋' : '로컬 파일';

  /// 바텀시트에 표시할 “실제 경로/파일명” 텍스트
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

  /// 선택한 튜토리얼을 열기 위한 헬퍼
  static Future<void> open(BuildContext context, TutorialItem item) async {
    Future<PdfDocument> futureDoc;

    if (item.assetPath != null) {
      // pubspec.yaml 의 flutter/assets 에 등록되어 있어야 함
      futureDoc = PdfDocument.openAsset(item.assetPath!);
    } else if (item.filePath != null) {
      // 로컬 파일 경로의 경우 파일 유무 확인
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

    // ignore: use_build_context_synchronously
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
