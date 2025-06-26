import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../states/status/status_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';

class StatusManagement extends StatelessWidget {
  const StatusManagement({super.key});

  @override
  Widget build(BuildContext context) {
    final statusState = context.watch<StatusState>();

    // ✨ 캐시 상태 디버그 출력
    debugPrint(
      '[DEBUG] StatusManagement 화면 빌드 → 캐시된 상태 수: ${statusState.toggleItems.length}, isLoading: ${statusState.isLoading}',
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '차량상태',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: '캐시 초기화 및 새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              debugPrint('[DEBUG] 수동 새로고침 트리거 → Firestore 호출 예상');
              await statusState.manualRefresh();
              showSuccessSnackbar(context, '상태 데이터 새로고침 완료');
            },
          ),
        ],
      ),
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
                  onPressed: () async {
                    final newName = statusState.textController.text.trim();
                    if (newName.isNotEmpty) {
                      debugPrint('[DEBUG] 상태 항목 추가 트리거 → Firestore 호출 예상 (이름: $newName)');
                      await statusState.addToggleItem(newName); // Firestore 호출 + 캐시 갱신
                      statusState.textController.clear();
                    } else {
                      showFailedSnackbar(context, "항목 이름을 입력하세요.");
                    }
                  },
                  child: const Text("추가"),
                ),
              ],
            ),
          ),
          Expanded(
            child: statusState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: statusState.toggleItems.length,
              itemBuilder: (context, index) {
                final item = statusState.toggleItems[index];

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusState.selectedItemId == item.id
                        ? Colors.blue.withAlpha((0.2 * 255).toInt())
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusState.selectedItemId == item.id
                          ? Colors.blue
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    title: Text(
                      item.name,
                      style: TextStyle(
                        color: statusState.selectedItemId == item.id
                            ? Colors.blue
                            : Colors.black,
                        fontWeight: statusState.selectedItemId == item.id
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusState.selectedItemId == item.id)
                          const Icon(Icons.check_circle, color: Colors.blue),
                        Switch(
                          value: item.isActive,
                          onChanged: (value) async {
                            debugPrint(
                                '[DEBUG] 상태 토글 트리거 → Firestore 호출 예상 (ID: ${item.id}, newState: $value)');
                            await statusState.toggleItem(item.id); // Firestore 호출 + 캐시 갱신
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      statusState.selectItem(
                        statusState.selectedItemId == item.id ? null : item.id,
                      );
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
          Icons.refresh,
        ],
        onIconTapped: (index) async {
          if (index == 0) {
            final newName = statusState.textController.text.trim();
            if (newName.isNotEmpty) {
              debugPrint('[DEBUG] 상태 항목 추가 트리거 (BottomNav) → Firestore 호출 예상');
              await statusState.addToggleItem(newName);
              statusState.textController.clear();
              showSuccessSnackbar(context, "항목이 추가되었습니다.");
            } else {
              showFailedSnackbar(context, "항목 이름을 입력하세요.");
            }
          } else if (index == 1) {
            if (statusState.selectedItemId != null) {
              debugPrint(
                  '[DEBUG] 상태 항목 삭제 트리거 → Firestore 호출 예상 (ID: ${statusState.selectedItemId})');
              await statusState.removeToggleItem(statusState.selectedItemId!); // Firestore 호출 + 캐시 갱신
              showSuccessSnackbar(context, "항목이 삭제되었습니다.");
            } else {
              showFailedSnackbar(context, "삭제할 항목을 선택하세요.");
            }
          } else if (index == 2) {
            debugPrint('[DEBUG] 수동 새로고침 트리거 (BottomNav) → Firestore 호출 예상');
            await statusState.manualRefresh(); // 수동 새로고침 트리거
            showSuccessSnackbar(context, "상태 데이터 새로고침 완료");
          }
        },
      ),
    );
  }
}
