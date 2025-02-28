import 'package:flutter/material.dart';

class PlateSearchDialog extends StatefulWidget {
  final void Function(String) onSearch;

  const PlateSearchDialog({
    super.key,
    required this.onSearch,
  });

  @override
  State<PlateSearchDialog> createState() => _PlateSearchDialogState();
}

class _PlateSearchDialogState extends State<PlateSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _enteredNumber = "";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(''),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔹 사용자가 입력한 번호를 실시간으로 표시
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            alignment: Alignment.center,
            child: Text(
              _enteredNumber.isNotEmpty ? _enteredNumber : "",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          // 🔹 입력 필드
          TextField(
            controller: _searchController,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '번호판 뒷 4자리 입력'),
            onChanged: (value) {
              setState(() {
                _enteredNumber = value;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            widget.onSearch(_searchController.text);
            Navigator.pop(context);
          },
          child: const Text('검색'),
        ),
      ],
    );
  }
}
