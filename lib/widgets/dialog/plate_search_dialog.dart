import 'package:flutter/material.dart';
import '../keypad/num_keypad.dart'; // 🔹 num_keypad.dart 파일 import

class PlateSearchDialog extends StatefulWidget {
  final Function(String) onSearch;

  const PlateSearchDialog({super.key, required this.onSearch});

  @override
  State<PlateSearchDialog> createState() => _PlateSearchDialogState();
}

class _PlateSearchDialogState extends State<PlateSearchDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("번호판 검색"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 60,
            child: AbsorbPointer( // 핸드폰 가상 키보드 비활성화
              child: TextField(
                controller: _searchController,
                keyboardType: TextInputType.none, // 가상 키보드 비활성화
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "번호판 뒷 4자리",
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          NumKeypad( // 🔹 num_keypad 사용
            controller: _searchController,
            maxLength: 4,
            onComplete: () {
              if (_searchController.text.length == 4) {
                Navigator.of(context).pop();
                widget.onSearch(_searchController.text);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("취소"),
        ),
        TextButton(
          onPressed: () {
            if (_searchController.text.length == 4) {
              Navigator.of(context).pop();
              widget.onSearch(_searchController.text);
            }
          },
          child: const Text("검색"),
        ),
      ],
    );
  }
}
