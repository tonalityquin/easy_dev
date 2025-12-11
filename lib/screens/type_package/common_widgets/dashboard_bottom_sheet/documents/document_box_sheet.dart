import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../backup/backup_form_page.dart';
import '../end_works/end_work_report_dialog.dart';
import '../work_start_report/sections/dashboard_end_report_form_page.dart';
import '../work_start_report/sections/dashboard_start_report_form_page.dart';
import 'document_inventory_repository.dart';
import 'user_statement_form_page.dart';
import 'document_item.dart';
import '../shares/parking_handover_share_page.dart';
import '../resignation/resignation_form_page.dart'; // ✅ 사직서 페이지 import 추가

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
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scrollController) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              const _SheetHandle(),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5EB),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const _BinderSpine(),
                      const VerticalDivider(
                        width: 0,
                        thickness: 0.6,
                        color: Color(0xFFE0D7C5),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const _SheetHeader(),
                            const Divider(
                              height: 1,
                              thickness: 0.8,
                              color: Color(0xFFE5DFD0),
                            ),
                            Expanded(
                              child: StreamBuilder<List<DocumentItem>>(
                                stream: repo.streamForUser(userState),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final items = snapshot.data ?? const <DocumentItem>[];

                                  if (items.isEmpty) {
                                    return const _EmptyState();
                                  }

                                  return ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return _DocumentListItem(
                                        item: item,
                                        onTap: () {
                                          switch (item.type) {
                                            case DocumentType.statementForm:
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => const UserStatementFormPage(),
                                                  fullscreenDialog: true,
                                                ),
                                              );
                                              break;

                                            case DocumentType.handoverForm:
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => const ParkingHandoverSharePage(),
                                                  fullscreenDialog: true,
                                                ),
                                              );
                                              break;

                                            case DocumentType.workEndReportForm:
                                              // 동일 type 안에서 id 로 역할 분리
                                              if (item.id == 'template-end-work-report') {
                                                // ✅ 업무 종료 보고서 → 기존 집계/서버 보고 시트
                                                showEndReportDialog(context);
                                              } else if (item.id == 'template-work-end-report') {
                                                // ✅ 퇴근 보고 양식 → 새로 만든 업무 종료/퇴근 보고 화면
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => const DashboardEndReportFormPage(),
                                                    fullscreenDialog: true,
                                                  ),
                                                );
                                              }
                                              // 그 외 id는 현재 아무 동작 없음
                                              break;

                                            case DocumentType.workStartReportForm:
                                              // ✅ 업무 시작 보고 양식 → 새로 만든 화면으로 이동
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => const DashboardStartReportFormPage(),
                                                  fullscreenDialog: true,
                                                ),
                                              );
                                              break;

                                            case DocumentType.generic:
                                              // ✅ generic 문서 중 연차(결근) 지원 신청서 연결
                                              if (item.id == 'template-annual-leave-application') {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => const BackupFormPage(),
                                                    fullscreenDialog: true,
                                                  ),
                                                );
                                              }
                                              // ✅ generic 문서 중 사직서 연결
                                              else if (item.id == 'template-resignation-letter') {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => const ResignationFormPage(),
                                                    fullscreenDialog: true,
                                                  ),
                                                );
                                              }
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
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 상단 드래그 핸들
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 6,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.brown.withOpacity(0.25),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// 문서철 왼쪽 스파인(바인더 느낌)
class _BinderSpine extends StatelessWidget {
  const _BinderSpine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      decoration: const BoxDecoration(
        color: Color(0xFFE0D7C5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.brown[200],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 상단 헤더(문서철 제목/설명)
class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.brown.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.folder_special_outlined,
              size: 22,
              color: Colors.brown,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 문서철',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4A3A28),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '보고서와 인수인계, 경위서 양식을 모아두었어요.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A7A65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            icon: const Icon(
              Icons.close,
              size: 20,
              color: Color(0xFF7A6A55),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// 각각의 문서를 카드 형태로 보여주는 위젯
class _DocumentListItem extends StatelessWidget {
  final DocumentItem item;
  final VoidCallback onTap;

  const _DocumentListItem({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColorForItem(item); // ← item 기준 색상
    final typeLabel = _typeLabelForItem(item); // ← item 기준 라벨
    final iconData = _iconForType(item.type);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 좌측 컬러 인덱스 바
              Container(
                width: 6,
                height: 80,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: accentColor.withOpacity(0.15),
                        child: Icon(
                          iconData,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF3C342A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _buildSubtitle(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF7A6F63),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    typeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: accentColor.darken(0.1),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFF9A8C7A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 90,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE5D4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const Icon(
                  Icons.folder_open,
                  size: 40,
                  color: Color(0xFFB09A7A),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '표시할 서류가 없어요',
              style: textTheme.titleMedium?.copyWith(
                color: const Color(0xFF4A3A28),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '필요한 서류 양식이 생성되면\n이 문서철에 차곡차곡 꽂혀요.',
              style: textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8A7A65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────
/// 디자인/텍스트 헬퍼 함수 모음
/// ─────────────────────────

String _buildSubtitle(DocumentItem item) {
  final parts = <String>[];
  if (item.subtitle != null && item.subtitle!.isNotEmpty) {
    parts.add(item.subtitle!);
  }
  parts.add('수정: ${_formatDateTime(item.updatedAt)}');
  return parts.join(' • ');
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

/// 기본 type 기준 색상
Color _accentColorForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return const Color(0xFF4F9A94); // 청록
    case DocumentType.workEndReportForm:
      return const Color(0xFFEF6C53); // 기본 오렌지/레드
    case DocumentType.handoverForm:
      return const Color(0xFF8D6E63); // 브라운
    case DocumentType.statementForm:
      return const Color(0xFF5C6BC0); // 블루
    case DocumentType.generic:
      return const Color(0xFF757575);
  }
}

/// type + id 기준으로 색상 세분화 (퇴근 vs 업무 종료)
Color _accentColorForItem(DocumentItem item) {
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') {
      // 퇴근 보고 양식: 기존 오렌지톤
      return const Color(0xFFEF6C53);
    }
    if (item.id == 'template-end-work-report') {
      // 업무 종료 보고서: 좀 더 진한 레드톤
      return const Color(0xFFD84315);
    }
  }
  return _accentColorForType(item.type);
}

IconData _iconForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return Icons.wb_sunny_outlined;
    case DocumentType.workEndReportForm:
      return Icons.nights_stay_outlined;
    case DocumentType.handoverForm:
      return Icons.swap_horiz;
    case DocumentType.statementForm:
      return Icons.description_outlined;
    case DocumentType.generic:
      return Icons.insert_drive_file_outlined;
  }
}

/// type + id 기준으로 라벨을 세분화
String _typeLabelForItem(DocumentItem item) {
  if (item.type == DocumentType.workEndReportForm) {
    if (item.id == 'template-work-end-report') {
      return '퇴근 보고';
    }
    if (item.id == 'template-end-work-report') {
      return '업무 종료 보고';
    }
  }
  return _typeLabelForType(item.type);
}

String _typeLabelForType(DocumentType type) {
  switch (type) {
    case DocumentType.workStartReportForm:
      return '업무 시작 보고';
    case DocumentType.workEndReportForm:
      // 기본값(위에서 id별로 override 가능)
      return '퇴근/업무 종료';
    case DocumentType.handoverForm:
      return '업무 인수인계';
    case DocumentType.statementForm:
      return '경위서';
    case DocumentType.generic:
      return '기타 문서';
  }
}

/// Color 확장: 약간 어둡게
extension _ColorShadeExtension on Color {
  Color darken(double amount) {
    assert(amount >= 0 && amount <= 1);
    final f = 1 - amount;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }
}
