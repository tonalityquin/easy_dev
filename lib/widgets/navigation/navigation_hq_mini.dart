import 'package:flutter/material.dart';

class HqMiniNavigation extends StatefulWidget {
  final double height;
  final List<IconData> icons;
  final List<String>? labels;
  final Function(bool isAscending)? onSortToggle;
  final void Function(int index)? onIconTapped;
  final Color? backgroundColor;
  final double iconSize;
  final int currentIndex;

  const HqMiniNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.labels,
    this.onSortToggle,
    this.onIconTapped,
    this.backgroundColor = Colors.white,
    this.iconSize = 24.0,
    this.currentIndex = 0,
  });

  @override
  HqMiniNavigationState createState() => HqMiniNavigationState();
}

class HqMiniNavigationState extends State<HqMiniNavigation> {
  bool isAscending = true;

  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending;
    });
    widget.onSortToggle?.call(isAscending);
  }

  Widget _buildIcon(IconData iconData, int index) {
    final cs = Theme.of(context).colorScheme;

    final isSortIcon = iconData == Icons.sort;
    final isSelected = widget.currentIndex == index;

    final Color selectedColor = cs.primary;                // Deep Blue base
    final Color unselectedColor = cs.onSurfaceVariant;     // Deep Blue dark(유사)
    final Color iconColor = isSelected ? selectedColor : unselectedColor;
    final Color labelColor = iconColor;

    final Widget baseIcon = isSortIcon
        ? Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationX(isAscending ? 0 : 3.14159),
      child: Icon(Icons.sort, color: iconColor),
    )
        : Icon(iconData, color: iconColor);

    final Widget iconButton = IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: SizedBox(
          key: ValueKey('${isSortIcon}_${isAscending}_$isSelected'),
          width: widget.iconSize,
          height: widget.iconSize,
          child: Center(child: baseIcon),
        ),
      ),
      onPressed: () {
        if (isSortIcon) {
          toggleSortOrder();
        } else {
          widget.onIconTapped?.call(index);
        }
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: widget.iconSize,
      splashRadius: widget.iconSize * .75,
    );

    if (widget.labels != null && widget.labels!.length > index) {
      return SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.18 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: iconButton,
            ),
            const SizedBox(height: 2),
            Text(
              widget.labels![index],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    } else {
      return iconButton;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final double totalHeight = widget.labels != null ? widget.height + 24 : widget.height;
    final Color bg = widget.backgroundColor ?? Colors.white;

    return Container(
      height: totalHeight,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: cs.surfaceTint.withOpacity(.20), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widget.icons.asMap().entries
            .map((entry) => _buildIcon(entry.value, entry.key))
            .toList(),
      ),
    );
  }
}
