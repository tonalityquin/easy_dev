import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/show_snackbar.dart';
import '../../../states/status_state.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class StatusManagement extends StatelessWidget {
  const StatusManagement({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final statusState = context.watch<StatusState>();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: Column(
        children: [
          // 입력 필드와 추가 버튼
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: statusState.textController,
                    decoration: const InputDecoration(
                      labelText: "항목 이름",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (statusState.textController.text.isNotEmpty) {
                      statusState.addToggleItem(
                        statusState.textController.text,
                      );
                      statusState.textController.clear();
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
              itemCount: statusState.toggleItems.length,
              itemBuilder: (context, index) {
                final item = statusState.toggleItems[index];
                return ListTile(
                  title: Text(item['name']),
                  trailing: Switch(
                    value: item['isActive'],
                    onChanged: (value) {
                      statusState.toggleItem(item['id']);
                    },
                  ),
                  selected: statusState.selectedItemId == item['id'],
                  onTap: () {
                    statusState.selectItem(item['id']);
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
            if (statusState.textController.text.isNotEmpty) {
              statusState.addToggleItem(
                statusState.textController.text,
              );
              statusState.textController.clear();
            } else {
              showSnackbar(context, "항목 이름을 입력하세요."); // ✅ showSnackbar 적용
            }
          } else if (index == 1) {
            // 삭제 버튼 클릭 시
            if (statusState.selectedItemId != null) {
              statusState.removeToggleItem(statusState.selectedItemId!);
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
