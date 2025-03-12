import 'package:flutter/material.dart';

class MiniNavigation extends StatefulWidget {
  final double height;
  final List<IconData> icons;
  final Function(bool isAscending)? onSortToggle;
  final void Function(int index)? onIconTapped;

  const MiniNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.onSortToggle,
    this.onIconTapped,
  });

  @override
  _MiniNavigationState createState() => _MiniNavigationState();
}

class _MiniNavigationState extends State<MiniNavigation> {
  bool isAscending = true;

  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending;
    });
    widget.onSortToggle?.call(isAscending);
  }

  void _handleIconTap(int index, IconData iconData) {
    if (iconData == Icons.sort) {
      toggleSortOrder();
    } else {
      widget.onIconTapped?.call(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: Colors.blue[200],
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: widget.icons.asMap().entries.map((entry) {
              final index = entry.key;
              final iconData = entry.value;
              return IconButton(
                icon: iconData == Icons.sort
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationX(isAscending ? 0 : 3.14159),
                        child: Icon(iconData),
                      )
                    : Icon(iconData),
                onPressed: () => _handleIconTap(index, iconData),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: widget.height * 0.6,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
