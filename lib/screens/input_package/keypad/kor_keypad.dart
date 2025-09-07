import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

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

class KorKeypad extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;

  const KorKeypad({
    super.key,
    required this.controller,
    this.onComplete,
    this.onReset,
  });

  @override
  State<KorKeypad> createState() => _KorKeypadState();
}

class _KorKeypadState extends State<KorKeypad> with TickerProviderStateMixin {
  String? activeSubLayout;

  final Map<String, String> keyToSubLayout = {
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

  final Map<String, AnimationController> _controllers = {};
  final Map<String, bool> _isPressed = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12),
      child: activeSubLayout == null
          ? _buildMainLayout()
          : _buildActiveSubLayout(),
    );
  }

  Widget _buildMainLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(['ㄱ', 'ㄴ', 'ㄷ']),
        _buildRow(['ㄹ', 'ㅁ', 'ㅂ']),
        _buildRow(['ㅅ', 'ㅇ', 'ㅈ']),
        _buildRow(['공란', 'ㅎ', '공란']),
      ],
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

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildKeyButton(key)).toList(),
    );
  }

  Widget _buildKeyButton(String key) {
    if (key.isEmpty) {
      return const Expanded(child: SizedBox());
    }

    _controllers.putIfAbsent(
      key,
          () => AnimationController(
        duration: const Duration(milliseconds: 80),
        vsync: this,
        lowerBound: 0.0,
        upperBound: 0.1,
      ),
    );
    _isPressed.putIfAbsent(key, () => false);

    final controller = _controllers[key]!;
    final animation = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            setState(() => _isPressed[key] = true);
            controller.forward();
          },
          onTapUp: (_) {
            setState(() => _isPressed[key] = false);
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) controller.reverse();
            });
            _handleMainKeyTap(key);
          },
          onTapCancel: () {
            setState(() => _isPressed[key] = false);
            controller.reverse();
          },
          child: ScaleTransition(
            scale: animation,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              decoration: BoxDecoration(
                color: _isPressed[key]! ? Colors.lightBlue[100] : Colors.grey[50],
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Center(
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleMainKeyTap(String key) {
    if (keyToSubLayout.containsKey(key)) {
      setState(() {
        activeSubLayout = keyToSubLayout[key];
      });
    } else if (key == '공란') {
      widget.onComplete?.call();
    } else {
      _processKeyInput(key);
    }
  }

  void _handleSubKeyTap(String key) {
    if (key == 'back') {
      setState(() {
        activeSubLayout = null;
      });
    } else {
      _processKeyInput(key);
    }
  }

  void _processKeyInput(String key) {
    setState(() {
      widget.controller.text += key;
      widget.onComplete?.call();
    });
  }
}
