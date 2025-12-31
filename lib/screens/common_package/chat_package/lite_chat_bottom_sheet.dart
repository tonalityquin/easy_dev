import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../services/sheet_chat_service.dart';

import 'lite_chat_panel.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ Lite: 말풍선 팝오버(키보드 대응 + 화면 밖 침범 방지)
/// - 팝오버 열림: acquire + chatUiVisible=true → 고빈도 폴링(3초)
/// - 팝오버 닫힘: (버튼 lease가 남아있으면) chatUiVisible=false → 저빈도 폴링(12초)
/// ─────────────────────────────────────────────────────────────

enum _TailDirection { up, down }

Future<void> _showChatPopoverLite({
  required BuildContext rootContext,
  required GlobalKey targetKey,
  required String scopeKey,
  required ValueNotifier<bool> popoverOpen,
}) async {
  FocusScope.of(rootContext).unfocus();

  final targetCtx = targetKey.currentContext;
  if (targetCtx == null) {
    showFailedSnackbar(rootContext, '채팅 버튼 위치를 찾지 못해 팝오버를 열 수 없습니다.');
    return;
  }

  final ro = targetCtx.findRenderObject();
  if (ro is! RenderBox) {
    showFailedSnackbar(rootContext, '채팅 버튼 렌더 정보를 찾지 못해 팝오버를 열 수 없습니다.');
    return;
  }

  final Offset btnTopLeft = ro.localToGlobal(Offset.zero);
  final Size btnSize = ro.size;
  final Rect btnRect = btnTopLeft & btnSize;

  const double margin = 12;
  const double radius = 16;
  const double tailH = 12;
  const double tailW = 22;
  const double gap = 10;

  const double minReadable = 220;
  const double hardMin = 180;

  popoverOpen.value = true;

  // ✅ 팝오버가 열려있는 동안만 (추가) acquire (고빈도 모드)
  try {
    await SheetChatService.instance.acquire(scopeKey, forceFetch: true);
  } catch (e) {
    popoverOpen.value = false;
    showFailedSnackbar(rootContext, '채팅 초기화 실패: $e');
    return;
  }

  // ✅ 채팅 UI가 열려있는 동안 알림 억제 + 고빈도 폴링
  SheetChatService.instance.setChatUiVisible(true);

  try {
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
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final media = MediaQuery.of(ctx);
                final screen = media.size;

                final double keyboard = media.viewInsets.bottom;
                final bool keyboardVisible = keyboard > 0;

                final double safeTop = media.padding.top + margin;
                final double safeBottom =
                    screen.height - (media.padding.bottom + keyboard + margin);

                final double usableHeight =
                (safeBottom - safeTop - gap).clamp(0.0, double.infinity);

                final double maxWidth =
                (screen.width - margin * 2).clamp(260.0, double.infinity);
                final double width = math.min(640.0, maxWidth);

                final double desiredHeight =
                (screen.height * 0.65).clamp(260.0, 560.0);
                final double cappedDesired = math.min(desiredHeight, usableHeight);

                final double availableAbove =
                (btnRect.top - safeTop - gap).clamp(0.0, double.infinity);
                final double availableBelow =
                (safeBottom - btnRect.bottom - gap).clamp(0.0, double.infinity);

                final double heightAbove = math.min(cappedDesired, availableAbove);
                final double heightBelow = math.min(cappedDesired, availableBelow);

                _TailDirection dir;
                double height;

                if (keyboardVisible) {
                  if (heightAbove >= hardMin) {
                    dir = _TailDirection.down;
                    height = heightAbove;
                  } else {
                    dir = _TailDirection.up;
                    height = heightBelow;
                  }
                } else {
                  if (heightAbove >= minReadable) {
                    dir = _TailDirection.down;
                    height = heightAbove;
                  } else if (heightBelow >= minReadable) {
                    dir = _TailDirection.up;
                    height = heightBelow;
                  } else {
                    if (heightAbove >= heightBelow) {
                      dir = _TailDirection.down;
                      height = heightAbove;
                    } else {
                      dir = _TailDirection.up;
                      height = heightBelow;
                    }
                  }
                }

                height = height.clamp(hardMin, math.max(hardMin, usableHeight));

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

                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {},
                        child: _ChatPopoverShellLite(
                          width: width,
                          height: height,
                          scopeKey: scopeKey,
                          onClose: () => Navigator.of(ctx).pop(),
                          radius: radius,
                          tailHeight: tailH,
                          tailWidth: tailW,
                          tailCenterX: tailCenterX,
                          tailDirection: dir,
                        ),
                      ),
                    ),
                  ],
                );
              },
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
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  } finally {
    popoverOpen.value = false;

    // ✅ 팝오버 종료 시: 알림 억제 해제 + 저빈도 폴링로 전환(버튼 lease가 남아있으면)
    SheetChatService.instance.setChatUiVisible(false);

    // ✅ 팝오버 acquire 해제(버튼 lease가 있으면 refCount=1로 유지)
    SheetChatService.instance.release();
  }
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
                Expanded(
                  child: Text(
                    '구역 채팅 (${scopeKey.trim()})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis,
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
              child: LiteChatPanel(scopeKey: scopeKey),
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
          child: Material(color: Colors.transparent, child: child),
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

/// ─────────────────────────────────────────────────────────────
/// ✅ Lite: 채팅 열기 버튼
/// - 변경 포인트: 버튼이 화면에 존재하는 동안 "알림 감시용 acquire(저빈도 폴링)" 1개 유지
/// ─────────────────────────────────────────────────────────────

class ChatOpenButtonLite extends StatefulWidget {
  const ChatOpenButtonLite({super.key});

  @override
  State<ChatOpenButtonLite> createState() => _ChatOpenButtonLiteState();
}

class _ChatOpenButtonLiteState extends State<ChatOpenButtonLite> {
  final GlobalKey _targetKey = GlobalKey();
  final ValueNotifier<bool> _popoverOpen = ValueNotifier<bool>(false);

  // ✅ 알림 감시용 lease 상태
  bool _watchLeaseHeld = false;
  String _watchScopeKey = '';

  // ✅ build 재진입/스코프 변경에서 acquire 호출이 겹치지 않도록 직렬화
  Future<void> _watchLeaseOp = Future.value();

  void _syncWatchLease({required String? scopeKey}) {
    _watchLeaseOp = _watchLeaseOp.then((_) async {
      if (!mounted) return;

      final next = (scopeKey ?? '').trim();

      // scopeKey가 비었으면 lease 해제
      if (next.isEmpty) {
        if (_watchLeaseHeld) {
          _watchLeaseHeld = false;
          _watchScopeKey = '';
          SheetChatService.instance.release();
        }
        return;
      }

      // 동일 scope면 유지
      if (_watchLeaseHeld && _watchScopeKey == next) {
        return;
      }

      // scope 변경/최초 시작:
      // "새 scope acquire 성공 → 그 다음 기존 lease release" 순서로 refCount=0 갭을 방지
      try {
        await SheetChatService.instance.acquire(next, forceFetch: true);

        if (!mounted) {
          // dispose 후에 acquire가 완료된 경우 누수 방지
          SheetChatService.instance.release();
          return;
        }

        if (_watchLeaseHeld) {
          SheetChatService.instance.release();
        } else {
          _watchLeaseHeld = true;
        }

        _watchScopeKey = next;
      } catch (_) {
        // 감시용 acquire 실패 시에는 조용히 유지/무시 (팝오버 오픈 시에는 기존처럼 snackbar 노출)
      }
    });
  }

  @override
  void dispose() {
    // ✅ 버튼이 사라지면 감시 lease 해제 (in-flight acquire는 위에서 누수 방지 처리)
    if (_watchLeaseHeld) {
      _watchLeaseHeld = false;
      _watchScopeKey = '';
      SheetChatService.instance.release();
    }
    _popoverOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scopeKey = context.select<UserState, String?>((s) => s.user?.currentArea?.trim());

    // ✅ 프레임 이후에 watch lease 동기화 (build에서 await 금지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncWatchLease(scopeKey: scopeKey);
    });

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
              child: Text('채팅 열기', overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ],
        ),
      );
    }

    // ✅ 버튼 프리뷰는 state 기반 (팝오버 닫힘 상태에서는 12초 폴링으로 갱신됨)
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
                popoverOpen: _popoverOpen,
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
