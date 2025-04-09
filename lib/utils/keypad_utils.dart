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
    final isReset = key == 'Reset';
    final isErase = key == '지우기';

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8.0),
            splashColor: Colors.purple.withValues(alpha: 0.2),
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
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isReset
                        ? Colors.red
                        : isErase
                        ? Colors.orange
                        : Colors.black,
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
