// lib/screens/service_mode/type_package/common_widgets/chats/chat_bottom_sheet.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/snackbar_helper.dart';

// ✅ Google Sheets 기반 채팅 서비스
import '../../../../../services/sheet_chat_service.dart';

import 'chat_panel.dart';

/// 좌측 상단(11시) 라벨 텍스트
const String _screenTag = 'chat';

/// ✅ 읽기 전용 마스킹 높이(입력/전송 영역 가림)
const double _kBottomMaskHeight = 78.0;

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

/// ✅ 읽기 전용 마스킹(입력/전송 UI를 가리고 터치까지 차단)
class _ReadOnlyChatBody extends StatelessWidget {
  const _ReadOnlyChatBody({
    required this.scopeKey,
    this.bottomMaskHeight = _kBottomMaskHeight,
  });

  final String scopeKey;
  final double bottomMaskHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ✅ 목록이 입력영역에 가리지 않도록 bottom padding 확보
        Padding(
          padding: EdgeInsets.only(bottom: bottomMaskHeight),
          child: ChatPanel(scopeKey: scopeKey),
        ),

        // ✅ 입력/전송 영역을 “가림 + 터치 차단”
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AbsorbPointer(
            absorbing: true,
            child: Container(
              height: bottomMaskHeight,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFEAEAEA), width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '읽기 전용 - 입력/전송은 허용되지 않습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withOpacity(.65),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// (기존) 풀시트 바텀시트 - ✅ 읽기 전용
void chatBottomSheet(BuildContext context) {
  final currentUser = context.read<UserState>().user;
  final String? scopeKey = currentUser?.currentArea?.trim();

  if (scopeKey == null || scopeKey.isEmpty) {
    showSelectedSnackbar(context, '채팅을 위해 currentArea가 설정되어야 합니다.');
    return;
  }

  SheetChatService.instance.start(scopeKey);
  FocusScope.of(context).unfocus();

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
                                    const Icon(Icons.forum,
                                        size: 20, color: Colors.black87),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F7),
                                        borderRadius:
                                        BorderRadius.circular(999),
                                        border: Border.all(
                                            color: Colors.black
                                                .withOpacity(.06)),
                                      ),
                                      child: const Text(
                                        '읽기 전용',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
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
                              color: Color(0xFFEAEAEA)),
                          Expanded(
                            child: Padding(
                              padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: _ReadOnlyChatBody(
                                scopeKey: scopeKey,
                                // ✅ 경고 제거: 호출부에서 실제로 값을 전달
                                bottomMaskHeight: _kBottomMaskHeight,
                              ),
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

/// ─────────────────────────────────────────────────────────────
/// ✅ 말풍선 팝오버(화면 밖 침범 방지: left/top clamp + 꼬리 위치 동기화)
/// ─────────────────────────────────────────────────────────────

enum _TailDirection { up, down }

Future<void> _showChatReadOnlyPopover({
  required BuildContext rootContext,
  required GlobalKey targetKey,
  required String scopeKey,
}) async {
  FocusScope.of(rootContext).unfocus();
  SheetChatService.instance.start(scopeKey);

  final targetCtx = targetKey.currentContext;
  if (targetCtx == null) {
    chatBottomSheet(rootContext);
    return;
  }

  final ro = targetCtx.findRenderObject();
  if (ro is! RenderBox) {
    chatBottomSheet(rootContext);
    return;
  }

  final media = MediaQuery.of(rootContext);
  final screen = media.size;

  // ✅ 안전 여백(상/하: safe area + margin)
  const double margin = 12;
  final double safeTop = media.padding.top + margin;
  final double safeBottom = screen.height - (media.padding.bottom + margin);

  // ✅ 버튼 Rect(전역 좌표)
  final Offset btnTopLeft = ro.localToGlobal(Offset.zero);
  final Size btnSize = ro.size;
  final Rect btnRect = btnTopLeft & btnSize;

  // ✅ 말풍선 기본 토큰
  const double radius = 16;
  const double tailH = 12;
  const double tailW = 22;

  // ✅ 폭/높이 산정(화면에 맞게 제한)
  final double maxWidth =
  (screen.width - margin * 2).clamp(260.0, double.infinity);
  final double width = math.min(640.0, maxWidth); // 상한
  final double desiredHeight =
  (screen.height * 0.65).clamp(260.0, 560.0);

  // 위/아래 여유 공간 계산(꼬리+간격 포함)
  const double gap = 10;
  final double availableAbove =
  (btnRect.top - safeTop - gap).clamp(0.0, double.infinity);
  final double availableBelow =
  (safeBottom - btnRect.bottom - gap).clamp(0.0, double.infinity);

  // 우선 “위로” 열되, 부족하면 “아래로” fallback
  final double heightAbove = math.min(desiredHeight, availableAbove);
  final double heightBelow = math.min(desiredHeight, availableBelow);

  _TailDirection dir;
  double height;

  // 최소 가독 높이(너무 작으면 풀시트)
  const double minReadable = 220;

  if (heightAbove >= minReadable) {
    dir = _TailDirection.down; // 말풍선이 버튼 위에 있으므로 꼬리는 아래로
    height = heightAbove;
  } else if (heightBelow >= minReadable) {
    dir = _TailDirection.up; // 말풍선이 버튼 아래에 있으므로 꼬리는 위로
    height = heightBelow;
  } else {
    chatBottomSheet(rootContext);
    return;
  }

  // ✅ left/top 계산 후 화면 경계로 clamp
  double left = (btnRect.center.dx - width / 2);
  left = left.clamp(margin, screen.width - width - margin);

  double top;
  if (dir == _TailDirection.down) {
    // 위에 뜨는 말풍선: 버튼 top 기준으로 위쪽 배치
    top = (btnRect.top - gap - height);
    top = top.clamp(safeTop, safeBottom - height);
  } else {
    // 아래에 뜨는 말풍선: 버튼 bottom 기준으로 아래쪽 배치
    top = (btnRect.bottom + gap);
    top = top.clamp(safeTop, safeBottom - height);
  }

  // ✅ 꼬리가 버튼을 향하도록 tailCenterX(말풍선 내부 좌표) 계산
  double tailCenterX = (btnRect.center.dx - left);
  final double minTailX = radius + tailW / 2 + 2;
  final double maxTailX = width - radius - tailW / 2 - 2;
  tailCenterX = tailCenterX.clamp(minTailX, maxTailX);

  await showGeneralDialog<void>(
    context: rootContext,
    barrierDismissible: true,
    barrierLabel: 'chat_popover',
    barrierColor: Colors.black.withOpacity(0.18),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogCtx, __, ___) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(dialogCtx).pop(),
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {}, // 내부 탭은 dismiss 방지
                  child: _ChatPopoverShell(
                    width: width,
                    height: height,
                    scopeKey: scopeKey,
                    onClose: () => Navigator.of(dialogCtx).pop(),
                    radius: radius,
                    tailHeight: tailH,
                    tailWidth: tailW,
                    tailCenterX: tailCenterX,
                    tailDirection: dir,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          alignment: dir == _TailDirection.down
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
}

class _ChatPopoverShell extends StatelessWidget {
  const _ChatPopoverShell({
    required this.width,
    required this.height,
    required this.scopeKey,
    required this.onClose,
    required this.radius,
    required this.tailHeight,
    required this.tailWidth,
    required this.tailCenterX,
    required this.tailDirection,
  });

  final double width;
  final double height;
  final String scopeKey;
  final VoidCallback onClose;

  final double radius;
  final double tailHeight;
  final double tailWidth;
  final double tailCenterX;
  final _TailDirection tailDirection;

  @override
  Widget build(BuildContext context) {
    return _SpeechBubble(
      width: width,
      height: height,
      radius: radius,
      tailHeight: tailHeight,
      tailWidth: tailWidth,
      tailCenterX: tailCenterX,
      tailDirection: tailDirection,
      color: Colors.white,
      borderColor: const Color(0xFFEAEAEA),
      borderWidth: 1,
      shadowColor: const Color(0x26000000),
      shadowElevation: 10,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.forum, size: 18, color: Colors.black87),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '구역 채팅',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black.withOpacity(.06)),
                  ),
                  child: const Text(
                    '읽기 전용',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEAEAEA)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: _ReadOnlyChatBody(
                scopeKey: scopeKey,
                // ✅ 경고 제거: 호출부에서 실제로 값을 전달
                bottomMaskHeight: _kBottomMaskHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// ✅ CustomPainter 기반 말풍선(꼬리 포함) 컨테이너
/// ─────────────────────────────────────────────────────────────

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.width,
    required this.height,
    required this.child,
    required this.radius,
    required this.tailHeight,
    required this.tailWidth,
    required this.tailCenterX,
    required this.tailDirection,
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.shadowColor,
    required this.shadowElevation,
  });

  final double width;
  final double height;
  final Widget child;

  final double radius;
  final double tailHeight;
  final double tailWidth;
  final double tailCenterX;
  final _TailDirection tailDirection;

  final Color color;
  final Color borderColor;
  final double borderWidth;

  final Color shadowColor;
  final double shadowElevation;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SpeechBubblePainter(
        radius: radius,
        tailHeight: tailHeight,
        tailWidth: tailWidth,
        tailCenterX: tailCenterX,
        tailDirection: tailDirection,
        fillColor: color,
        borderColor: borderColor,
        borderWidth: borderWidth,
        shadowColor: shadowColor,
        shadowElevation: shadowElevation,
      ),
      child: ClipPath(
        clipper: _SpeechBubbleClipper(
          radius: radius,
          tailHeight: tailHeight,
          tailWidth: tailWidth,
          tailCenterX: tailCenterX,
          tailDirection: tailDirection,
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Material(
            color: Colors.transparent,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  _SpeechBubblePainter({
    required this.radius,
    required this.tailHeight,
    required this.tailWidth,
    required this.tailCenterX,
    required this.tailDirection,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    required this.shadowColor,
    required this.shadowElevation,
  });

  final double radius;
  final double tailHeight;
  final double tailWidth;
  final double tailCenterX;
  final _TailDirection tailDirection;

  final Color fillColor;
  final Color borderColor;
  final double borderWidth;

  final Color shadowColor;
  final double shadowElevation;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _SpeechBubblePath.build(
      size: size,
      radius: radius,
      tailHeight: tailHeight,
      tailWidth: tailWidth,
      tailCenterX: tailCenterX,
      tailDirection: tailDirection,
    );

    canvas.drawShadow(path, shadowColor, shadowElevation, true);

    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.tailHeight != tailHeight ||
        oldDelegate.tailWidth != tailWidth ||
        oldDelegate.tailCenterX != tailCenterX ||
        oldDelegate.tailDirection != tailDirection ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.shadowColor != shadowColor ||
        oldDelegate.shadowElevation != shadowElevation;
  }
}

class _SpeechBubbleClipper extends CustomClipper<Path> {
  _SpeechBubbleClipper({
    required this.radius,
    required this.tailHeight,
    required this.tailWidth,
    required this.tailCenterX,
    required this.tailDirection,
  });

  final double radius;
  final double tailHeight;
  final double tailWidth;
  final double tailCenterX;
  final _TailDirection tailDirection;

  @override
  Path getClip(Size size) {
    return _SpeechBubblePath.build(
      size: size,
      radius: radius,
      tailHeight: tailHeight,
      tailWidth: tailWidth,
      tailCenterX: tailCenterX,
      tailDirection: tailDirection,
    );
  }

  @override
  bool shouldReclip(covariant _SpeechBubbleClipper oldClipper) {
    return oldClipper.radius != radius ||
        oldClipper.tailHeight != tailHeight ||
        oldClipper.tailWidth != tailWidth ||
        oldClipper.tailCenterX != tailCenterX ||
        oldClipper.tailDirection != tailDirection;
  }
}

class _SpeechBubblePath {
  static Path build({
    required Size size,
    required double radius,
    required double tailHeight,
    required double tailWidth,
    required double tailCenterX,
    required _TailDirection tailDirection,
  }) {
    final double w = size.width;
    final double h = size.height;
    final double r = radius;

    final double halfTailW = tailWidth / 2;

    // 꼬리 base가 라운드 코너에 침범하지 않도록 tailCenterX를 안전 범위로 clamp
    final double minX = r + halfTailW + 2;
    final double maxX = w - r - halfTailW - 2;
    final double tcx = tailCenterX.clamp(minX, maxX);

    final double tailLeftX = tcx - halfTailW;
    final double tailRightX = tcx + halfTailW;

    final Path p = Path();

    if (tailDirection == _TailDirection.down) {
      // ── 꼬리: 아래
      final double bodyBottom = h - tailHeight;

      p.moveTo(r, 0);
      p.lineTo(w - r, 0);
      p.quadraticBezierTo(w, 0, w, r);

      p.lineTo(w, bodyBottom - r);
      p.quadraticBezierTo(w, bodyBottom, w - r, bodyBottom);

      p.lineTo(tailRightX, bodyBottom);
      p.lineTo(tcx, h);
      p.lineTo(tailLeftX, bodyBottom);

      p.lineTo(r, bodyBottom);
      p.quadraticBezierTo(0, bodyBottom, 0, bodyBottom - r);

      p.lineTo(0, r);
      p.quadraticBezierTo(0, 0, r, 0);

      p.close();
      return p;
    } else {
      // ── 꼬리: 위
      final double bodyTop = tailHeight;

      p.moveTo(r, bodyTop);

      p.lineTo(tailLeftX, bodyTop);
      p.lineTo(tcx, 0);
      p.lineTo(tailRightX, bodyTop);

      p.lineTo(w - r, bodyTop);
      p.quadraticBezierTo(w, bodyTop, w, bodyTop + r);

      p.lineTo(w, h - r);
      p.quadraticBezierTo(w, h, w - r, h);

      p.lineTo(r, h);
      p.quadraticBezierTo(0, h, 0, h - r);

      p.lineTo(0, bodyTop + r);
      p.quadraticBezierTo(0, bodyTop, r, bodyTop);

      p.close();
      return p;
    }
  }
}

/// 채팅 열기 버튼 (Sheets 기반)
/// - currentArea 변화 감지: select 유지
/// - 최신 메시지 미리보기 표시
/// - 클릭 시 “말풍선(팝오버)”로 열기(화면 밖 침범 방지)
class ChatOpenButton extends StatefulWidget {
  const ChatOpenButton({super.key});

  @override
  State<ChatOpenButton> createState() => _ChatOpenButtonState();
}

class _ChatOpenButtonState extends State<ChatOpenButton> {
  final GlobalKey _targetKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final scopeKey = context.select<UserState, String?>(
          (s) => s.user?.currentArea?.trim(),
    );

    if (scopeKey == null || scopeKey.isEmpty) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black54,
          disabledBackgroundColor: Colors.white,
          disabledForegroundColor: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum, size: 18),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                '채팅 열기',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      );
    }

    SheetChatService.instance.start(scopeKey);

    return ValueListenableBuilder<SheetChatState>(
      valueListenable: SheetChatService.instance.state,
      builder: (context, st, _) {
        final latestMsg = st.latest?.text ?? '';
        final text =
        latestMsg.length > 20 ? '${latestMsg.substring(0, 20)}...' : latestMsg;
        final label = latestMsg.isEmpty ? '채팅 열기' : text;

        return Container(
          key: _targetKey,
          child: ElevatedButton(
            onPressed: () async {
              await _showChatReadOnlyPopover(
                rootContext: context,
                targetKey: _targetKey,
                scopeKey: scopeKey,
              );
            },
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
          ),
        );
      },
    );
  }
}
