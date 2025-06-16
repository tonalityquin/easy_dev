import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../states/secondary/secondary_mode.dart';

void secondaryPickerDialog({
  required BuildContext context,
  required SecondaryMode manageState,
  required String currentStatus,
  required List<String> availableStatus,
}) {
  String tempSelected = currentStatus;
  int outsideTapCount = 0;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "모드 선택",
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  outsideTapCount++;
                  if (outsideTapCount >= 10) {
                    tempSelected = "Dev Mode";
                    manageState.updateManage(tempSelected);
                    Navigator.of(context).pop();
                  }
                },
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    const Text(
                      '모드 선택',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: availableStatus.indexOf(currentStatus),
                        ),
                        itemExtent: 50,
                        onSelectedItemChanged: (index) {
                          tempSelected = availableStatus[index];
                        },
                        children: availableStatus
                            .map((mode) => Center(
                          child: Text(
                            mode,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ))
                            .toList(),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40, top: 20),
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            manageState.updateManage(tempSelected);
                            Navigator.of(context).pop();
                          },
                          onTapDown: (_) {
                            outsideTapCount = 0; // 확인 버튼 누르면 초기화
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 50, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.green, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Text(
                              '확인',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
