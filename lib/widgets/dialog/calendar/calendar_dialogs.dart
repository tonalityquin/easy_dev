import 'package:flutter/cupertino.dart';

typedef OnMemoSaved = void Function(String memo);

void showAddMemoDialog({
  required BuildContext context,
  required OnMemoSaved onSave,
}) {
  String tempMemo = '';
  final controller = TextEditingController();

  showCupertinoDialog(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('메모 입력'),
      content: Column(
        children: [
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: controller,
            placeholder: '메모를 입력하세요',
            maxLines: 3,
            onChanged: (value) => tempMemo = value,
            autofocus: true,
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('취소'),
          onPressed: () => Navigator.pop(context),
        ),
        CupertinoDialogAction(
          child: const Text('완료'),
          onPressed: () {
            onSave(tempMemo);
            Navigator.pop(context);
            showCupertinoSnackBar(context, '메모가 저장되었습니다!');
          },
        ),
      ],
    ),
  );
}

void showEditMemoDialog({
  required BuildContext context,
  required String initialMemo,
  required OnMemoSaved onSave,
}) {
  String tempMemo = initialMemo;
  final controller = TextEditingController(text: initialMemo);

  showCupertinoDialog(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('메모 수정'),
      content: Column(
        children: [
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: controller,
            maxLines: 3,
            onChanged: (value) => tempMemo = value,
            autofocus: true,
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('취소'),
          onPressed: () => Navigator.pop(context),
        ),
        CupertinoDialogAction(
          child: const Text('저장'),
          onPressed: () {
            onSave(tempMemo);
            Navigator.pop(context);
            showCupertinoSnackBar(context, '메모가 수정되었습니다!');
          },
        ),
      ],
    ),
  );
}

/// iOS 스타일의 간단한 스낵바 대체
void showCupertinoSnackBar(BuildContext context, String message) {
  showCupertinoDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => CupertinoAlertDialog(
      content: Text(message),
    ),
  );

  Future.delayed(const Duration(seconds: 1), () {
    Navigator.of(context, rootNavigator: true).pop();
  });
}
