import 'package:flutter/material.dart';

class KorKeypadUtils {
  static Widget buildSubLayout(List<List<String>> keyRows, Function(String) onKeyTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keyRows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((key) {
            return buildKeyButton(
              key,
              key.isNotEmpty ? () => onKeyTap(key) : null,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  static Widget buildKeyButton(String key, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.black, width: 2.0),
          ),
          child: Center(
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
