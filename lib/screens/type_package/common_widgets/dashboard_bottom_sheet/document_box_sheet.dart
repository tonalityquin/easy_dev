// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/document_box_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import 'document_inventory_repository.dart';

// ✅ 경위서 화면 (동일 코드 사본을 같은 폴더에 둠)
import 'user_statement_form_page.dart';
import 'widgets/document_item.dart';

/// 현재 화면 위에 띄우는 바텀시트 오픈 함수
/// - useRootNavigator: false → 같은 트리의 Provider/Stream 공유(지역 스트림 끊김 방지)
/// - isScrollControlled: true → DraggableScrollableSheet 높이 제어
Future<void> openDocumentBox(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _DocumentBoxSheet(),
  );
}

class _DocumentBoxSheet extends StatelessWidget {
  const _DocumentBoxSheet();

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final repo = DocumentInventoryRepository.instance;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 60,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),

              // 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      '내 서류함',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '닫기',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // 목록(사용자 전용 인벤토리)
              Expanded(
                child: StreamBuilder<List<DocumentItem>>(
                  stream: repo.streamForUser(userState),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snapshot.data ?? const <DocumentItem>[];
                    if (items.isEmpty) {
                      return const _EmptyState();
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          leading: const Icon(Icons.description_outlined),
                          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (item.subtitle != null && item.subtitle!.isNotEmpty) item.subtitle!,
                              '수정: ${_formatDateTime(item.updatedAt)}',
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            switch (item.type) {
                              case DocumentType.statementForm:
                              // ✅ 같은 Navigator 트리에서 풀스크린 페이지 push → 스트림 유지
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const UserStatementFormPage(),
                                    fullscreenDialog: true,
                                  ),
                                );
                                break;

                              case DocumentType.generic:
                              // 아직 미구현 문서 유형
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('아직 미구현 문서 유형입니다.')),
                                );
                                break;
                            }
                          },
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

  static String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.black54),
            const SizedBox(height: 8),
            Text(
              '표시할 서류가 없어요',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '필요한 서류가 생기면 이곳에 목록이 나타납니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
