// lib/screens/lite_mode/lite_type_package/lite_common_widgets/chats/lite_chat_bottom_sheet.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/snackbar_helper.dart';

import '../../../../../services/sheet_chat_service.dart';
import 'simple_chat_panel.dart';

/// 좌측 상단(11시) 라벨 텍스트
const String _screenTag = 'chat';

/// ✅ ReadOnly 마스킹 높이(입력/전송 영역 가림)
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

class _SimpleChatBody extends StatelessWidget {
  const _SimpleChatBody({
    required this.scopeKey,
  });

  final String scopeKey;

  @override
  Widget build(BuildContext context) {
    return SimpleChatPanel(scopeKey: scopeKey);
  }
}

/// - 필요 시 readOnly=true로 사용
class _ReadOnlyLiteChatBody extends StatelessWidget {
  const _ReadOnlyLiteChatBody({
    required this.scopeKey,
    this.bottomMaskHeight = _kBottomMaskHeight,
  });

  final String scopeKey;
  final double bottomMaskHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: bottomMaskHeight),
          child: SimpleChatPanel(scopeKey: scopeKey),
        ),
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

/// ✅ Lite: 풀시트 바텀시트
/// - readOnly=false(기본): LiteChatPanel 모든 기능 사용 가능
/// - readOnly=true: 입력/전송 마스킹(보기만 가능)
void simpleChatBottomSheet(
    BuildContext context, {
      bool readOnly = false,
    }) {
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
                  bottom: true,
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
                                    const Icon(Icons.forum,
                                        size: 20, color: Colors.black87),
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
                                    if (readOnly) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF2F4F7),
                                          borderRadius:
                                          BorderRadius.circular(999),
                                          border: Border.all(
                                            color: Colors.black.withOpacity(.06),
                                          ),
                                        ),
                                        child: const Text(
                                          '읽기 전용',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
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
                              child: readOnly
                                  ? const _ReadOnlyLiteChatBody(
                                scopeKey: '',
                              )
                                  : const _SimpleChatBody(scopeKey: ''),
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
  ).then((_) {
    // no-op
  });
}

