// lib/screens/head_package/labor_guide_page.dart
import 'package:flutter/material.dart';

import 'labors/statement_form_page.dart';

/// 회사 노무 가이드
/// - asBottomSheet=true: 최상단까지 차오르는 전체 화면 바텀시트 UI
/// - [LaborGuidePage.showAsBottomSheet] 헬퍼로 간편 호출
class LaborGuidePage extends StatelessWidget {
  const LaborGuidePage({super.key, this.asBottomSheet = false});

  /// true면 AppBar 없는 시트 전용 헤더(핸들/닫기)를 사용
  final bool asBottomSheet;

  /// 전체 화면 바텀시트로 열기(권장)
  static Future<T?> showAsBottomSheet<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: const _FullHeightBottomSheetFrame(
            child: LaborGuidePage(asBottomSheet: true),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withOpacity(.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '근로 기준, 휴가/휴일, 초과근무, 서식 다운로드 등 노무 관련 정보를 제공합니다.',
              style: text.bodyMedium?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('근로시간/연장근로 안내'),
            subtitle: const Text('법정 근로시간, 연장/야간/휴일근로 개념'),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.beach_access_outlined),
            title: const Text('연차휴가/대체휴무'),
            subtitle: const Text('발생 기준, 사용 절차, 정산'),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.attach_file_outlined),
            title: const Text('신청/보고 서식'),
            subtitle: const Text('연차신청서, 휴직신청서, 야근보고서 등'),
            onTap: () {},
          ),

          // 경위서 양식 연결 (페이지 푸시 유지)
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('경위서 양식'),
            subtitle: const Text('사건/사고 경위 작성 및 제출'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StatementFormPage()),
              );
            },
          ),
        ],
      ),
    );

    // 페이지 모드: 기존 Scaffold 유지
    if (!asBottomSheet) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('회사 노무 가이드'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
          ),
        ),
        body: body,
      );
    }

    // 바텀시트 모드: 시트 전용 헤더 + 본문 + (🔧 사용 예시) 상단 액션
    return _SheetScaffold(
      title: '회사 노무 가이드',
      onClose: () => Navigator.of(context).maybePop(),
      body: body,
      // 🔧 trailingActions를 실제 전달 → unused_element_parameter 경고 해결
      trailingActions: [
        IconButton(
          tooltip: '경위서 양식',
          icon: const Icon(Icons.edit_note_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatementFormPage()),
            );
          },
        ),
      ],
    );
  }
}

/// ===== “전체 화면” 바텀시트 프레임 =====
/// - 상/하 SafeArea, 둥근 모서리, 배경 투명 + 그림자 포함
class _FullHeightBottomSheetFrame extends StatelessWidget {
  const _FullHeightBottomSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 1.0, // ⬅️ 최상단까지
      widthFactor: 1.0,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: DecoratedBox(
            decoration: const BoxDecoration(boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 8,
                color: Color(0x33000000),
                offset: Offset(0, 8),
              ),
            ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.white,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 바텀시트 전용 스캐폴드 =====
/// - AppBar 대체(핸들 + 타이틀 + 닫기 버튼)
/// - body 전용, 필요 시 trailingActions 표시
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.onClose,
    required this.body,
    this.trailingActions,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget>? trailingActions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            // 상단 핸들
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // 헤더(타이틀/닫기)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingActions != null) ...trailingActions!,
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 본문 스크롤
            Expanded(child: body),
            const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }
}
