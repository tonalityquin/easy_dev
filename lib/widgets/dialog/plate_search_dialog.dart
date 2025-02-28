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
  final FocusNode _focusNode = FocusNode(); // ✅ 자동 포커스를 위한 FocusNode 추가

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus(); // ✅ 다이얼로그가 열리면 자동으로 키보드 올라오게 설정
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose(); // ✅ FocusNode 해제
    super.dispose();
  }

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
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, child) {
                return Text(
                  value.text.isNotEmpty ? value.text : "",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          // 🔹 입력 필드 (4자리 제한)
          TextField(
            controller: _searchController,
            maxLength: 4,
            // ✅ 최대 입력 길이 4자리 제한
            focusNode: _focusNode,
            // ✅ 자동 포커스 적용
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '번호판 뒷 4자리 입력'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        // 🔹 입력이 4자리일 때만 검색 버튼 활성화
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, child) {
            return TextButton(
              onPressed: value.text.length == 4
                  ? () {
                      widget.onSearch(_searchController.text);
                      Navigator.pop(context);
                    }
                  : null, // ✅ 4자리 미만 입력 시 버튼 비활성화
              child: const Text('검색'),
            );
          },
        ),
      ],
    );
  }
}
