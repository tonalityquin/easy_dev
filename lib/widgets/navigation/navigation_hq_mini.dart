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
    final isSortIcon = iconData == Icons.sort;
    final isSelected = widget.currentIndex == index;

    final iconColor = isSelected ? Colors.green : Colors.grey;
    final labelColor = isSelected ? Colors.green : Colors.grey;

    final iconWidget = IconButton(
      icon: isSortIcon
          ? Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationX(isAscending ? 0 : 3.14159),
        child: Icon(Icons.sort, color: iconColor),
      )
          : Icon(iconData, color: iconColor),
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
    );

    if (widget.labels != null && widget.labels!.length > index) {
      return SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: iconWidget,
            ),
            const SizedBox(height: 2),
            Text(
              widget.labels![index],
              style: TextStyle(fontSize: 10, color: labelColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    } else {
      return iconWidget;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double totalHeight = widget.labels != null ? widget.height + 24 : widget.height;

    return Container(
      color: widget.backgroundColor,
      height: totalHeight,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widget.icons.asMap().entries.map((entry) {
          return _buildIcon(entry.value, entry.key);
        }).toList(),
      ),
    );
  }
}
