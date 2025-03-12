import 'package:flutter/material.dart';

class LocationContainer extends StatelessWidget {
  final String location;
  final bool isSelected;
  final VoidCallback onTap;

  const LocationContainer({
    Key? key,
    required this.location,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,
          border: Border.all(color: Colors.black, width: 2.0),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          location,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
