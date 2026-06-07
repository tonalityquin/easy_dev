import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kor_keypad/kor_0.dart';
import 'kor_keypad/kor_1.dart';
import 'kor_keypad/kor_2.dart';
import 'kor_keypad/kor_3.dart';
import 'kor_keypad/kor_4.dart';
import 'kor_keypad/kor_5.dart';
import 'kor_keypad/kor_6.dart';
import 'kor_keypad/kor_7.dart';
import 'kor_keypad/kor_8.dart';
import 'kor_keypad/kor_9.dart';

const _korInk = Color(0xFF101828);
const _korMuted = Color(0xFF667085);
const _korLine = Color(0xFFD8DEE8);
const _korPanel = Color(0xFFFFFFFF);
const _korBlue = Color(0xFF2563EB);

class KorKeypad extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;
  final int maxLength;
  final double height;

  const KorKeypad({
    super.key,
    required this.controller,
    this.onComplete,
    this.onReset,
    this.maxLength = 1,
    this.height = 248.0,
  });

  @override
  State<KorKeypad> createState() => _KorKeypadState();
}

class _KorKeypadState extends State<KorKeypad> {
  String? activeSubLayout;

  final Map<String, String> keyToSubLayout = const {
    'ㄱ': 'kor1',
    'ㄴ': 'kor2',
    'ㄷ': 'kor3',
    'ㄹ': 'kor4',
    'ㅁ': 'kor5',
    'ㅂ': 'kor6',
    'ㅅ': 'kor7',
    'ㅇ': 'kor8',
    'ㅈ': 'kor9',
    'ㅎ': 'kor0',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '한글 키패드',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: _korPanel,
          border: Border(top: BorderSide(color: _korLine)),
        ),
        child: SizedBox(
          height: widget.height,
          child: activeSubLayout == null ? _buildMainLayout() : _buildActiveSubLayout(),
        ),
      ),
    );
  }

  Widget _buildMainLayout() {
    const rows = [
      ['ㄱ', 'ㄴ', 'ㄷ'],
      ['ㄹ', 'ㅁ', 'ㅂ'],
      ['ㅅ', 'ㅇ', 'ㅈ'],
      ['공란', 'ㅎ', '지움'],
    ];
    return Column(
      children: rows.map((row) {
        return Expanded(
          child: Row(
            children: row.map((label) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _KorMainButton(
                    label: label,
                    onTap: () => _handleMainKeyTap(label),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActiveSubLayout() {
    switch (activeSubLayout) {
      case 'kor0':
        return Kor0(onKeyTap: _handleSubKeyTap);
      case 'kor1':
        return Kor1(onKeyTap: _handleSubKeyTap);
      case 'kor2':
        return Kor2(onKeyTap: _handleSubKeyTap);
      case 'kor3':
        return Kor3(onKeyTap: _handleSubKeyTap);
      case 'kor4':
        return Kor4(onKeyTap: _handleSubKeyTap);
      case 'kor5':
        return Kor5(onKeyTap: _handleSubKeyTap);
      case 'kor6':
        return Kor6(onKeyTap: _handleSubKeyTap);
      case 'kor7':
        return Kor7(onKeyTap: _handleSubKeyTap);
      case 'kor8':
        return Kor8(onKeyTap: _handleSubKeyTap);
      case 'kor9':
        return Kor9(onKeyTap: _handleSubKeyTap);
      default:
        return const SizedBox.shrink();
    }
  }

  void _handleMainKeyTap(String key) {
    HapticFeedback.selectionClick();
    if (key == '지움') {
      widget.controller.clear();
      return;
    }
    if (keyToSubLayout.containsKey(key)) {
      setState(() => activeSubLayout = keyToSubLayout[key]);
    } else if (key == '공란') {
      Future.microtask(() => widget.onComplete?.call());
    }
  }

  void _handleSubKeyTap(String key) {
    HapticFeedback.selectionClick();
    if (key == 'back') {
      setState(() => activeSubLayout = null);
      return;
    }
    if (widget.controller.text.length >= widget.maxLength) {
      Future.microtask(() => widget.onComplete?.call());
      return;
    }
    setState(() => widget.controller.text += key);
    Future.microtask(() => widget.onComplete?.call());
  }
}

class _KorMainButton extends StatelessWidget {
  const _KorMainButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final utility = label == '공란' || label == '지움';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: utility ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: utility ? _korLine : _korBlue.withOpacity(.18)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: utility ? _korMuted : _korInk,
            fontWeight: FontWeight.w900,
            fontSize: utility ? 14 : 20,
          ),
        ),
      ),
    );
  }
}
