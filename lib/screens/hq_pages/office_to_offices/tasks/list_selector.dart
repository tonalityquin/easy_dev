import 'package:flutter/material.dart';

/// 목록 선택용 ChoiceChip을 가로 스크롤로 표시
Widget buildListSelector({
  required Map<String, List<dynamic>> todoLists,
  required String currentList,
  required ValueChanged<String> onSelected,
}) {
  return SizedBox(
    height: 40, // AppBar 안에서 높이 제한
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: todoLists.keys.map((listName) {
          final isSelected = listName == currentList;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(
                listName,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              selected: isSelected,
              selectedColor: Colors.blueAccent,
              backgroundColor: Colors.grey[200],
              onSelected: (_) => onSelected(listName),
              elevation: isSelected ? 2 : 0,
            ),
          );
        }).toList(),
      ),
    ),
  );
}
