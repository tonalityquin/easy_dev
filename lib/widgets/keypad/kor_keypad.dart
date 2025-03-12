import 'package:flutter/material.dart';
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
class _KorKeypadState extends State<KorKeypad> {
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
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFef7FF),
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: activeSubLayout == null ? _buildMainLayout() : _buildActiveSubLayout(),
    );
  }
  Widget _buildMainLayout() {
    return buildSubLayout(
      [
        ['ㄱ', 'ㄴ', 'ㄷ'],
        ['ㄹ', 'ㅁ', 'ㅂ'],
        ['ㅅ', 'ㅇ', 'ㅈ'],
        ['지우기', 'ㅎ', 'Reset'],
      ],
      _handleMainKeyTap,
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
    setState(() {
      if (keyToSubLayout.containsKey(key)) {
        activeSubLayout = keyToSubLayout[key];
        print('서브 레이아웃 활성화: $activeSubLayout');
      } else if (key == '지우기') {
        widget.controller.clear();
        print('지우기 버튼 눌림, controller 초기화');
      } else if (key == 'Reset' && widget.onReset != null) {
        widget.onReset!();
        print('Reset 호출');
      } else {
        _processKeyInput(key);
      }
    });
  }
  void _handleSubKeyTap(String key) {
    setState(() {
      if (key == 'back') {
        activeSubLayout = null;
        print('서브 레이아웃 복귀: 메인 레이아웃으로 전환');
      } else {
        _processKeyInput(key);
      }
    });
  }
  void _processKeyInput(String key) {
    setState(() {
      widget.controller.text = key;
      print('입력 처리: $key, controller.text = ${widget.controller.text}');
      if (widget.controller.text.isNotEmpty && widget.onComplete != null) {
        Future.microtask(() {
          widget.onComplete!();
        });
      }
    });
  }
}
Widget buildSubLayout(List<List<String>> keyRows, Function(String) onKeyTap) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: keyRows.map((row) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: row.map((key) {
          return buildKeyButton(key, key.isNotEmpty ? () => onKeyTap(key) : null);
        }).toList(),
      );
    }).toList(),
  );
}
Widget buildKeyButton(String key, VoidCallback? onTap) {
  return Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.grey),
        ),
        child: Center(
          child: Text(
            key,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ),
  );
}
