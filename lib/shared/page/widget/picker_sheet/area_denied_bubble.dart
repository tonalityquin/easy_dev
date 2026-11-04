import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/models/account_role_diagnostics.dart';

class AreaDeniedBubble extends StatefulWidget {
  const AreaDeniedBubble({
    super.key,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
  });

  final Widget child;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  static _AreaDeniedBubbleState? _active;

  static void show(BuildContext context, String message) {
    context.findAncestorStateOfType<_AreaDeniedBubbleState>()?.show(message);
  }

  static void dismissAll() {
    _active?._hide();
  }

  @override
  State<AreaDeniedBubble> createState() => _AreaDeniedBubbleState();
}

class _AreaDeniedBubbleState extends State<AreaDeniedBubble>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
  );
  OverlayEntry? _entry;
  Timer? _dismissTimer;
  ScrollPosition? _scrollPosition;
  int _revision = 0;
  bool _reduceMotion = false;
  Size? _lastScreenSize;
  double? _lastScaledFontSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    if (media == null) return;
    final screenSize = media.size;
    final fontSize = media.textScaler.scale(12);
    final changed = (_lastScreenSize != null && _lastScreenSize != screenSize) ||
        (_lastScaledFontSize != null && _lastScaledFontSize != fontSize);
    _lastScreenSize = screenSize;
    _lastScaledFontSize = fontSize;
    if (changed && _entry != null) {
      final revision = _revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _revision) _hide(animate: false);
      });
    }
  }

  @override
  void didChangeMetrics() {
    _hide(animate: false);
  }

  void _handleScrollingChanged() {
    if (_entry == null || _scrollPosition?.isScrollingNotifier.value != true) {
      return;
    }
    AccountRoleDiagnostics.record('area_denied_bubble_hidden reason=scroll');
    _hide(animate: false);
  }

  void _attachScrollPosition() {
    _detachScrollPosition();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return;
    _scrollPosition = position;
    position.isScrollingNotifier.addListener(_handleScrollingChanged);
    _handleScrollingChanged();
  }

  void _detachScrollPosition() {
    final position = _scrollPosition;
    _scrollPosition = null;
    position?.isScrollingNotifier.removeListener(_handleScrollingChanged);
  }

  void show(String message) {
    final value = message.trim();
    if (!mounted || value.isEmpty) return;
    _dismissTimer?.cancel();
    _revision++;
    final media = MediaQuery.maybeOf(context);
    _reduceMotion = media?.disableAnimations ?? false;
    final targetBox = context.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayRender = overlay?.context.findRenderObject();
    if (targetBox is! RenderBox ||
        !targetBox.hasSize ||
        overlay == null ||
        overlayRender is! RenderBox ||
        !overlayRender.hasSize) {
      _hide(animate: false);
      return;
    }

    const edgeMargin = 12.0;
    const gap = 8.0;
    const tailWidth = 18.0;
    const tailHeight = 8.0;
    const iconWidth = 17.0;
    const iconGap = 8.0;
    const horizontalPadding = 26.0;
    const verticalPadding = 22.0;
    const borderWidth = 2.0;

    final overlaySize = overlayRender.size;
    final overlayMedia = MediaQuery.maybeOf(overlay.context) ?? media;
    final padding = overlayMedia?.padding ?? EdgeInsets.zero;
    final insets = overlayMedia?.viewInsets ?? EdgeInsets.zero;
    final safeLeft = math.min(
      overlaySize.width,
      math.max(0.0, padding.left + edgeMargin),
    );
    final safeRight = math.max(
      safeLeft,
      overlaySize.width - padding.right - edgeMargin,
    );
    final safeTop = math.min(
      overlaySize.height,
      math.max(0.0, padding.top + edgeMargin),
    );
    final safeBottom = math.max(
      safeTop,
      overlaySize.height - math.max(padding.bottom, insets.bottom) - edgeMargin,
    );
    final safeHeight = math.max(0.0, safeBottom - safeTop);
    if (safeHeight < 32.0) {
      _hide(animate: false);
      return;
    }
    final maxWidth = math.min(320.0, math.max(1.0, safeRight - safeLeft));
    final background = widget.backgroundColor ?? Theme.of(context).colorScheme.surface;
    final foreground = widget.foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    final border = widget.borderColor ?? Theme.of(context).colorScheme.outlineVariant;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ) ??
        TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: Directionality.of(context),
      textScaler: media?.textScaler ?? TextScaler.noScaling,
    );
    final reservedWidth = horizontalPadding + iconWidth + iconGap + borderWidth;
    painter.layout(maxWidth: math.max(1.0, maxWidth - reservedWidth));
    final width = math.min(
      maxWidth,
      math.max(math.min(120.0, maxWidth), painter.width + reservedWidth),
    );
    painter.layout(maxWidth: math.max(1.0, width - reservedWidth));
    final naturalBodyHeight =
        math.max(iconWidth, painter.height) + verticalPadding + borderWidth;
    final naturalBubbleHeight = naturalBodyHeight + tailHeight;
    painter.dispose();

    final position = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayRender,
    );
    final target = position & targetBox.size;
    final anchorX = target.center.dx;
    final left = (anchorX - width / 2)
        .clamp(safeLeft, math.max(safeLeft, safeRight - width))
        .toDouble();
    final roomAbove = math.max(0.0, target.top - safeTop - gap);
    final roomBelow = math.max(0.0, safeBottom - target.bottom - gap);
    final below = roomAbove >= naturalBubbleHeight
        ? false
        : roomBelow >= naturalBubbleHeight || roomBelow >= roomAbove;
    final sideRoom = below ? roomBelow : roomAbove;
    final fittingHeight = sideRoom >= math.min(72.0, safeHeight)
        ? sideRoom
        : safeHeight;
    final bubbleHeight = math.min(
      naturalBubbleHeight,
      math.max(1.0, math.min(safeHeight, fittingHeight)),
    );
    final bodyHeight = math.max(1.0, bubbleHeight - tailHeight);
    final closeButtonSize = math.min(32.0, math.max(14.0, bodyHeight * 0.4));
    final heightConstrained = bubbleHeight + 0.5 < naturalBubbleHeight;
    final preferredTop =
        below ? target.bottom + gap : target.top - gap - bubbleHeight;
    final top = preferredTop
        .clamp(safeTop, math.max(safeTop, safeBottom - bubbleHeight))
        .toDouble();
    final anchorY = below ? target.bottom : target.top;
    final tailLeft = (anchorX - left - tailWidth / 2)
        .clamp(16.0, math.max(16.0, width - tailWidth - 16.0))
        .toDouble();
    final adjustedHorizontal = (left - (anchorX - width / 2)).abs() > 0.5;
    final adjustedVertical = (top - preferredTop).abs() > 0.5;

    if (AreaDeniedBubble._active != this) {
      AreaDeniedBubble._active?._hide(animate: false);
    }
    _removeEntry();
    AreaDeniedBubble._active = this;
    final messageContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 17,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(value, style: style),
            ),
          ),
        ],
      ),
    );
    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned.fill(
        child: IgnorePointer(
          ignoring: !heightConstrained,
          child: Stack(
            children: [
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: below ? Alignment.bottomCenter : Alignment.topCenter,
                followerAnchor: Alignment.topLeft,
                offset: Offset(left - anchorX, top - anchorY),
                child: FadeTransition(
                  opacity: _animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, below ? -0.02 : 0.02),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    )),
                    child: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (below)
                              Padding(
                                padding: EdgeInsets.only(left: tailLeft),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: CustomPaint(
                                    size: const Size(tailWidth, tailHeight),
                                    painter: _AreaBubbleTailPainter(
                                      fill: background,
                                      border: border,
                                      pointsUp: true,
                                    ),
                                  ),
                                ),
                              ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.16),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: heightConstrained
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        height: bodyHeight,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: IconButton(
                                                onPressed: () {
                                                  AccountRoleDiagnostics.record(
                                                    'area_denied_bubble_hidden reason=manual',
                                                  );
                                                  _hide(animate: false);
                                                },
                                                icon: Icon(
                                                  Icons.close_rounded,
                                                  size: math.min(18.0, closeButtonSize - 2),
                                                  color: foreground,
                                                  semanticLabel: '안내 닫기',
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(
                                                  minWidth: closeButtonSize,
                                                  minHeight: closeButtonSize,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Scrollbar(
                                                child: SingleChildScrollView(
                                                  physics: const ClampingScrollPhysics(),
                                                  child: messageContent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : messageContent,
                            ),
                            if (!below)
                              Padding(
                                padding: EdgeInsets.only(left: tailLeft),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: CustomPaint(
                                    size: const Size(tailWidth, tailHeight),
                                    painter: _AreaBubbleTailPainter(
                                      fill: background,
                                      border: border,
                                      pointsUp: false,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _attachScrollPosition();
    if (_entry == null) return;
    if (_reduceMotion) {
      _animation.value = 1;
    } else {
      _animation.forward(from: 0);
    }
    AccountRoleDiagnostics.record(
      'area_denied_bubble_shown below=$below '
      'adjustedX=$adjustedHorizontal adjustedY=$adjustedVertical '
      'heightConstrained=$heightConstrained',
    );
    if (!heightConstrained) {
      _dismissTimer = Timer(const Duration(seconds: 2), _hide);
    }
  }

  void _hide({bool animate = true}) {
    _dismissTimer?.cancel();
    final revision = ++_revision;
    if (_entry == null) return;
    if (!animate || _reduceMotion) {
      _removeEntry();
      return;
    }
    _animation.reverse().then((_) {
      if (mounted && revision == _revision) _removeEntry();
    });
  }

  void _removeEntry() {
    _detachScrollPosition();
    final entry = _entry;
    _entry = null;
    if (identical(AreaDeniedBubble._active, this)) {
      AreaDeniedBubble._active = null;
    }
    entry?.remove();
    entry?.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissTimer?.cancel();
    _removeEntry();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: widget.child,
    );
  }
}

class _AreaBubbleTailPainter extends CustomPainter {
  const _AreaBubbleTailPainter({
    required this.fill,
    required this.border,
    required this.pointsUp,
  });

  final Color fill;
  final Color border;
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = Path()
      ..moveTo(0, pointsUp ? size.height : 0)
      ..lineTo(size.width / 2, pointsUp ? 0 : size.height)
      ..lineTo(size.width, pointsUp ? size.height : 0)
      ..close();
    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      shape,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _AreaBubbleTailPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.pointsUp != pointsUp;
}
