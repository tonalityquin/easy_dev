import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/show_snackbar.dart';
import '../../../states/memo_state.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class MemoManagement extends StatelessWidget {
  const MemoManagement({super.key}); // 위젯을 생성할 때, 기본 키 값(key)을 받아 상수로 선언하여 성능을 최적화한다.

  @override
  Widget build(BuildContext context) {
    final memoState = context.watch<MemoState>(); // MemoState의 상태를 실시간으로 감지하고 업데이트된 값을 가져온다.

    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 보조 페이지의 항목 선택
      body: Column(
        children: [
          // 입력 필드
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: memoState.textController,
                    decoration: const InputDecoration(
                      labelText: "항목 이름",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 추가 버튼
                ElevatedButton(
                  onPressed: () {
                    if (memoState.textController.text.isNotEmpty) {
                      memoState.addToggleItem(
                        memoState.textController.text,
                      );
                      memoState.textController.clear();
                    }
                  },
                  child: const Text("추가"),
                ),
              ],
            ),
          ),
          // 토글 항목 리스트
          Expanded(
            child: ListView.builder(
              itemCount: memoState.memos.length,
              itemBuilder: (context, index) {
                final item = memoState.memos[index];
                final bool isSelected = memoState.selectedItemId == item['id'];

                return ListTile(
                  title: Text(
                    item['name'],
                    style: TextStyle(
                      color: isSelected ? Colors.blue : Colors.black, // ✅ 선택된 항목 글자색 변경
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // ✅ 선택된 항목 강조
                    ),
                  ),
                  tileColor: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent, // ✅ 선택된 항목 배경색 변경
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item['isActive'],
                        onChanged: (value) {
                          memoState.toggleItem(item['id']);
                        },
                      ),
                      if (isSelected) Icon(Icons.check_circle, color: Colors.blue), // ✅ 선택된 경우 체크 아이콘 표시
                    ],
                  ),
                  selected: isSelected,
                  onTap: () {
                    memoState.selectItem(item['id']);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: const [
          Icons.add, // 추가 버튼
          Icons.delete, // 삭제 버튼
          Icons.question_mark, // 도움말 버튼
        ],
        onIconTapped: (index) {
          if (index == 0) {
            // 추가 버튼 클릭 시
            if (memoState.textController.text.isNotEmpty) {
              memoState.addToggleItem(
                memoState.textController.text,
              );
              memoState.textController.clear();
            } else {
              showSnackbar(context, "항목 이름을 입력하세요."); // ✅ showSnackbar 적용
            }
          } else if (index == 1) {
            // 삭제 버튼 클릭 시
            if (memoState.selectedItemId != null) {
              memoState.removeToggleItem(memoState.selectedItemId!);
            } else {
              showSnackbar(context, "삭제할 항목을 선택하세요."); // ✅ showSnackbar 적용
            }
          } else if (index == 2) {
            // 도움말 버튼 클릭 시
            showSnackbar(context, "도움말 버튼 클릭됨"); // ✅ showSnackbar 적용
          }
        },
      ),
    );
  }
}
