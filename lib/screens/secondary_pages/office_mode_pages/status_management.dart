import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/show_snackbar.dart';
import '../../../states/status_state.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart';

class StatusManagement extends StatelessWidget {
  const StatusManagement({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final statusState = context.watch<StatusState>();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: Column(
        children: [
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
          Expanded(
            child: ListView.builder(
              itemCount: statusState.toggleItems.length,
              itemBuilder: (context, index) {
                final item = statusState.toggleItems[index];

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300), // 애니메이션 지속 시간
                  curve: Curves.easeInOut, // 부드러운 애니메이션
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusState.selectedItemId == item['id']
                        ? Colors.blue.withOpacity(0.2) // 선택된 경우 배경색
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusState.selectedItemId == item['id']
                          ? Colors.blue // 선택된 경우 파란 테두리
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    title: Text(
                      item['name'],
                      style: TextStyle(
                        color: statusState.selectedItemId == item['id']
                            ? Colors.blue // 선택된 경우 글자 색상 변경
                            : Colors.black,
                        fontWeight: statusState.selectedItemId == item['id']
                            ? FontWeight.bold // 선택된 경우 글자 굵게
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusState.selectedItemId == item['id'])
                          const Icon(Icons.check_circle, color: Colors.blue), // 선택된 항목에 체크 아이콘 표시
                        Switch(
                          value: item['isActive'],
                          onChanged: (value) {
                            statusState.toggleItem(item['id']);
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      if (statusState.selectedItemId == item['id']) {
                        statusState.selectItem(null); // 선택 해제
                      } else {
                        statusState.selectItem(item['id']); // 항목 선택
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: const [
          Icons.add,
          Icons.delete,
          Icons.question_mark,
        ],
        onIconTapped: (index) {
          if (index == 0) {
            if (statusState.textController.text.isNotEmpty) {
              statusState.addToggleItem(statusState.textController.text);
              statusState.textController.clear();
            } else {
              showSnackbar(context, "항목 이름을 입력하세요.");
            }
          } else if (index == 1) {
            if (statusState.selectedItemId != null) {
              statusState.removeToggleItem(statusState.selectedItemId!);
            } else {
              showSnackbar(context, "삭제할 항목을 선택하세요.");
            }
          } else if (index == 2) {
            showSnackbar(context, "도움말 버튼 클릭됨");
          }
        },
      ),
    );
  }
}