/// 위 builder에서 const로 만들기 위해 scopeKey를 나중에 주입하는 방식은 불가하므로,
/// 실제로는 아래와 같이 "비-const"로 바꿔 scopeKey를 전달합니다.
void _showLiteChatBottomSheetInternal(
    BuildContext context, {
      required String scopeKey,
      bool readOnly = false,
    }) {
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
                  bottom: true,
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
                                    const Icon(Icons.forum,
                                        size: 20, color: Colors.black87),
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
                                    if (readOnly) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF2F4F7),
                                          borderRadius:
                                          BorderRadius.circular(999),
                                          border: Border.all(
                                            color: Colors.black.withOpacity(.06),
                                          ),
                                        ),
                                        child: const Text(
                                          '읽기 전용',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
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
                              child: readOnly
                                  ? _ReadOnlyLiteChatBody(
                                scopeKey: scopeKey,
                                bottomMaskHeight: _kBottomMaskHeight,
                              )
                                  : _SimpleChatBody(scopeKey: scopeKey),
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
/// ✅ Lite: 말풍선 팝오버(꼬리 포함) + 화면 밖 침범 방지(clamp)
/// - readOnly=false(기본): 모든 기능 사용 가능
/// - readOnly=true: 입력/전송 마스킹
/// ─────────────────────────────────────────────────────────────

enum _TailDirection { up, down }

Future<void> _showChatPopoverLite({
  required BuildContext rootContext,
  required GlobalKey targetKey,
  required String scopeKey,
  bool readOnly = false,
}) async {
  FocusScope.of(rootContext).unfocus();
  SheetChatService.instance.start(scopeKey);

  final targetCtx = targetKey.currentContext;
  if (targetCtx == null) {
    _showLiteChatBottomSheetInternal(rootContext,
        scopeKey: scopeKey, readOnly: readOnly);
    return;
  }

  final ro = targetCtx.findRenderObject();
  if (ro is! RenderBox) {
    _showLiteChatBottomSheetInternal(rootContext,
        scopeKey: scopeKey, readOnly: readOnly);
    return;
  }

  final media = MediaQuery.of(rootContext);
  final screen = media.size;

  const double margin = 12;
  final double safeTop = media.padding.top + margin;
  final double safeBottom = screen.height - (media.padding.bottom + margin);

  final Offset btnTopLeft = ro.localToGlobal(Offset.zero);
  final Size btnSize = ro.size;
  final Rect btnRect = btnTopLeft & btnSize;

  const double radius = 16;
  const double tailH = 12;
  const double tailW = 22;

  final double maxWidth =
  (screen.width - margin * 2).clamp(260.0, double.infinity);
  final double width = math.min(640.0, maxWidth);
  final double desiredHeight =
  (screen.height * 0.65).clamp(260.0, 560.0);

  const double gap = 10;
  final double availableAbove =
  (btnRect.top - safeTop - gap).clamp(0.0, double.infinity);
  final double availableBelow =
  (safeBottom - btnRect.bottom - gap).clamp(0.0, double.infinity);

  final double heightAbove = math.min(desiredHeight, availableAbove);
  final double heightBelow = math.min(desiredHeight, availableBelow);

  const double minReadable = 220;

  _TailDirection dir;
  double height;

  if (heightAbove >= minReadable) {
    dir = _TailDirection.down; // 말풍선이 버튼 위 / 꼬리 아래
    height = heightAbove;
  } else if (heightBelow >= minReadable) {
    dir = _TailDirection.up; // 말풍선이 버튼 아래 / 꼬리 위
    height = heightBelow;
  } else {
    _showLiteChatBottomSheetInternal(rootContext,
        scopeKey: scopeKey, readOnly: readOnly);
    return;
  }

  double left = (btnRect.center.dx - width / 2);
  left = left.clamp(margin, screen.width - width - margin);

  double top;
  if (dir == _TailDirection.down) {
    top = (btnRect.top - gap - height);
    top = top.clamp(safeTop, safeBottom - height);
  } else {
    top = (btnRect.bottom + gap);
    top = top.clamp(safeTop, safeBottom - height);
  }

  double tailCenterX = (btnRect.center.dx - left);
  final double minTailX = radius + tailW / 2 + 2;
  final double maxTailX = width - radius - tailW / 2 - 2;
  tailCenterX = tailCenterX.clamp(minTailX, maxTailX);

  await showGeneralDialog<void>(
    context: rootContext,
    barrierDismissible: true,
    barrierLabel: 'chat_popover_lite',
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
                  child: _ChatPopoverShellLite(
                    width: width,
                    height: height,
                    scopeKey: scopeKey,
                    onClose: () => Navigator.of(dialogCtx).pop(),
                    radius: radius,
                    tailHeight: tailH,
                    tailWidth: tailW,
                    tailCenterX: tailCenterX,
                    tailDirection: dir,
                    readOnly: readOnly,
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
          alignment:
          dir == _TailDirection.down ? Alignment.bottomCenter : Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
}

class _ChatPopoverShellLite extends StatelessWidget {
  const _ChatPopoverShellLite({
    required this.width,
    required this.height,
    required this.scopeKey,
    required this.onClose,
    required this.radius,
    required this.tailHeight,
    required this.tailWidth,
    required this.tailCenterX,
    required this.tailDirection,
    required this.readOnly,
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

  final bool readOnly;

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
                Expanded(
                  child: Text(
                    '구역 채팅 (${scopeKey.trim()})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (readOnly) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black.withOpacity(.06)),
                    ),
                    child: const Text(
                      '읽기 전용',
                      style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
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
              child: readOnly
                  ? _ReadOnlyLiteChatBody(
                scopeKey: scopeKey,
                bottomMaskHeight: _kBottomMaskHeight,
              )
                  : _SimpleChatBody(scopeKey: scopeKey),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// ✅ CustomPainter 기반 말풍선(꼬리 포함)
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

    final double minX = r + halfTailW + 2;
    final double maxX = w - r - halfTailW - 2;
    final double tcx = tailCenterX.clamp(minX, maxX);

    final double tailLeftX = tcx - halfTailW;
    final double tailRightX = tcx + halfTailW;

    final Path p = Path();

    if (tailDirection == _TailDirection.down) {
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

/// ✅ Lite: 채팅 열기 버튼(팝오버 우선, 공간 부족 시 풀시트로 fallback)
class ChatOpenButtonSimple extends StatefulWidget {
  const ChatOpenButtonSimple({
    super.key,
    this.readOnly = false,
  });

  final bool readOnly;

  @override
  State<ChatOpenButtonSimple> createState() => _ChatOpenButtonSimpleState();
}

class _ChatOpenButtonSimpleState extends State<ChatOpenButtonSimple> {
  final GlobalKey _targetKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final scopeKey =
    context.select<UserState, String?>((s) => s.user?.currentArea?.trim());

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
        final latest = st.latest?.text ?? '';
        final text = latest.length > 20 ? '${latest.substring(0, 20)}...' : latest;
        final label = latest.isEmpty ? '채팅 열기' : text;

        return Container(
          key: _targetKey,
          child: ElevatedButton(
            onPressed: () async {
              await _showChatPopoverLite(
                rootContext: context,
                targetKey: _targetKey,
                scopeKey: scopeKey,
                readOnly: widget.readOnly,
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
