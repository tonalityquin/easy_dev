import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart'; // ✅ Snackbar 유틸 추가

class BreakDocumentBody extends StatelessWidget {
  final TextEditingController controller;
  final bool menuOpen;
  final int? selectedRow;
  final int? selectedCol;
  final List<UserModel> users;
  final Map<String, Map<int, String>> cellData;
  final void Function(int rowIndex, int colIndex, String rowKey) onCellTapped;
  final Future<void> Function(String rowKey) appendText;
  final Future<void> Function(String rowKey) clearText;
  final VoidCallback toggleMenu;
  final Future<List<UserModel>> Function(String area) getUsersByArea;
  final Future<void> Function(String area) reloadUsers; // ✅ 추가

  const BreakDocumentBody({
    super.key,
    required this.controller,
    required this.menuOpen,
    required this.selectedRow,
    required this.selectedCol,
    required this.users,
    required this.cellData,
    required this.onCellTapped,
    required this.appendText,
    required this.clearText,
    required this.toggleMenu,
    required this.getUsersByArea,
    required this.reloadUsers, // ✅ 추가
  });

  Widget _buildCell({
    required String text,
    required bool isHeader,
    required bool isSelected,
    VoidCallback? onTap,
    double width = 60,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 40,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: isHeader
              ? Colors.grey.shade200
              : isSelected
              ? Colors.lightBlue.shade100
              : Colors.white,
        ),
        child: (text.contains('\n'))
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: text.split('\n').map((line) {
            return Text(
              line,
              style: TextStyle(
                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            );
          }).toList(),
        )
            : Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedArea = context.watch<AreaState>().currentArea;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('근무자 휴게시간 테이블', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '사용자 목록 새로고침',
            onPressed: () async {
              if (selectedArea.isNotEmpty) {
                await reloadUsers(selectedArea);
              } else {
                showFailedSnackbar(context, '지역을 먼저 선택하세요');
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '추가할 문구 입력',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '직원 휴게 테이블 (${selectedArea.isNotEmpty ? selectedArea : "지역 미선택"})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: FutureBuilder<List<UserModel>>(
                    future: getUsersByArea(selectedArea),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Text('에러: ${snapshot.error}');
                      }

                      final userList = snapshot.data ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: List.generate(33, (index) {
                              if (index == 0) return _buildCell(text: '', isHeader: true, isSelected: false);
                              if (index == 32) return _buildCell(text: '사인란', isHeader: true, isSelected: false, width: 120);
                              return _buildCell(text: '$index', isHeader: true, isSelected: false);
                            }),
                          ),
                          const SizedBox(height: 8),
                          ...userList.asMap().entries.map((entry) {
                            final rowIndex = entry.key;
                            final user = entry.value;
                            final rowKey = user.id;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: List.generate(33, (colIndex) {
                                  if (colIndex == 0) {
                                    return _buildCell(text: user.name, isHeader: true, isSelected: false);
                                  }
                                  if (colIndex == 32) {
                                    return _buildCell(text: '', isHeader: false, isSelected: false, width: 120);
                                  }

                                  final isSel = selectedRow == rowIndex && selectedCol == colIndex;
                                  final text = cellData[rowKey]?[colIndex] ?? '';

                                  return _buildCell(
                                    text: text,
                                    isHeader: false,
                                    isSelected: isSel,
                                    onTap: () => onCellTapped(rowIndex, colIndex, rowKey),
                                  );
                                }),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (menuOpen)
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: () {
                    if (selectedRow != null && selectedRow! < users.length) {
                      final rowKey = users[selectedRow!].id;
                      appendText(rowKey);
                    }
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.save),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'clearBtn',
                  mini: true,
                  onPressed: () {
                    if (selectedRow != null && selectedRow! < users.length) {
                      final rowKey = users[selectedRow!].id;
                      clearText(rowKey);
                    }
                  },
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
                const SizedBox(height: 12),
              ],
            ),
          FloatingActionButton(
            heroTag: 'breakFab',
            onPressed: toggleMenu,
            backgroundColor: Colors.blueAccent,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 300),
              turns: menuOpen ? 0.25 : 0.0,
              child: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
    );
  }
}
