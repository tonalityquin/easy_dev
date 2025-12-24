import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import 'chat_panel.dart';
import '../../../../../utils/snackbar_helper.dart';

// ✅ Google Sheets 기반 채팅 서비스
import '../../../../../services/sheet_chat_service.dart';

/// 좌측 상단(11시) 라벨 텍스트
const String _screenTag = 'chat';

/// 11시 라벨 위젯 (LocationManagement와 동일 스타일)
Widget _buildScreenTag(BuildContext context) {
  final base = Theme.of(context).textTheme.labelSmall;
  final style = (base ??
      const TextStyle(
        fontSize: 11,
        color: Colors.black54,
        fontWeight: FontWeight.w600,
      ))
      .copyWith(
    color: Colors.black54,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  return SafeArea(
    top: true,
    bottom: false,
    left: false,
    right: false,
    child: IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: $_screenTag',
            child: Text(_screenTag, style: style),
          ),
        ),
      ),
    ),
  );
}

/// 공개 채팅 바텀시트 열기 (Sheets 기반)
void chatBottomSheet(BuildContext context) {
  // roomId는 더 이상 “채팅 저장/필터링”에 사용하지 않음.
  // 다만, 기존 UX와 동일하게 currentArea가 비어있으면 진입 막고 싶다면 아래 로직 유지.
  final currentUser = context.read<UserState>().user;
  final String? scopeKey = currentUser?.currentArea?.trim();

  if (scopeKey == null || scopeKey.isEmpty) {
    showSelectedSnackbar(context, '채팅을 위해 currentArea가 설정되어야 합니다.');
    return;
  }

  // ✅ 서비스 시작(idempotent) - 실제 스프레드시트 ID는 서비스가 SharedPreferences에서 읽음
  SheetChatService.instance.start(scopeKey);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false, // 내부에서 SafeArea 처리
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withOpacity(0.25),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) {
      final inset = MediaQuery.of(ctx).viewInsets.bottom; // 키보드 패딩
      final size = MediaQuery.of(ctx).size;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: inset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: size.height, // ★ 화면 전체 높이
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white, // ★ 전면 흰 배경
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 16,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: true,
                  left: false,
                  right: false,
                  bottom: false,
                  child: Stack(
                    children: [
                      // 11시 라벨 오버레이
                      _buildScreenTag(ctx),

                      // 본문
                      Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // ── 헤더
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                            child: Column(
                              children: [
                                // 드래그 핸들
                                Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const SizedBox(width: 4),
                                    const Icon(Icons.forum, size: 20, color: Colors.black87),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        '구역 채팅',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '닫기',
                                      icon: const Icon(Icons.close),
                                      onPressed: () => Navigator.of(ctx).pop(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFEAEAEA),
                          ),

                          // ── 콘텐츠(가변 영역)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: ChatPanel(scopeKey: scopeKey),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 채팅 열기 버튼 (Sheets 기반)
/// - currentArea 변화 감지: select 유지(기존 UX 유지)
/// - 서비스 캐시(ValueNotifier) 구독
class ChatOpenButton extends StatelessWidget {
  const ChatOpenButton({super.key});

  @override
  Widget build(BuildContext context) {
    // currentArea 변경 시 자동 리빌드
    final scopeKey = context.select<UserState, String?>(
          (s) => s.user?.currentArea?.trim(),
    );

    if (scopeKey == null || scopeKey.isEmpty) {
      return const SizedBox.shrink();
    }

    // ✅ 안전하게 서비스 시작(idempotent)
    SheetChatService.instance.start(scopeKey);

    return ValueListenableBuilder<SheetChatState>(
      valueListenable: SheetChatService.instance.state,
      builder: (context, st, _) {
        final latestMsg = st.latest?.text ?? '';
        final text = latestMsg.length > 20 ? '${latestMsg.substring(0, 20)}...' : latestMsg;
        final label = latestMsg.isEmpty ? '채팅 열기' : text;

        // 흰색 배경 + 라운드 + 테두리로 깔끔한 버튼
        return ElevatedButton(
          onPressed: () => chatBottomSheet(context),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  st.error != null ? '채팅 오류' : label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
