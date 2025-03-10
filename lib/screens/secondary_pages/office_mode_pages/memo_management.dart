import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/show_snackbar.dart';
import '../../../states/memo_state.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class MemoManagement extends StatelessWidget {
  const MemoManagement({super.key});

  @override
  Widget build(BuildContext context) {
    final memoState = context.watch<MemoState>();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: Column(
        children: [
          _buildInputField(context, memoState),
          Expanded(child: _buildMemoList(memoState)),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, memoState),
    );
  }

  /// 입력 필드 위젯
  Widget _buildInputField(BuildContext context, MemoState memoState) {
    return Padding(
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
          ElevatedButton(
            onPressed: () => _addMemo(context, memoState),
            child: const Text("추가"),
          ),
        ],
      ),
    );
  }

  /// 메모 리스트 위젯
  Widget _buildMemoList(MemoState memoState) {
    return ListView.builder(
      itemCount: memoState.memo.length,
      itemBuilder: (context, index) {
        final item = memoState.memo[index];
        final bool isSelected = memoState.selectedMemoId == item['id'];

        return ListTile(
          title: Text(
            item['name'],
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.black,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          tileColor: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: item['isActive'],
                onChanged: (_) => memoState.toggleMemo(item['id']),
              ),
              if (isSelected) const Icon(Icons.check_circle, color: Colors.blue),
            ],
          ),
          selected: isSelected,
          onTap: () => memoState.selectMemo(item['id']),
        );
      },
    );
  }

  /// 하단 내비게이션 바 위젯
  Widget _buildBottomNavigationBar(BuildContext context, MemoState memoState) {
    return SecondaryMiniNavigation(
      icons: const [Icons.add, Icons.delete],
      onIconTapped: (index) {
        if (index == 0) {
          _addMemo(context, memoState);
        } else if (index == 1) {
          _deleteMemo(context, memoState);
        }
      },
    );
  }

  /// 메모 추가 함수
  void _addMemo(BuildContext context, MemoState memoState) {
    if (memoState.textController.text.isNotEmpty) {
      memoState.addMemo(memoState.textController.text);
      memoState.textController.clear();
    } else {
      showSnackbar(context, "항목 이름을 입력하세요.");
    }
  }

  /// 메모 삭제 함수
  void _deleteMemo(BuildContext context, MemoState memoState) {
    if (memoState.selectedMemoId != null) {
      memoState.removeMemo(memoState.selectedMemoId!);
    } else {
      showSnackbar(context, "삭제할 항목을 선택하세요.");
    }
  }
}
