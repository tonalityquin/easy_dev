// lib/screens/simple_package/sections/documents/simple_payment_document_sheet.dart

import 'package:flutter/material.dart';

/// 팀원용 Simple 모드에서 사용하는 "결재 서류 선택" 바텀시트
///
/// - 상단 핸들, 왼쪽 바인더 스파인, 카드 디자인 등은
///   simple_document_box_sheet.dart 와 동일한 톤/스타일 유지
/// - 내용은 단순히 2개의 결재 서류 액션으로 구성
///   1) 출퇴근 서류 결재
///   2) 휴게시간 서류 결재
Future<void> openSimplePaymentDocumentSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PaymentDocumentSheet(),
  );
}

class _PaymentDocumentSheet extends StatelessWidget {
  const _PaymentDocumentSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      // 거의 전체 화면에 가깝게 열리도록 설정
      initialChildSize: 0.96,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (ctx, scrollController) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
                            const _PaymentSheetHeader(),
                            const Divider(
                              height: 1,
                              thickness: 0.8,
                              color: Color(0xFFE5DFD0),
                            ),
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 12,
                                ),
                                children: const [
                                  _PaymentActionItem(
                                    icon: Icons.access_time,
                                    title: '출퇴근 서류 결재',
                                    description:
                                    '출근·퇴근 기록과 관련된 결재 서류를 작성하거나 제출합니다.',
                                    type: _PaymentActionType.workAttendance,
                                  ),
                                  SizedBox(height: 10),
                                  _PaymentActionItem(
                                    icon: Icons.free_breakfast,
                                    title: '휴게시간 서류 결재',
                                    description:
                                    '휴게시간 사용·변경과 관련된 결재 서류를 작성합니다.',
                                    type: _PaymentActionType.breakTime,
                                  ),
                                ],
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
        margin: const EdgeInsets.only(bottom: 10, top: 8),
        decoration: BoxDecoration(
          color: Colors.brown.withOpacity(0.25),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// 문서철 왼쪽 스파인(바인더 느낌) — 기존 문서철과 동일한 스타일
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

/// 상단 헤더(제목/설명) — 결재 서류 선택용 텍스트로 변경
class _PaymentSheetHeader extends StatelessWidget {
  const _PaymentSheetHeader();

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
              Icons.receipt_long,
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
                  '결재 서류 선택',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4A3A28),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '출퇴근·휴게시간 관련 결재 서류를 선택해 작성할 수 있어요.',
                  maxLines: 2,
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

/// 결재 액션 종류
enum _PaymentActionType {
  workAttendance, // 출퇴근 서류 결재
  breakTime, // 휴게시간 서류 결재
}

/// 각각의 결재 서류 액션을 카드 형태로 보여주는 위젯
class _PaymentActionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final _PaymentActionType type;

  const _PaymentActionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.type,
  });

  Color get _accentColor {
    switch (type) {
      case _PaymentActionType.workAttendance:
        return const Color(0xFF4F9A94); // 출퇴근: 청록
      case _PaymentActionType.breakTime:
        return const Color(0xFFF2A93B); // 휴게: 옐로우
    }
  }

  IconData get _chevronIcon => Icons.chevron_right;

  String get _pillLabel {
    switch (type) {
      case _PaymentActionType.workAttendance:
        return '출퇴근 결재';
      case _PaymentActionType.breakTime:
        return '휴게시간 결재';
    }
  }

  void _onTap(BuildContext context) {
    // TODO: 실제 결재 서류 작성/목록 화면으로 라우팅
    //  예: AppRoutes.workApprovalSheet, AppRoutes.breakTimeApprovalSheet 등
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          type == _PaymentActionType.workAttendance
              ? '출퇴근 서류 결재 화면은 아직 연결되지 않았습니다.'
              : '휴게시간 서류 결재 화면은 아직 연결되지 않았습니다.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => _onTap(context),
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
                      backgroundColor: accentColor.withOpacity(0.12),
                      child: Icon(
                        icon,
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
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF3C342A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF7A6F63),
                            ),
                          ),
                          const SizedBox(height: 6),
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
                                  _pillLabel,
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
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                _chevronIcon,
                size: 22,
                color: const Color(0xFF9A8C7A),
              ),
            ),
          ],
        ),
      ),
    );
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
