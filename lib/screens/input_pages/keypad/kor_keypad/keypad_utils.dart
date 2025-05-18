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
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8.0),
            splashColor: Colors.purple.withAlpha(50),
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey),
              ),
              child: Center(
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black, // 단일 색상 처리
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
