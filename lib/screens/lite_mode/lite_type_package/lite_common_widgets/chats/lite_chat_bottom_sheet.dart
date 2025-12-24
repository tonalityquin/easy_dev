import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/snackbar_helper.dart';

import 'lite_chat_panel.dart';
import '../../../../../services/sheet_chat_service.dart';

const String _screenTag = 'chat';

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

void liteChatBottomSheet(BuildContext context) {
  final currentUser = context.read<UserState>().user;
  final String? scopeKey = currentUser?.currentArea?.trim(); // 영역 전환 감지용으로만 사용

  if (scopeKey == null || scopeKey.isEmpty) {
    showSelectedSnackbar(context, '채팅을 위해 currentArea가 설정되어야 합니다.');
    return;
  }

  // ✅ 서비스 시작(idempotent)
  SheetChatService.instance.start(scopeKey);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withOpacity(0.25),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) {
      final inset = MediaQuery.of(ctx).viewInsets.bottom;
      final size = MediaQuery.of(ctx).size;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: inset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: size.height,
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
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
                      _buildScreenTag(ctx),
                      Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                            child: Column(
                              children: [
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
                                    Expanded(
                                      child: Text(
                                        '구역 채팅 (${scopeKey.trim()})',
                                        style: const TextStyle(
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
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: LiteChatPanel(scopeKey: scopeKey),
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

class ChatOpenButton extends StatelessWidget {
  const ChatOpenButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scopeKey = context.select<UserState, String?>(
          (s) => s.user?.currentArea?.trim(),
    );

    if (scopeKey == null || scopeKey.isEmpty) {
      return const SizedBox.shrink();
    }

    SheetChatService.instance.start(scopeKey);

    return ValueListenableBuilder<SheetChatState>(
      valueListenable: SheetChatService.instance.state,
      builder: (context, st, _) {
        final latest = st.latest?.text ?? '';
        final text = latest.length > 20 ? '${latest.substring(0, 20)}...' : latest;
        final label = latest.isEmpty ? '채팅 열기' : text;

        return ElevatedButton(
          onPressed: () => liteChatBottomSheet(context),
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
