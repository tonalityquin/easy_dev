import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _keyInk = Color(0xFF101828);
const _keyMuted = Color(0xFF667085);
const _keyLine = Color(0xFFD8DEE8);
const _keyPanel = Color(0xFFFFFFFF);
const _keyBlue = Color(0xFF2563EB);

class NumKeypad extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final bool enableDigitModeSwitch;
  final VoidCallback? onReset;

  const NumKeypad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onChangeFrontDigitMode,
    this.enableDigitModeSwitch = false,
    this.onReset,
  });

  List<String> _lastRowKeys() {
    if (enableDigitModeSwitch) return ['두자리', '0', '세자리'];
    if (onReset != null) return ['처음', '0', '삭제'];
    return ['', '0', '삭제'];
  }

  void _handleKeyTap(String key) {
    HapticFeedback.selectionClick();
    if (key.isEmpty) return;
    if (key == '두자리') {
      onChangeFrontDigitMode?.call(false);
      return;
    }
    if (key == '세자리') {
      onChangeFrontDigitMode?.call(true);
      return;
    }
    if (key == '처음') {
      onReset?.call();
      return;
    }
    if (key == '삭제') {
      if (controller.text.isNotEmpty) {
        controller.text = controller.text.substring(0, controller.text.length - 1);
      }
      return;
    }
    if (controller.text.length < maxLength) {
      controller.text += key;
      if (controller.text.length == maxLength) {
        Future.microtask(() => onComplete?.call());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      _lastRowKeys(),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: _keyPanel,
        border: Border(top: BorderSide(color: _keyLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: row.map((label) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _KeyButton(
                      label: label,
                      isUtility: label.length > 1,
                      onTap: () => _handleKeyTap(label),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.isUtility,
    required this.onTap,
  });

  final String label;
  final bool isUtility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = label.isEmpty;
    return InkWell(
      onTap: empty ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: empty
              ? Colors.transparent
              : isUtility
                  ? const Color(0xFFF1F5F9)
                  : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: empty ? null : Border.all(color: isUtility ? _keyLine : _keyBlue.withOpacity(.18)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isUtility ? _keyMuted : _keyInk,
            fontWeight: FontWeight.w900,
            fontSize: isUtility ? 14 : 20,
          ),
        ),
      ),
    );
  }
}
