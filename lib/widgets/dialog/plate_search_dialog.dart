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
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(''),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          TextField(
            controller: _searchController,
            maxLength: 4,
            focusNode: _focusNode,
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
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, child) {
            return TextButton(
              onPressed: value.text.length == 4
                  ? () {
                      widget.onSearch(_searchController.text);
                      Navigator.pop(context);
                    }
                  : null,
              child: const Text('검색'),
            );
          },
        ),
      ],
    );
  }
}
