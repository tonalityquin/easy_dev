import 'package:flutter/material.dart';

class HqMiniNavigation extends StatefulWidget {
  final double height;
  final List<IconData> icons;
  final Function(bool isAscending)? onSortToggle;
  final void Function(int index)? onIconTapped;
  final Color? backgroundColor;
  final double iconSize;

  const HqMiniNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.onSortToggle,
    this.onIconTapped,
    this.backgroundColor = Colors.white,
    this.iconSize = 24.0,
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
    return IconButton(
      icon: isSortIcon
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationX(isAscending ? 0 : 3.14159),
              child: Icon(Icons.sort),
            )
          : Icon(iconData),
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: widget.backgroundColor,
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: widget.icons.asMap().entries.map((entry) {
              return _buildIcon(entry.value, entry.key);
            }).toList(),
          ),
        ),
      ],
    );
  }
}
