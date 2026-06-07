import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _subInk = Color(0xFF101828);
const _subMuted = Color(0xFF667085);
const _subLine = Color(0xFFD8DEE8);
const _subBlue = Color(0xFF2563EB);

class KorKeypadUtils {
  static Widget buildSubLayout(
    List<List<String>> keyRows,
    void Function(String) onKeyTap, {
    required State state,
    required StateSetter setState,
    Map<String, AnimationController>? controllers,
    Map<String, bool>? isPressed,
  }) {
    return Column(
      children: List.generate(keyRows.length, (r) {
        final row = keyRows[r];
        return Expanded(
          child: Row(
            children: List.generate(row.length, (c) {
              final label = row[c];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _buildKeyButton(label, label.isNotEmpty ? () => onKeyTap(label) : null),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  static Widget _buildKeyButton(String key, VoidCallback? onTap) {
    if (key.isEmpty) return const SizedBox.shrink();
    final isBack = key == 'back';
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isBack ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isBack ? _subLine : _subBlue.withOpacity(.18)),
        ),
        child: Text(
          isBack ? '뒤로' : key,
          style: TextStyle(
            color: isBack ? _subMuted : _subInk,
            fontWeight: FontWeight.w900,
            fontSize: isBack ? 14 : 20,
          ),
        ),
      ),
    );
  }
}
