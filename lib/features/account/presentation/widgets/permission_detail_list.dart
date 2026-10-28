import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/account_permission_policy.dart';

class PermissionDetailList extends StatelessWidget {
  const PermissionDetailList({
    super.key,
    required this.permissions,
    this.selected,
    this.onToggle,
    this.enabled = true,
    this.height,
  });

  final List<String> permissions;
  final Set<String>? selected;
  final ValueChanged<String>? onToggle;
  final bool enabled;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (permissions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('표시할 권한이 없습니다.'),
      );
    }
    final list = ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: permissions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final permission = permissions[index];
        return PermissionDetailRow(
          key: ValueKey<String>(permission),
          permission: permission,
          selected: selected == null ? null : selected!.contains(permission),
          enabled: enabled,
          onChanged: onToggle == null ? null : (_) => onToggle!(permission),
        );
      },
    );
    if (height == null) return list;
    return SizedBox(height: height, child: list);
  }
}

class PermissionDetailRow extends StatefulWidget {
  const PermissionDetailRow({
    super.key,
    required this.permission,
    this.selected,
    this.enabled = true,
    this.onChanged,
  });

  final String permission;
  final bool? selected;
  final bool enabled;
  final ValueChanged<bool?>? onChanged;

  @override
  State<PermissionDetailRow> createState() => _PermissionDetailRowState();
}

class _PermissionDetailRowState extends State<PermissionDetailRow> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _bubble;

  void _hideBubble() {
    final entry = _bubble;
    _bubble = null;
    entry?.remove();
    entry?.dispose();
  }

  void _showBubble() {
    _hideBubble();
    if (!mounted) return;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final origin = render.localToGlobal(Offset.zero);
    final below = origin.dy < 210;
    final screen = MediaQuery.sizeOf(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final theme = Theme.of(context);
    final width = math.min(370.0, math.max(180.0, screen.width - 32));
    _bubble = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: below ? Alignment.bottomLeft : Alignment.topLeft,
          followerAnchor: below ? Alignment.topLeft : Alignment.bottomLeft,
          offset: Offset(0, below ? 8 : -8),
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: .96 + .04 * value,
                  alignment: below ? Alignment.topLeft : Alignment.bottomLeft,
                  child: child,
                ),
              ),
              child: Material(
                elevation: 10,
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AccountPermissionPolicy.permissionLabel(widget.permission),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AccountPermissionPolicy.permissionDetail(widget.permission),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.permission,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_bubble!);
  }

  @override
  void didUpdateWidget(covariant PermissionDetailRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.permission != widget.permission) _hideBubble();
  }

  @override
  void dispose() {
    _hideBubble();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interactive = widget.selected != null && widget.onChanged != null && widget.enabled;
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _showBubble(),
        onLongPressEnd: (_) => _hideBubble(),
        onLongPressCancel: _hideBubble,
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: interactive ? () => widget.onChanged!(!widget.selected!) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.selected != null)
                    Checkbox(
                      value: widget.selected!,
                      onChanged: interactive ? widget.onChanged : null,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.verified_user_outlined, size: 20),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AccountPermissionPolicy.permissionLabel(widget.permission),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          AccountPermissionPolicy.permissionSummary(widget.permission),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.permission,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
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
